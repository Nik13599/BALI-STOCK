import 'database.dart';

class V14SchemaRepository {
  V14SchemaRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<void> ensureSchema() async {
    final db = await _database.database;
    final rows = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='operations' LIMIT 1");
    final sql = rows.isEmpty ? '' : '${rows.first['sql'] ?? ''}';
    if (sql.contains("'spot_stocktake'")) return;

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE operation_lines RENAME TO operation_lines_pre_v14');
        await txn.execute('ALTER TABLE operations RENAME TO operations_pre_v14');

        await txn.execute('''
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
        await txn.execute('''
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

        await txn.execute('''
          INSERT INTO operations(
            id,type,created_at,employee_name,started_at,completed_at,active_seconds,total_seconds,
            supplier_id,supplier_name,document_number,comment,attachment_url,
            source_location_id,source_location_name,target_location_id,target_location_name,correction_of,total_value
          )
          SELECT
            id,type,created_at,employee_name,started_at,completed_at,active_seconds,total_seconds,
            supplier_id,supplier_name,document_number,comment,attachment_url,
            source_location_id,source_location_name,target_location_id,target_location_name,correction_of,total_value
          FROM operations_pre_v14
        ''');
        await txn.execute('''
          INSERT INTO operation_lines(
            id,operation_id,product_id,product_name,category_name,bottle_ml,stock_unit,
            before_total_ml,before_initialized,change_total_ml,after_total_ml,
            unit_cost,line_value,comment,source_location_id,target_location_id
          )
          SELECT
            id,operation_id,product_id,product_name,category_name,bottle_ml,stock_unit,
            before_total_ml,before_initialized,change_total_ml,after_total_ml,
            unit_cost,line_value,comment,source_location_id,target_location_id
          FROM operation_lines_pre_v14
        ''');
        await txn.execute('DROP TABLE operation_lines_pre_v14');
        await txn.execute('DROP TABLE operations_pre_v14');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_operations_created_at ON operations(created_at DESC)');
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}
