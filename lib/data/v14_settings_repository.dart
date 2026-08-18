import '../v14_models.dart';
import 'database.dart';

class V14SettingsRepository {
  V14SettingsRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<StockListViewMode> loadStockViewMode() async {
    final db = await _database.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['v14_stock_view_mode'],
      limit: 1,
    );
    if (rows.isEmpty) return StockListViewMode.compact;
    final value = '${rows.first['value'] ?? ''}';
    for (final mode in StockListViewMode.values) {
      if (mode.name == value) return mode;
    }
    return StockListViewMode.compact;
  }

  Future<void> saveStockViewMode(StockListViewMode mode) async {
    final db = await _database.database;
    await db.insert(
      'app_settings',
      {'key': 'v14_stock_view_mode', 'value': mode.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
