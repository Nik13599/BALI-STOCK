import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';
import 'database.dart';

class RemoteSyncRepository {
  RemoteSyncRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<void> applySnapshot(Map<String, dynamic> snapshot) async {
    final remoteProducts = (snapshot['products'] as List?)?.whereType<Map>().toList(growable: false) ?? const [];
    if (remoteProducts.isEmpty) return;
    final remoteOperations = (snapshot['operations'] as List?)?.whereType<Map>().toList(growable: false) ?? const [];
    final remoteDrafts = (snapshot['drafts'] as List?)?.whereType<Map>().toList(growable: false) ?? const [];
    final db = await _database.database;

    await db.transaction((txn) async {
      final localProductByRemoteKey = <String, int>{};
      final categoryByName = <String, int>{};

      for (final raw in remoteProducts) {
        final name = '${raw['name'] ?? ''}'.trim();
        final categoryName = '${raw['category_name'] ?? 'Прочее'}'.trim();
        if (name.isEmpty) continue;
        final categorySort = _asInt(raw['category_sort']);
        final packageSize = _asInt(raw['package_size'], fallback: 1).clamp(1, 1 << 31);
        final unit = StockUnitX.fromDb(raw['stock_unit'] as String?);
        final minimum = _asInt(raw['minimum_amount']);
        final active = raw['active'] != false;
        final remoteKey = '${raw['product_key'] ?? ''}';

        var categoryId = categoryByName[categoryName];
        if (categoryId == null) {
          final categoryRows = await txn.query('categories', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [categoryName], limit: 1);
          if (categoryRows.isEmpty) {
            categoryId = await txn.insert('categories', {'name': categoryName, 'sort_order': categorySort});
          } else {
            categoryId = categoryRows.first['id'] as int;
            await txn.update('categories', {'sort_order': categorySort}, where: 'id = ?', whereArgs: [categoryId]);
          }
          categoryByName[categoryName] = categoryId;
        }

        final balanceRaw = raw['balance'];
        final balance = balanceRaw is Map ? balanceRaw : null;
        final initialized = balance?['initialized'] == true;
        final quantity = balance?['quantity_base'] == null ? 0 : _asInt(balance?['quantity_base']);
        final whole = unit == StockUnit.piece ? quantity : quantity ~/ packageSize;
        final extra = unit == StockUnit.piece ? 0 : quantity % packageSize;

        final existing = await txn.query('products', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
        final values = <String, Object?>{
          'name': name,
          'category_id': categoryId,
          'bottle_ml': unit == StockUnit.piece ? 1 : packageSize,
          'whole_bottles': whole,
          'extra_ml': extra,
          'minimum_ml': minimum,
          'stock_unit': unit.dbValue,
          'stock_initialized': initialized ? 1 : 0,
          'active': active ? 1 : 0,
        };
        final int localId;
        if (existing.isEmpty) {
          localId = await txn.insert('products', {...values, 'created_at': DateTime.now().toIso8601String()});
        } else {
          localId = existing.first['id'] as int;
          await txn.update('products', values, where: 'id = ?', whereArgs: [localId]);
        }
        if (remoteKey.isNotEmpty) localProductByRemoteKey[remoteKey] = localId;
      }

      await txn.delete('operation_lines');
      await txn.delete('operations');
      for (final rawOperation in remoteOperations) {
        final localOperationId = await txn.insert('operations', {
          'type': rawOperation['operation_type'] == 'delivery' ? 'delivery' : 'stocktake',
          'created_at': '${rawOperation['created_at']}',
          'employee_name': rawOperation['employee_name'],
          'started_at': rawOperation['started_at'],
          'completed_at': rawOperation['completed_at'],
          'active_seconds': _asInt(rawOperation['active_seconds']),
          'total_seconds': _asInt(rawOperation['total_seconds']),
        });
        final lines = (rawOperation['lines'] as List?)?.whereType<Map>() ?? const Iterable<Map>.empty();
        for (final line in lines) {
          int? productId = localProductByRemoteKey['${line['product_key'] ?? ''}'];
          if (productId == null) {
            final rows = await txn.query('products', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: ['${line['product_name'] ?? ''}'], limit: 1);
            if (rows.isNotEmpty) productId = rows.first['id'] as int;
          }
          if (productId == null) continue;
          await txn.insert('operation_lines', {
            'operation_id': localOperationId,
            'product_id': productId,
            'product_name': '${line['product_name'] ?? ''}',
            'category_name': '${line['category_name'] ?? ''}',
            'bottle_ml': _asInt(line['package_size'], fallback: 1),
            'stock_unit': '${line['stock_unit'] ?? 'ml'}',
            'before_total_ml': line['before_quantity'] == null ? 0 : _asInt(line['before_quantity']),
            'before_initialized': line['before_initialized'] == true ? 1 : 0,
            'change_total_ml': _asInt(line['change_quantity']),
            'after_total_ml': _asInt(line['after_quantity']),
          });
        }
      }

      for (final remoteDraft in remoteDrafts) {
        await _mergeRemoteDraft(txn, remoteDraft);
      }
    });
  }

  Future<StocktakeDraft> readDraft(int draftId) async {
    final db = await _database.database;
    return _readDraft(db, draftId);
  }

  Future<StocktakeDraft?> readDraftByEmployee(String employeeName) async {
    final db = await _database.database;
    final rows = await db.query('stocktake_drafts', columns: ['id'], where: 'employee_name = ? COLLATE NOCASE', whereArgs: [employeeName.trim()], limit: 1);
    if (rows.isEmpty) return null;
    return _readDraft(db, rows.first['id'] as int);
  }

  Future<void> _mergeRemoteDraft(DatabaseExecutor txn, Map remoteDraft) async {
    final employee = '${remoteDraft['employee_name'] ?? ''}'.trim();
    if (employee.isEmpty) return;
    final remoteUpdated = DateTime.tryParse('${remoteDraft['updated_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final existing = await txn.query('stocktake_drafts', columns: ['id', 'updated_at'], where: 'employee_name = ? COLLATE NOCASE', whereArgs: [employee], limit: 1);
    if (existing.isNotEmpty) {
      final localUpdated = DateTime.tryParse('${existing.first['updated_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (!remoteUpdated.isAfter(localUpdated)) return;
      await txn.delete('stocktake_drafts', where: 'id = ?', whereArgs: [existing.first['id']]);
    }

    final payloadRaw = remoteDraft['payload'];
    final payload = payloadRaw is Map ? payloadRaw : const <String, dynamic>{};
    final linePayloads = (payload['lines'] as List?)?.whereType<Map>().toList(growable: false) ?? const [];
    if (linePayloads.isEmpty) return;
    final draftId = await txn.insert('stocktake_drafts', {
      'employee_name': employee,
      'status': remoteDraft['status'] == 'in_progress' ? 'in_progress' : 'draft',
      'started_at': '${remoteDraft['started_at']}',
      'updated_at': '${remoteDraft['updated_at']}',
      'active_seconds': _asInt(remoteDraft['active_seconds']),
      'last_product_id': null,
      'total_count': _asInt(remoteDraft['total_count'], fallback: linePayloads.length),
    });

    for (final line in linePayloads) {
      final productName = '${line['product_name'] ?? ''}';
      final products = await txn.query('products', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [productName], limit: 1);
      if (products.isEmpty) continue;
      await txn.insert('stocktake_draft_lines', {
        'draft_id': draftId,
        'product_id': products.first['id'] as int,
        'product_name': productName,
        'category_name': '${line['category_name'] ?? ''}',
        'package_size': _asInt(line['package_size'], fallback: 1),
        'stock_unit': '${line['stock_unit'] ?? 'ml'}',
        'before_total': _asInt(line['before_total']),
        'before_initialized': line['before_initialized'] == true ? 1 : 0,
        'sort_order': _asInt(line['sort_order']),
        'whole_packages': line['whole_packages'] == null ? null : _asInt(line['whole_packages']),
        'extra_amount': line['extra_amount'] == null ? null : _asInt(line['extra_amount']),
      });
    }
  }

  Future<StocktakeDraft> _readDraft(DatabaseExecutor db, int draftId) async {
    final rows = await db.query('stocktake_drafts', where: 'id = ?', whereArgs: [draftId], limit: 1);
    if (rows.isEmpty) throw StateError('Черновик переучёта не найден');
    final row = rows.first;
    final lineRows = await db.query('stocktake_draft_lines', where: 'draft_id = ?', whereArgs: [draftId], orderBy: 'sort_order');
    final lines = lineRows
        .map((line) => SavedStocktakeLine(
              productId: line['product_id'] as int,
              productName: line['product_name'] as String,
              categoryName: line['category_name'] as String,
              packageSize: line['package_size'] as int,
              stockUnit: StockUnitX.fromDb(line['stock_unit'] as String?),
              beforeTotal: line['before_total'] as int,
              beforeInitialized: (line['before_initialized'] as int? ?? 1) == 1,
              sortOrder: line['sort_order'] as int,
              wholePackages: line['whole_packages'] as int?,
              extraAmount: line['extra_amount'] as int?,
            ))
        .toList(growable: false);
    return StocktakeDraft(
      id: draftId,
      employeeName: row['employee_name'] as String,
      status: StocktakeDraftStatusX.fromDb(row['status'] as String?),
      startedAt: DateTime.parse(row['started_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      activeSeconds: row['active_seconds'] as int,
      lastProductId: row['last_product_id'] as int?,
      totalCount: row['total_count'] as int,
      filledCount: lines.where((line) => line.isFilled).length,
      lines: lines,
    );
  }

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}
