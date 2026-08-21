import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';
import 'database.dart';
import 'offline_sync_queue.dart';

class OfflineMutationRepository {
  OfflineMutationRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;
  final Random _random = Random.secure();

  Future<void> ensureSchema() async {
    final db = await _database.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action_id TEXT NOT NULL UNIQUE,
        action_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_order ON sync_outbox(id)');
  }

  String _newActionId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'bali-$t-$r';
  }

  Future<String> enqueue(String actionType, Map<String, dynamic> payload) async {
    return enqueueLatest(actionType, payload);
  }

  Future<String> enqueueLatest(
    String actionType,
    Map<String, dynamic> payload, {
    String? coalesceKey,
  }) async {
    await ensureSchema();
    final db = await _database.database;
    final actionId = _newActionId();
    final body = <String, dynamic>{
      ...payload,
      'client_action_id': actionId,
      if (coalesceKey != null) 'client_coalesce_key': coalesceKey,
    };
    await db.transaction((txn) async {
      if (coalesceKey != null) {
        final existing = await txn.query(
          'sync_outbox',
          columns: ['id', 'payload_json'],
          where: 'action_type = ?',
          whereArgs: [actionType],
        );
        for (final row in existing) {
          try {
            final decoded = jsonDecode(row['payload_json'] as String);
            if (decoded is Map && decoded['client_coalesce_key'] == coalesceKey) {
              await txn.delete('sync_outbox', where: 'id = ?', whereArgs: [row['id']]);
            }
          } catch (_) {
            // Keep an unreadable legacy entry for normal retry/error reporting.
          }
        }
      }
      await txn.insert('sync_outbox', {
        'action_id': actionId,
        'action_type': actionType,
        'payload_json': jsonEncode(body),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'attempts': 0,
      });
    });
    return actionId;
  }

  Future<void> removeCoalesced(String actionType, String coalesceKey) async {
    await ensureSchema();
    final db = await _database.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'sync_outbox',
        columns: ['id', 'payload_json'],
        where: 'action_type = ?',
        whereArgs: [actionType],
      );
      for (final row in existing) {
        try {
          final decoded = jsonDecode(row['payload_json'] as String);
          if (decoded is Map && decoded['client_coalesce_key'] == coalesceKey) {
            await txn.delete('sync_outbox', where: 'id = ?', whereArgs: [row['id']]);
          }
        } catch (_) {
          // Do not delete an entry whose identity cannot be verified.
        }
      }
    });
  }

  Future<int> pendingCount() async {
    await ensureSchema();
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_outbox');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<PendingSyncAction?> nextPending() async {
    await ensureSchema();
    final db = await _database.database;
    final rows = await db.query('sync_outbox', orderBy: 'id', limit: 1);
    return rows.isEmpty ? null : PendingSyncAction.fromMap(rows.first);
  }

  Future<void> markFailed(int id, Object error) async {
    final db = await _database.database;
    await db.rawUpdate(
      'UPDATE sync_outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error.toString(), id],
    );
  }

  Future<void> removePending(int id) async {
    final db = await _database.database;
    await db.delete('sync_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> applyDelivery({
    required List<DeliveryDraftLine> lines,
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? comment,
    String? attachmentUrl,
    String? locationId,
  }) async {
    if (lines.isEmpty) throw ArgumentError('Добавьте хотя бы одну позицию поставки');
    final db = await _database.database;
    late int operationId;
    await db.transaction((txn) async {
      operationId = await txn.insert('operations', {
        'type': 'delivery',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'employee_name': employee.trim().isEmpty ? null : employee.trim(),
        'supplier_id': supplierId,
        'document_number': documentNumber,
        'comment': comment,
        'attachment_url': attachmentUrl,
        'target_location_id': locationId,
      });
      for (final line in lines) {
        final current = await _readProduct(txn, line.product.id);
        if (!current.stockInitialized) {
          throw StateError('Сначала проведите первичный переучёт. Остаток ${current.name} ещё не введён.');
        }
        final added = line.addedMl;
        if (added <= 0) throw ArgumentError('Количество поставки должно быть больше нуля: ${current.name}');
        final before = current.totalAmount;
        final after = before + added;
        await _writeProductQuantity(txn, current, after);
        await _insertLine(
          txn,
          operationId: operationId,
          product: current,
          before: before,
          beforeInitialized: true,
          change: added,
          after: after,
          unitCost: line.unitCost,
          lineValue: line.unitCost == null ? null : line.unitCost! * (current.stockUnit == StockUnit.piece ? added : added / current.packageSize),
          comment: line.sourceText,
          targetLocationId: locationId,
        );
      }
    });
    return operationId;
  }

  Future<int> applyWriteOff({
    required String employee,
    required String reason,
    required List<DeliveryDraftLine> lines,
    String? locationId,
    String? comment,
  }) async {
    if (lines.isEmpty) throw ArgumentError('Добавьте хотя бы одну позицию списания');
    final db = await _database.database;
    late int operationId;
    await db.transaction((txn) async {
      operationId = await txn.insert('operations', {
        'type': 'writeoff',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'employee_name': employee.trim(),
        'comment': [reason.trim(), comment?.trim()].where((x) => x != null && x!.isNotEmpty).join(' • '),
        'source_location_id': locationId,
      });
      for (final line in lines) {
        final current = await _readProduct(txn, line.product.id);
        if (!current.stockInitialized) throw StateError('Остаток ${current.name} ещё не введён');
        final amount = line.addedMl;
        if (amount <= 0) throw ArgumentError('Количество списания должно быть больше нуля: ${current.name}');
        final before = current.totalAmount;
        if (amount > before) throw StateError('Нельзя списать больше текущего остатка: ${current.name}');
        final after = before - amount;
        await _writeProductQuantity(txn, current, after);
        await _insertLine(
          txn,
          operationId: operationId,
          product: current,
          before: before,
          beforeInitialized: true,
          change: -amount,
          after: after,
          comment: line.sourceText ?? reason,
          sourceLocationId: locationId,
        );
      }
    });
    return operationId;
  }

  Future<int> applyTransfer({
    required String employee,
    required String sourceLocationId,
    required String targetLocationId,
    required List<DeliveryDraftLine> lines,
    String? comment,
  }) async {
    if (sourceLocationId == targetLocationId) throw ArgumentError('Источник и место назначения должны отличаться');
    if (lines.isEmpty) throw ArgumentError('Добавьте хотя бы одну позицию перемещения');
    final db = await _database.database;
    late int operationId;
    await db.transaction((txn) async {
      operationId = await txn.insert('operations', {
        'type': 'transfer',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'employee_name': employee.trim(),
        'comment': comment,
        'source_location_id': sourceLocationId,
        'target_location_id': targetLocationId,
      });
      for (final line in lines) {
        final current = await _readProduct(txn, line.product.id);
        final amount = line.addedMl;
        if (amount <= 0) throw ArgumentError('Количество перемещения должно быть больше нуля: ${current.name}');
        if (current.stockInitialized && amount > current.totalAmount) {
          throw StateError('Перемещение превышает общий остаток: ${current.name}');
        }
        final before = current.stockInitialized ? current.totalAmount : 0;
        await _insertLine(
          txn,
          operationId: operationId,
          product: current,
          before: before,
          beforeInitialized: current.stockInitialized,
          change: 0,
          after: before,
          sourceLocationId: sourceLocationId,
          targetLocationId: targetLocationId,
        );
      }
    });
    return operationId;
  }

  Future<int> applyCorrection({
    required String employee,
    required String reason,
    required Map<Product, int> deltas,
    String? locationId,
    String? correctionOf,
  }) async {
    final effective = deltas.entries.where((x) => x.value != 0).toList(growable: false);
    if (effective.isEmpty) throw ArgumentError('Нет изменений для корректировки');
    final db = await _database.database;
    late int operationId;
    await db.transaction((txn) async {
      operationId = await txn.insert('operations', {
        'type': 'correction',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'employee_name': employee.trim(),
        'comment': reason.trim(),
        'source_location_id': locationId,
        'correction_of': correctionOf,
      });
      for (final entry in effective) {
        final current = await _readProduct(txn, entry.key.id);
        if (!current.stockInitialized) throw StateError('Остаток ${current.name} ещё не введён');
        final before = current.totalAmount;
        final after = before + entry.value;
        if (after < 0) throw StateError('Корректировка сделает остаток отрицательным: ${current.name}');
        await _writeProductQuantity(txn, current, after);
        await _insertLine(
          txn,
          operationId: operationId,
          product: current,
          before: before,
          beforeInitialized: true,
          change: entry.value,
          after: after,
          comment: reason,
          sourceLocationId: locationId,
        );
      }
    });
    return operationId;
  }

  Future<Product> _readProduct(DatabaseExecutor db, int productId) async {
    final rows = await db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM products p
      JOIN categories c ON c.id = p.category_id
      WHERE p.id = ? AND p.active = 1
      LIMIT 1
    ''', [productId]);
    if (rows.isEmpty) throw StateError('Позиция больше не активна');
    final row = rows.first;
    return Product(
      id: row['id'] as int,
      name: row['name'] as String,
      categoryId: row['category_id'] as int,
      categoryName: row['category_name'] as String,
      bottleMl: row['bottle_ml'] as int,
      wholeBottles: row['whole_bottles'] as int,
      extraMl: row['extra_ml'] as int,
      minimumMl: row['minimum_ml'] as int,
      stockUnit: StockUnitX.fromDb(row['stock_unit'] as String?),
      stockInitialized: (row['stock_initialized'] as int? ?? 1) == 1,
      active: (row['active'] as int? ?? 1) == 1,
      targetAmount: (row['target_amount'] as int?) ?? 0,
      barcode: row['barcode'] as String?,
      defaultCost: (row['default_cost'] as num?)?.toDouble(),
      costCurrency: (row['cost_currency'] as String?) ?? 'BYN',
      varianceRecheckAmount: (row['variance_recheck_amount'] as int?) ?? 0,
    );
  }

  Future<void> _writeProductQuantity(DatabaseExecutor db, Product product, int quantity) async {
    final whole = product.stockUnit == StockUnit.piece ? quantity : quantity ~/ product.packageSize;
    final extra = product.stockUnit == StockUnit.piece ? 0 : quantity % product.packageSize;
    await db.update(
      'products',
      {
        'whole_bottles': whole,
        'extra_ml': extra,
        'stock_initialized': 1,
      },
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> _insertLine(
    DatabaseExecutor db, {
    required int operationId,
    required Product product,
    required int before,
    required bool beforeInitialized,
    required int change,
    required int after,
    double? unitCost,
    double? lineValue,
    String? comment,
    String? sourceLocationId,
    String? targetLocationId,
  }) async {
    await db.insert('operation_lines', {
      'operation_id': operationId,
      'product_id': product.id,
      'product_name': product.name,
      'category_name': product.categoryName,
      'bottle_ml': product.packageSize,
      'stock_unit': product.stockUnit.dbValue,
      'before_total_ml': before,
      'before_initialized': beforeInitialized ? 1 : 0,
      'change_total_ml': change,
      'after_total_ml': after,
      'unit_cost': unitCost,
      'line_value': lineValue,
      'comment': comment,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
    });
  }
}
