import '../models.dart';
import 'database.dart';

class WarehouseRepository {
  WarehouseRepository({BaliStockDatabase? database})
      : _database = database ?? BaliStockDatabase.instance;

  final BaliStockDatabase _database;

  Future<List<Category>> getCategories() async {
    final db = await _database.database;
    final rows = await db.query('categories', orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList(growable: false);
  }

  Future<int> addCategory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Название категории обязательно');
    final db = await _database.database;
    final maxRows = await db.rawQuery('SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM categories');
    final sortOrder = (maxRows.first['next_order'] as int?) ?? 0;
    return db.insert('categories', {'name': clean, 'sort_order': sortOrder});
  }

  Future<List<Product>> getProducts() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM products p
      JOIN categories c ON c.id = p.category_id
      WHERE p.active = 1
      ORDER BY c.sort_order, c.name COLLATE NOCASE, p.name COLLATE NOCASE
    ''');
    return rows.map(_productFromMap).toList(growable: false);
  }

  Future<void> addProduct({
    required String name,
    required int categoryId,
    required int packageSize,
    required int wholePackages,
    required int extraAmount,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    final clean = name.trim();
    _validateProductFields(clean, packageSize, minimumAmount, stockUnit);
    _validateQuantity(wholePackages, extraAmount, packageSize, stockUnit, clean);

    final db = await _database.database;
    await db.insert('products', {
      'name': clean,
      'category_id': categoryId,
      'bottle_ml': stockUnit == StockUnit.piece ? 1 : packageSize,
      'whole_bottles': wholePackages,
      'extra_ml': stockUnit == StockUnit.piece ? 0 : extraAmount,
      'minimum_ml': minimumAmount,
      'stock_unit': stockUnit.dbValue,
      'stock_initialized': 1,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required int categoryId,
    required int packageSize,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    final clean = name.trim();
    _validateProductFields(clean, packageSize, minimumAmount, stockUnit);

    final db = await _database.database;
    final rows = await db.query('products', where: 'id = ? AND active = 1', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) throw StateError('Позиция больше не активна');

    final oldSize = rows.first['bottle_ml'] as int;
    final oldUnit = StockUnitX.fromDb(rows.first['stock_unit'] as String?);
    final initialized = (rows.first['stock_initialized'] as int? ?? 1) == 1;
    final whole = rows.first['whole_bottles'] as int;
    final extra = rows.first['extra_ml'] as int;
    final newSize = stockUnit == StockUnit.piece ? 1 : packageSize;
    if (initialized && (oldSize != newSize || oldUnit != stockUnit) && (whole > 0 || extra > 0)) {
      throw StateError('Нельзя менять тип учёта или размер тары/упаковки у позиции с остатком. Сначала проведите переучёт с нулевым остатком.');
    }

    await db.update(
      'products',
      {
        'name': clean,
        'category_id': categoryId,
        'bottle_ml': newSize,
        'minimum_ml': minimumAmount,
        'stock_unit': stockUnit.dbValue,
        if (stockUnit == StockUnit.piece) 'extra_ml': 0,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> receiveDelivery(List<DeliveryDraftLine> lines) async {
    if (lines.isEmpty) throw ArgumentError('Добавьте хотя бы одну позицию поставки');
    final db = await _database.database;

    await db.transaction((txn) async {
      final operationId = await txn.insert('operations', {
        'type': 'delivery',
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final line in lines) {
        final rows = await txn.rawQuery('''
          SELECT p.*, c.name AS category_name
          FROM products p
          JOIN categories c ON c.id = p.category_id
          WHERE p.id = ? AND p.active = 1
        ''', [line.product.id]);
        if (rows.isEmpty) throw StateError('Позиция ${line.product.name} больше не активна');
        final current = _productFromMap(rows.first);
        if (!current.stockInitialized) {
          throw StateError('Сначала проведите первичный переучёт. Остаток ${current.name} ещё не введён.');
        }
        _validateQuantity(line.bottles, line.extraMl, current.packageSize, current.stockUnit, current.name);

        final before = current.totalAmount;
        final added = line.bottles * current.packageSize + line.extraMl;
        final after = before + added;
        final normalizedPackages = current.stockUnit == StockUnit.piece ? after : after ~/ current.packageSize;
        final normalizedExtra = current.stockUnit == StockUnit.piece ? 0 : after % current.packageSize;

        await txn.update(
          'products',
          {'whole_bottles': normalizedPackages, 'extra_ml': normalizedExtra},
          where: 'id = ?',
          whereArgs: [current.id],
        );
        await txn.insert('operation_lines', {
          'operation_id': operationId,
          'product_id': current.id,
          'product_name': current.name,
          'category_name': current.categoryName,
          'bottle_ml': current.packageSize,
          'stock_unit': current.stockUnit.dbValue,
          'before_total_ml': before,
          'before_initialized': 1,
          'change_total_ml': added,
          'after_total_ml': after,
        });
      }
    });
  }

  Future<void> conductStocktake(Map<int, StocktakeDraftLine> values) async {
    final db = await _database.database;

    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT p.*, c.name AS category_name
        FROM products p
        JOIN categories c ON c.id = p.category_id
        WHERE p.active = 1
        ORDER BY c.sort_order, p.name COLLATE NOCASE
      ''');
      final products = rows.map(_productFromMap).toList(growable: false);
      if (products.isEmpty) throw StateError('На складе нет активных позиций');
      if (values.length != products.length || products.any((p) => !values.containsKey(p.id))) {
        throw StateError('Переучёт нельзя провести: заполнены не все позиции');
      }

      for (final product in products) {
        final value = values[product.id]!;
        _validateQuantity(value.bottles, value.extraMl, product.packageSize, product.stockUnit, product.name);
      }

      final operationId = await txn.insert('operations', {
        'type': 'stocktake',
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final product in products) {
        final value = values[product.id]!;
        final beforeInitialized = product.stockInitialized;
        final before = beforeInitialized ? product.totalAmount : 0;
        final after = value.bottles * product.packageSize + value.extraMl;
        final difference = beforeInitialized ? after - before : 0;

        await txn.update(
          'products',
          {
            'whole_bottles': product.stockUnit == StockUnit.piece ? after : value.bottles,
            'extra_ml': product.stockUnit == StockUnit.piece ? 0 : value.extraMl,
            'stock_initialized': 1,
          },
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await txn.insert('operation_lines', {
          'operation_id': operationId,
          'product_id': product.id,
          'product_name': product.name,
          'category_name': product.categoryName,
          'bottle_ml': product.packageSize,
          'stock_unit': product.stockUnit.dbValue,
          'before_total_ml': before,
          'before_initialized': beforeInitialized ? 1 : 0,
          'change_total_ml': difference,
          'after_total_ml': after,
        });
      }
    });
  }

  Future<List<StockOperation>> getOperations() async {
    final db = await _database.database;
    final operations = await db.query('operations', orderBy: 'created_at DESC, id DESC');
    final result = <StockOperation>[];

    for (final operation in operations) {
      final id = operation['id'] as int;
      final lineRows = await db.query(
        'operation_lines',
        where: 'operation_id = ?',
        whereArgs: [id],
        orderBy: 'category_name COLLATE NOCASE, product_name COLLATE NOCASE',
      );
      result.add(StockOperation(
        id: id,
        type: operation['type'] == 'delivery' ? StockOperationType.delivery : StockOperationType.stocktake,
        createdAt: DateTime.parse(operation['created_at'] as String),
        lines: lineRows
            .map((row) => StockOperationLine(
                  productId: row['product_id'] as int,
                  productName: row['product_name'] as String,
                  categoryName: row['category_name'] as String,
                  bottleMl: row['bottle_ml'] as int,
                  stockUnit: StockUnitX.fromDb(row['stock_unit'] as String?),
                  beforeTotalMl: row['before_total_ml'] as int,
                  beforeInitialized: (row['before_initialized'] as int? ?? 1) == 1,
                  changeTotalMl: row['change_total_ml'] as int,
                  afterTotalMl: row['after_total_ml'] as int,
                ))
            .toList(growable: false),
      ));
    }
    return result;
  }

  void _validateProductFields(String name, int packageSize, int minimumAmount, StockUnit unit) {
    if (name.isEmpty) throw ArgumentError('Название позиции обязательно');
    if (unit != StockUnit.piece && packageSize <= 0) {
      throw ArgumentError(unit == StockUnit.ml ? 'Объём бутылки должен быть больше нуля' : 'Вес упаковки должен быть больше нуля');
    }
    if (minimumAmount < 0) throw ArgumentError('Минимальный остаток не может быть отрицательным');
  }

  void _validateQuantity(int packages, int extra, int packageSize, StockUnit unit, String name) {
    if (packages < 0 || extra < 0) throw ArgumentError('Количество не может быть отрицательным: $name');
    if (unit == StockUnit.piece) {
      if (extra != 0) throw ArgumentError('Для штучного товара дополнительный остаток не используется: $name');
      return;
    }
    if (extra >= packageSize) {
      final unitName = unit == StockUnit.ml ? 'объёма одной бутылки' : 'веса одной упаковки';
      throw ArgumentError('Дополнительный остаток должен быть меньше $unitName: $name');
    }
  }

  Product _productFromMap(Map<String, Object?> row) => Product(
        id: row['id'] as int,
        name: row['name'] as String,
        categoryId: row['category_id'] as int,
        categoryName: row['category_name'] as String,
        bottleMl: row['bottle_ml'] as int,
        wholeBottles: row['whole_bottles'] as int,
        extraMl: row['extra_ml'] as int,
        minimumMl: row['minimum_ml'] as int,
        stockUnit: StockUnitX.fromDb(row['stock_unit'] as String?),
        stockInitialized: (row['stock_initialized'] as int? ?? 1) == 1,
        active: (row['active'] as int) == 1,
      );
}
