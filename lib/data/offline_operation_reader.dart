import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';
import 'database.dart';

class OfflineOperationReader {
  OfflineOperationReader({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;
  final BaliStockDatabase _database;

  Future<List<StockOperation>> getOperations() async {
    final db = await _database.database;
    final rows = await db.query('operations', orderBy: 'created_at DESC, id DESC');
    final result = <StockOperation>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final lineRows = await db.query(
        'operation_lines',
        where: 'operation_id = ?',
        whereArgs: [id],
        orderBy: 'category_name COLLATE NOCASE, product_name COLLATE NOCASE',
      );
      result.add(StockOperation(
        id: id,
        type: StockOperationTypeX.fromDb(row['type'] as String?),
        createdAt: DateTime.parse(row['created_at'] as String),
        employeeName: row['employee_name'] as String?,
        startedAt: _date(row['started_at']),
        completedAt: _date(row['completed_at']),
        activeSeconds: (row['active_seconds'] as int?) ?? 0,
        totalSeconds: (row['total_seconds'] as int?) ?? 0,
        supplierId: row['supplier_id'] as String?,
        supplierName: row['supplier_name'] as String?,
        documentNumber: row['document_number'] as String?,
        comment: row['comment'] as String?,
        attachmentUrl: row['attachment_url'] as String?,
        sourceLocationId: row['source_location_id'] as String?,
        sourceLocationName: row['source_location_name'] as String?,
        targetLocationId: row['target_location_id'] as String?,
        targetLocationName: row['target_location_name'] as String?,
        correctionOf: row['correction_of'] as String?,
        totalValue: (row['total_value'] as num?)?.toDouble(),
        lines: lineRows.map((line) => StockOperationLine(
          productId: line['product_id'] as int,
          productName: line['product_name'] as String,
          categoryName: line['category_name'] as String,
          bottleMl: line['bottle_ml'] as int,
          stockUnit: StockUnitX.fromDb(line['stock_unit'] as String?),
          beforeTotalMl: line['before_total_ml'] as int,
          beforeInitialized: (line['before_initialized'] as int? ?? 1) == 1,
          changeTotalMl: line['change_total_ml'] as int,
          afterTotalMl: line['after_total_ml'] as int,
          unitCost: (line['unit_cost'] as num?)?.toDouble(),
          lineValue: (line['line_value'] as num?)?.toDouble(),
          comment: line['comment'] as String?,
          sourceLocationId: line['source_location_id'] as String?,
          targetLocationId: line['target_location_id'] as String?,
        )).toList(growable: false),
      ));
    }
    return result;
  }

  DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);
}
