import 'package:sqflite_common/sqlite_api.dart';

Future<void> createOperationTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE operations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL CHECK (type IN ('delivery', 'stocktake', 'spot_stocktake', 'writeoff', 'transfer', 'correction')),
      created_at TEXT NOT NULL,
      employee_name TEXT,
      started_at TEXT,
      completed_at TEXT,
      active_seconds INTEGER NOT NULL DEFAULT 0,
      total_seconds INTEGER NOT NULL DEFAULT 0,
      supplier_id TEXT,
      supplier_name TEXT,
      document_number TEXT,
      comment TEXT,
      attachment_url TEXT,
      source_location_id TEXT,
      source_location_name TEXT,
      target_location_id TEXT,
      target_location_name TEXT,
      correction_of TEXT,
      total_value REAL
    )
  ''');
  await db.execute('''
    CREATE TABLE operation_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      category_name TEXT NOT NULL,
      bottle_ml INTEGER NOT NULL,
      stock_unit TEXT NOT NULL DEFAULT 'ml',
      before_total_ml INTEGER NOT NULL,
      before_initialized INTEGER NOT NULL DEFAULT 1,
      change_total_ml INTEGER NOT NULL,
      after_total_ml INTEGER NOT NULL,
      unit_cost REAL,
      line_value REAL,
      comment TEXT,
      source_location_id TEXT,
      target_location_id TEXT,
      FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
    )
  ''');
}
