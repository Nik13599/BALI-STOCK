import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';
import '../v14_models.dart';
import 'database.dart';

class V14OfflineRepository {
  V14OfflineRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<int> applySpotStocktake({
    required Product product,
    required String employee,
    required int quantityBase,
    required SpotStocktakeReason reason,
    required String device,
    String? comment,
  }) async {
    final cleanEmployee = employee.trim();
    if (cleanEmployee.isEmpty) throw ArgumentError('Укажите ФИО сотрудника');
    if (quantityBase < 0) throw ArgumentError('Остаток не может быть отрицательным');
    if (reason == SpotStocktakeReason.other && (comment ?? '').trim().isEmpty) {
      throw ArgumentError('Для причины «Другая причина» укажите комментарий');
    }

    final db = await _database.database;
    late int operationId;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT p.*, c.name AS category_name
        FROM products p
        JOIN categories c ON c.id = p.category_id
        WHERE p.id = ? AND p.active = 1
        LIMIT 1
      ''', [product.id]);
      if (rows.isEmpty) throw StateError('Позиция больше не активна');
      final row = rows.first;
      final packageSize = row['bottle_ml'] as int;
      final unit = StockUnitX.fromDb(row['stock_unit'] as String?);
      final whole = row['whole_bottles'] as int;
      final extra = row['extra_ml'] as int;
      final initialized = (row['stock_initialized'] as int? ?? 1) == 1;
      final before = initialized ? whole * packageSize + extra : 0;
      final diff = initialized ? quantityBase - before : 0;
      final now = DateTime.now().toIso8601String();
      final reasonComment = <String>[
        reason.label,
        if ((comment ?? '').trim().isNotEmpty) comment!.trim(),
        if (device.trim().isNotEmpty) 'Устройство: ${device.trim()}',
        'Синхронизация: ожидает отправки',
      ].join(' • ');

      operationId = await txn.insert('operations', {
        'type': 'spot_stocktake',
        'created_at': now,
        'employee_name': cleanEmployee,
        'started_at': now,
        'completed_at': now,
        'active_seconds': 0,
        'total_seconds': 0,
        'comment': reasonComment,
      });

      final normalizedWhole = unit == StockUnit.piece ? quantityBase : quantityBase ~/ packageSize;
      final normalizedExtra = unit == StockUnit.piece ? 0 : quantityBase % packageSize;
      await txn.update(
        'products',
        {
          'whole_bottles': normalizedWhole,
          'extra_ml': normalizedExtra,
          'stock_initialized': 1,
        },
        where: 'id = ?',
        whereArgs: [product.id],
      );

      await txn.insert('operation_lines', {
        'operation_id': operationId,
        'product_id': product.id,
        'product_name': product.name,
        'category_name': product.categoryName,
        'bottle_ml': product.packageSize,
        'stock_unit': product.stockUnit.dbValue,
        'before_total_ml': before,
        'before_initialized': initialized ? 1 : 0,
        'change_total_ml': diff,
        'after_total_ml': quantityBase,
        'comment': reasonComment,
      });
    });
    return operationId;
  }
}
