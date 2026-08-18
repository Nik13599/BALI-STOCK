import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'database.dart';

class V14MetaCacheRepository {
  V14MetaCacheRepository({BaliStockDatabase? database}) : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<void> ensureSchema() async {
    final db = await _database.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS v14_meta_cache (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveSnapshot(Map<String, dynamic> snapshot) async {
    await ensureSchema();
    final productsRaw = snapshot['products'];
    final auditRaw = snapshot['catalog_audit'];
    final operationsRaw = snapshot['operations'];

    final products = productsRaw is List
        ? productsRaw.whereType<Map>().map((raw) => {
              'product_key': raw['product_key'],
              'sell_by_bottle': raw['sell_by_bottle'],
              'bottle_sale_price': raw['bottle_sale_price'],
              'portion_sale': raw['portion_sale'],
              'portion_prices': raw['portion_prices'],
              'image_path': raw['image_path'],
              'image_url': raw['image_url'],
            }).toList(growable: false)
        : const [];
    final audit = auditRaw is List ? auditRaw.whereType<Map>().toList(growable: false) : const [];
    final spot = operationsRaw is List
        ? operationsRaw.whereType<Map>().where((x) => '${x['operation_type'] ?? ''}' == 'spot_stocktake').toList(growable: false)
        : const [];

    final db = await _database.database;
    await db.insert(
      'v14_meta_cache',
      {
        'id': 1,
        'payload_json': jsonEncode({'products': products, 'catalog_audit': audit, 'operations': spot}),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadSnapshot() async {
    await ensureSchema();
    final db = await _database.database;
    final rows = await db.query('v14_meta_cache', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['payload_json'] as String);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry('$key', value));
  }
}
