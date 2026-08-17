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
        version: 6,
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
              target_amount INTEGER NOT NULL DEFAULT 0 CHECK (target_amount >= 0),
              barcode TEXT,
              default_cost REAL,
              cost_currency TEXT NOT NULL DEFAULT 'BYN',
              variance_recheck_amount INTEGER NOT NULL DEFAULT 0 CHECK (variance_recheck_amount >= 0),
              stock_unit TEXT NOT NULL DEFAULT 'ml',
              stock_initialized INTEGER NOT NULL DEFAULT 1,
              active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              FOREIGN KEY(category_id) REFERENCES categories(id)
            )
          ''');
          await _createOperationTables(db);
          await _createDraftTables(db);
          await _createIndexes(db);
          await _seedCatalog(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE products ADD COLUMN stock_initialized INTEGER NOT NULL DEFAULT 1');
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE operation_lines ADD COLUMN before_initialized INTEGER NOT NULL DEFAULT 1');
          }
          if (oldVersion < 4) {
            await db.execute("ALTER TABLE products ADD COLUMN stock_unit TEXT NOT NULL DEFAULT 'ml'");
            await db.execute("ALTER TABLE operation_lines ADD COLUMN stock_unit TEXT NOT NULL DEFAULT 'ml'");
            await _normalizeLegacyNames(db);
          }
          if (oldVersion < 5) {
            await db.execute('ALTER TABLE operations ADD COLUMN employee_name TEXT');
            await db.execute('ALTER TABLE operations ADD COLUMN started_at TEXT');
            await db.execute('ALTER TABLE operations ADD COLUMN completed_at TEXT');
            await db.execute('ALTER TABLE operations ADD COLUMN active_seconds INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE operations ADD COLUMN total_seconds INTEGER NOT NULL DEFAULT 0');
            await _createDraftTables(db);
          }
          if (oldVersion < 6) {
            await _migrateV6(db);
          }
          await _createIndexes(db);
          await _seedCatalog(db);
        },
        onOpen: (db) async {
          // If the process was killed while counting, treat the session as paused.
          await db.update(
            'stocktake_drafts',
            {'status': 'draft'},
            where: "status = 'in_progress'",
          );
        },
      ),
    );
  }

  static Future<void> _migrateV6(Database db) async {
    await db.execute('ALTER TABLE products ADD COLUMN target_amount INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
    await db.execute('ALTER TABLE products ADD COLUMN default_cost REAL');
    await db.execute("ALTER TABLE products ADD COLUMN cost_currency TEXT NOT NULL DEFAULT 'BYN'");
    await db.execute('ALTER TABLE products ADD COLUMN variance_recheck_amount INTEGER NOT NULL DEFAULT 0');

    // The v5 operations table had a CHECK limited to delivery/stocktake.
    // Rebuild it so the local cache can faithfully mirror all immutable server operations.
    await db.execute('ALTER TABLE operation_lines RENAME TO operation_lines_v5');
    await db.execute('ALTER TABLE operations RENAME TO operations_v5');
    await _createOperationTables(db);

    await db.execute('''
      INSERT INTO operations(
        id,type,created_at,employee_name,started_at,completed_at,active_seconds,total_seconds
      )
      SELECT id,type,created_at,employee_name,started_at,completed_at,active_seconds,total_seconds
      FROM operations_v5
    ''');
    await db.execute('''
      INSERT INTO operation_lines(
        id,operation_id,product_id,product_name,category_name,bottle_ml,stock_unit,
        before_total_ml,before_initialized,change_total_ml,after_total_ml
      )
      SELECT id,operation_id,product_id,product_name,category_name,bottle_ml,stock_unit,
        before_total_ml,before_initialized,change_total_ml,after_total_ml
      FROM operation_lines_v5
    ''');
    await db.execute('DROP TABLE operation_lines_v5');
    await db.execute('DROP TABLE operations_v5');
  }

  static Future<void> _createOperationTables(Database db) async {
    await db.execute('''
      CREATE TABLE operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK (type IN ('delivery', 'stocktake', 'writeoff', 'transfer', 'correction')),
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

  static Future<void> _createDraftTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocktake_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_name TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('draft', 'in_progress')) DEFAULT 'draft',
        started_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        active_seconds INTEGER NOT NULL DEFAULT 0,
        last_product_id INTEGER,
        total_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocktake_draft_lines (
        draft_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        category_name TEXT NOT NULL,
        package_size INTEGER NOT NULL,
        stock_unit TEXT NOT NULL,
        before_total INTEGER NOT NULL DEFAULT 0,
        before_initialized INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        whole_packages INTEGER,
        extra_amount INTEGER,
        PRIMARY KEY (draft_id, product_id),
        FOREIGN KEY(draft_id) REFERENCES stocktake_drafts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL AND barcode <> ""');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_operations_created_at ON operations(created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stocktake_draft_lines_order ON stocktake_draft_lines(draft_id, sort_order)');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_stocktake_drafts_employee_active
      ON stocktake_drafts(employee_name COLLATE NOCASE)
      WHERE status IN ('draft', 'in_progress')
    ''');
  }

  static Future<void> _normalizeLegacyNames(Database db) async {
    const aliases = <String, String>{
      'Johnnie Walker RED Label': 'Johnnie Walker Red Label',
      'Johnnie Walker BLACK Label': 'Johnnie Walker Black Label',
      'Johnnie Walker BLUE Label': 'Johnnie Walker Blue Label',
      'Casillero De Diablo Sauv. Blanc сухое': 'Casillero De Diablo Sauvignon Blanc сухое',
      'Cin Zano Asti': 'Cinzano Asti',
      'Luc Belaire розовое сухое': 'Luc Belaire Rosé',
      'Luc Belaire белое брют': 'Luc Belaire Brut',
      'Veuve Clicquot Brut белое брют': 'Veuve Clicquot Brut',
      'Moet & Chandon Brut белое брют': 'Moët & Chandon Brut',
      'Moet & Chandon Brut розовое брют': 'Moët & Chandon Rosé',
      'Bottega Gold Prosecco белое брют': 'Bottega Gold Prosecco',
      'Bottega Rose Gold Pinot Nero розовое брют': 'Bottega Rose Gold Pinot Nero',
      'Mumm белое брют': 'Mumm Brut',
      'Dom Perignon Brut': 'Dom Pérignon Brut',
      'Кока-Кола': 'Coca-Cola',
      'Швепс': 'Schweppes',
      'Спрайт': 'Sprite',
      'Кока-Кола Zero': 'Coca-Cola Zero',
      'Боровая газ': 'Боровая газированная',
      'Боровая негаз': 'Боровая негазированная',
      'Tassay газ': 'Tassay газированная',
      'Tassay негаз': 'Tassay негазированная',
    };

    for (final entry in aliases.entries) {
      final target = await db.query('products', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [entry.value], limit: 1);
      if (target.isEmpty) {
        await db.update('products', {'name': entry.value}, where: 'name = ? COLLATE NOCASE', whereArgs: [entry.key]);
      }
    }
  }

  static Future<void> _seedCatalog(Database db) async {
    final categoryIds = <String, int>{};
    for (var i = 0; i < seedCategories.length; i++) {
      final name = seedCategories[i];
      final existing = await db.query('categories', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
      final int id;
      if (existing.isNotEmpty) {
        id = existing.first['id'] as int;
        await db.update('categories', {'sort_order': i}, where: 'id = ?', whereArgs: [id]);
      } else {
        id = await db.insert('categories', {'name': name, 'sort_order': i});
      }
      categoryIds[name] = id;
    }

    final now = DateTime.now().toIso8601String();
    for (final product in seedProducts) {
      final categoryId = categoryIds[product.category]!;
      final existing = await db.rawQuery('''
        SELECT p.id, p.stock_initialized
        FROM products p
        WHERE p.name = ? COLLATE NOCASE
        LIMIT 1
      ''', [product.name]);

      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        final initialized = (existing.first['stock_initialized'] as int? ?? 1) == 1;
        final values = <String, Object?>{
          'category_id': categoryId,
          'stock_unit': product.unit,
        };
        if (!initialized) values['bottle_ml'] = product.packageSize;
        await db.update('products', values, where: 'id = ?', whereArgs: [id]);
        continue;
      }

      await db.insert('products', {
        'name': product.name,
        'category_id': categoryId,
        'bottle_ml': product.packageSize,
        'whole_bottles': 0,
        'extra_ml': 0,
        'minimum_ml': 0,
        'target_amount': 0,
        'variance_recheck_amount': 0,
        'stock_unit': product.unit,
        'stock_initialized': 0,
        'active': 1,
        'created_at': now,
      });
    }
  }
}
