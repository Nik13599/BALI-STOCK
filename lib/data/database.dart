import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'seed_catalog.dart';

class BaliStockDatabase {
  BaliStockDatabase._();

  static final BaliStockDatabase instance = BaliStockDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }

    final dbPath = await factory.getDatabasesPath();
    return factory.openDatabase(
      p.join(dbPath, 'bali_stock.db'),
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              category_id INTEGER NOT NULL,
              bottle_ml INTEGER NOT NULL CHECK (bottle_ml > 0),
              whole_bottles INTEGER NOT NULL DEFAULT 0 CHECK (whole_bottles >= 0),
              extra_ml INTEGER NOT NULL DEFAULT 0 CHECK (extra_ml >= 0),
              minimum_ml INTEGER NOT NULL DEFAULT 0 CHECK (minimum_ml >= 0),
              stock_initialized INTEGER NOT NULL DEFAULT 1,
              active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              FOREIGN KEY(category_id) REFERENCES categories(id)
            )
          ''');
          await _createOperationTables(db);
          await _createIndexes(db);
          await _seedCatalog(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE products ADD COLUMN stock_initialized INTEGER NOT NULL DEFAULT 1');
            await _seedCatalog(db);
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE operation_lines ADD COLUMN before_initialized INTEGER NOT NULL DEFAULT 1');
          }
        },
      ),
    );
  }

  static Future<void> _createOperationTables(Database db) async {
    await db.execute('''
      CREATE TABLE operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK (type IN ('delivery', 'stocktake')),
        created_at TEXT NOT NULL
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
        before_total_ml INTEGER NOT NULL,
        before_initialized INTEGER NOT NULL DEFAULT 1,
        change_total_ml INTEGER NOT NULL,
        after_total_ml INTEGER NOT NULL,
        FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX idx_operations_created_at ON operations(created_at DESC)');
  }

  static Future<void> _seedCatalog(Database db) async {
    final categoryIds = <String, int>{};
    for (var i = 0; i < seedCategories.length; i++) {
      final name = seedCategories[i];
      final existing = await db.query('categories', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      final int id;
      if (existing.isNotEmpty) {
        id = existing.first['id'] as int;
      } else {
        id = await db.insert('categories', {'name': name, 'sort_order': i});
      }
      categoryIds[name] = id;
    }

    final now = DateTime.now().toIso8601String();
    for (final product in seedProducts) {
      final categoryId = categoryIds[product.category]!;
      final existing = await db.rawQuery('''
        SELECT p.id
        FROM products p
        WHERE p.name = ? COLLATE NOCASE
        LIMIT 1
      ''', [product.name]);
      if (existing.isNotEmpty) continue;

      await db.insert('products', {
        'name': product.name,
        'category_id': categoryId,
        'bottle_ml': product.bottleMl,
        'whole_bottles': 0,
        'extra_ml': 0,
        'minimum_ml': 0,
        'stock_initialized': 0,
        'active': 1,
        'created_at': now,
      });
    }
  }
}
