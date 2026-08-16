import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        version: 1,
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
              active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              FOREIGN KEY(category_id) REFERENCES categories(id)
            )
          ''');
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
              change_total_ml INTEGER NOT NULL,
              after_total_ml INTEGER NOT NULL,
              FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
          await db.execute('CREATE INDEX idx_operations_created_at ON operations(created_at DESC)');
          await _seedCategories(db);
        },
      ),
    );
  }

  static Future<void> _seedCategories(Database db) async {
    const names = <String>[
      'Виски',
      'Ром',
      'Водка',
      'Коньяк / Бренди',
      'Текила',
      'Ликёры',
      'Вермуты / Аперитивы',
      'Вино',
      'Игристое',
      'Пиво',
      'Безалкогольные',
      'Энергетики',
      'Вода',
      'Соки / Пюре',
      'Сиропы',
      'Прочее',
    ];

    final batch = db.batch();
    for (var i = 0; i < names.length; i++) {
      batch.insert('categories', {'name': names[i], 'sort_order': i});
    }
    await batch.commit(noResult: true);
  }
}
