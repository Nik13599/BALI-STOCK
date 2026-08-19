import 'database.dart';
import 'operation_schema.dart';

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

        await createOperationTables(txn);

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
