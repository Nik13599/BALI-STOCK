import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';
import 'database.dart';

class OfflineControlCache {
  const OfflineControlCache({
    required this.suppliers,
    required this.productSuppliers,
    required this.locations,
    required this.locationBalances,
    required this.purchaseSuggestions,
    required this.analytics,
  });

  final List<StockSupplier> suppliers;
  final List<ProductSupplierLink> productSuppliers;
  final List<StockLocation> locations;
  final List<StockLocationBalance> locationBalances;
  final List<PurchaseSuggestion> purchaseSuggestions;
  final StockAnalytics analytics;
}

class OfflineControlCacheRepository {
  OfflineControlCacheRepository({BaliStockDatabase? database})
      : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<void> ensureSchema() async {
    final db = await _database.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_control_cache (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> save({
    required List<StockSupplier> suppliers,
    required List<ProductSupplierLink> productSuppliers,
    required List<StockLocation> locations,
    required List<StockLocationBalance> locationBalances,
    required List<PurchaseSuggestion> purchaseSuggestions,
    required StockAnalytics analytics,
  }) async {
    await ensureSchema();
    final db = await _database.database;
    final payload = {
      'suppliers': suppliers.map((x) => {
        'id': x.id,
        'name': x.name,
        'contact_person': x.contactPerson,
        'phone': x.phone,
        'email': x.email,
        'notes': x.notes,
        'active': x.active,
      }).toList(growable: false),
      'product_suppliers': productSuppliers.map((x) => {
        'product_key': x.productKey,
        'supplier_id': x.supplierId,
        'supplier_sku': x.supplierSku,
        'last_price': x.lastPrice,
        'currency': x.currency,
        'is_primary': x.isPrimary,
        'active': x.active,
      }).toList(growable: false),
      'locations': locations.map((x) => {
        'id': x.id,
        'name': x.name,
        'is_primary': x.isPrimary,
        'active': x.active,
        'sort_order': x.sortOrder,
      }).toList(growable: false),
      'location_balances': locationBalances.map((x) => {
        'location_id': x.locationId,
        'product_key': x.productKey,
        'quantity_base': x.quantityBase,
        'initialized': x.initialized,
      }).toList(growable: false),
      'purchase_suggestions': purchaseSuggestions.map((x) => {
        'product_key': x.productKey,
        'name': x.name,
        'category_name': x.categoryName,
        'stock_unit': x.stockUnit.dbValue,
        'package_size': x.packageSize,
        'current_quantity': x.currentQuantity,
        'minimum_amount': x.minimumAmount,
        'target_amount': x.targetAmount,
        'suggested_quantity': x.suggestedQuantity,
        'preferred_supplier': x.preferredSupplier,
        'last_price': x.lastPrice,
        'currency': x.currency,
      }).toList(growable: false),
      'analytics': {
        'period_days': analytics.periodDays,
        'operations': analytics.operations,
        'deliveries': analytics.deliveries,
        'stocktakes': analytics.stocktakes,
        'writeoffs': analytics.writeoffs,
        'transfers': analytics.transfers,
        'average_stocktake_seconds': analytics.averageStocktakeSeconds,
        'fastest_stocktake_seconds': analytics.fastestStocktakeSeconds,
        'longest_stocktake_seconds': analytics.longestStocktakeSeconds,
        'largest_variances': analytics.largestVariances,
      },
    };
    await db.insert(
      'offline_control_cache',
      {
        'id': 1,
        'payload_json': jsonEncode(payload),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OfflineControlCache?> load() async {
    await ensureSchema();
    final db = await _database.database;
    final rows = await db.query('offline_control_cache', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['payload_json'] as String);
    if (decoded is! Map) return null;

    List<Map<dynamic, dynamic>> maps(Object? value) => value is List
        ? value.whereType<Map>().map((x) => x.cast<dynamic, dynamic>()).toList(growable: false)
        : const [];

    return OfflineControlCache(
      suppliers: maps(decoded['suppliers']).map(StockSupplier.fromJson).toList(growable: false),
      productSuppliers: maps(decoded['product_suppliers']).map(ProductSupplierLink.fromJson).toList(growable: false),
      locations: maps(decoded['locations']).map(StockLocation.fromJson).toList(growable: false),
      locationBalances: maps(decoded['location_balances']).map(StockLocationBalance.fromJson).toList(growable: false),
      purchaseSuggestions: maps(decoded['purchase_suggestions']).map(PurchaseSuggestion.fromJson).toList(growable: false),
      analytics: StockAnalytics.fromJson(decoded['analytics'] is Map ? decoded['analytics'] as Map : null),
    );
  }
}
