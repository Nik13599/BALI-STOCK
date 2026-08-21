import 'package:sqflite_common/sqlite_api.dart';

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

  Future<void> updateProductControlCache({
    required int productId,
    required int minimumAmount,
    required int targetAmount,
    required int varianceRecheckAmount,
    String? barcode,
  }) async {
    if (minimumAmount < 0 || targetAmount < 0 || varianceRecheckAmount < 0) {
      throw ArgumentError('Минимум, цель и порог перепроверки не могут быть отрицательными');
    }
    final db = await _database.database;
    final updated = await db.update(
      'products',
      {
        'minimum_ml': minimumAmount,
        'target_amount': targetAmount,
        'variance_recheck_amount': varianceRecheckAmount,
        'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
    if (updated != 1) throw StateError('Товар для изменения не найден');
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

  Future<String?> getLastStocktakeEmployee() async {
    final db = await _database.database;
    final rows = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: ['last_stocktake_employee'], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setLastStocktakeEmployee(DatabaseExecutor db, String employeeName) async {
    await db.insert(
      'app_settings',
      {'key': 'last_stocktake_employee', 'value': employeeName},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<StocktakeDraft>> getActiveStocktakeDrafts() async {
    final db = await _database.database;
    final rows = await db.query('stocktake_drafts', orderBy: 'started_at DESC');
    final result = <StocktakeDraft>[];
    for (final row in rows) {
      result.add(await _readDraft(db, row['id'] as int));
    }
    return result;
  }

  Future<StocktakeDraft?> getActiveStocktakeDraft(String employeeName) async {
    final clean = employeeName.trim();
    if (clean.isEmpty) return null;
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT id FROM stocktake_drafts
      WHERE employee_name = ? COLLATE NOCASE
      ORDER BY started_at DESC
      LIMIT 1
    ''', [clean]);
    if (rows.isEmpty) return null;
    return _readDraft(db, rows.first['id'] as int);
  }

  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    final clean = employeeName.trim();
    if (clean.isEmpty) throw ArgumentError('Укажите ФИО сотрудника');
    final db = await _database.database;
    late int draftId;

    await db.transaction((txn) async {
      final existing = await txn.rawQuery('''
        SELECT id FROM stocktake_drafts
        WHERE employee_name = ? COLLATE NOCASE
        LIMIT 1
      ''', [clean]);
      if (existing.isNotEmpty) {
        draftId = existing.first['id'] as int;
        await _setLastStocktakeEmployee(txn, clean);
        return;
      }

      final products = await txn.rawQuery('''
        SELECT p.*, c.name AS category_name, c.sort_order AS category_sort
        FROM products p
        JOIN categories c ON c.id = p.category_id
        WHERE p.active = 1
        ORDER BY c.sort_order, c.name COLLATE NOCASE, p.name COLLATE NOCASE
      ''');
      if (products.isEmpty) throw StateError('На складе нет активных позиций');

      final now = DateTime.now().toIso8601String();
      draftId = await txn.insert('stocktake_drafts', {
        'employee_name': clean,
        'status': 'in_progress',
        'started_at': now,
        'updated_at': now,
        'active_seconds': 0,
        'total_count': products.length,
      });

      for (var i = 0; i < products.length; i++) {
        final product = _productFromMap(products[i]);
        await txn.insert('stocktake_draft_lines', {
          'draft_id': draftId,
          'product_id': product.id,
          'product_name': product.name,
          'category_name': product.categoryName,
          'package_size': product.packageSize,
          'stock_unit': product.stockUnit.dbValue,
          'before_total': product.stockInitialized ? product.totalAmount : 0,
          'before_initialized': product.stockInitialized ? 1 : 0,
          'sort_order': i,
        });
      }
      await _setLastStocktakeEmployee(txn, clean);
    });

    return _readDraft(db, draftId);
  }

  Future<StocktakeDraft> resumeStocktakeDraft(int draftId) async {
    final db = await _database.database;
    await db.update(
      'stocktake_drafts',
      {'status': 'in_progress', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [draftId],
    );
    return _readDraft(db, draftId);
  }

  Future<void> pauseStocktakeDraft(int draftId, int activeSeconds) async {
    final db = await _database.database;
    await db.update(
      'stocktake_drafts',
      {
        'status': 'draft',
        'active_seconds': activeSeconds < 0 ? 0 : activeSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [draftId],
    );
  }

  Future<void> saveStocktakeActiveSeconds(int draftId, int activeSeconds) async {
    final db = await _database.database;
    await db.update(
      'stocktake_drafts',
      {
        'active_seconds': activeSeconds < 0 ? 0 : activeSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [draftId],
    );
  }

  Future<void> saveStocktakeDraftLine({
    required int draftId,
    required int productId,
    required int? wholePackages,
    required int? extraAmount,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'stocktake_draft_lines',
      columns: ['package_size', 'stock_unit'],
      where: 'draft_id = ? AND product_id = ?',
      whereArgs: [draftId, productId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Позиция не входит в этот переучёт');

    final packageSize = rows.first['package_size'] as int;
    final unit = StockUnitX.fromDb(rows.first['stock_unit'] as String?);
    if (wholePackages != null && wholePackages < 0) throw ArgumentError('Количество не может быть отрицательным');
    if (unit != StockUnit.piece && extraAmount != null && (extraAmount < 0 || extraAmount >= packageSize)) {
      throw ArgumentError('Некорректный дополнительный остаток');
    }

    await db.transaction((txn) async {
      await txn.update(
        'stocktake_draft_lines',
        {
          'whole_packages': wholePackages,
          'extra_amount': unit == StockUnit.piece ? null : extraAmount,
        },
        where: 'draft_id = ? AND product_id = ?',
        whereArgs: [draftId, productId],
      );
      await txn.update(
        'stocktake_drafts',
        {
          'last_product_id': productId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [draftId],
      );
    });
  }

  Future<void> deleteStocktakeDraft(int draftId) async {
    final db = await _database.database;
    await db.delete('stocktake_drafts', where: 'id = ?', whereArgs: [draftId]);
  }

  Future<int> completeStocktakeDraft(int draftId, int activeSeconds) async {
    final db = await _database.database;
    late int operationId;

    await db.transaction((txn) async {
      final draftRows = await txn.query('stocktake_drafts', where: 'id = ?', whereArgs: [draftId], limit: 1);
      if (draftRows.isEmpty) throw StateError('Черновик переучёта не найден');
      final draftRow = draftRows.first;
      final lineRows = await txn.query('stocktake_draft_lines', where: 'draft_id = ?', whereArgs: [draftId], orderBy: 'sort_order');
      final lines = lineRows.map(_savedLineFromMap).toList(growable: false);
      if (lines.isEmpty || lines.length != (draftRow['total_count'] as int) || lines.any((line) => !line.isFilled)) {
        throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
      }

      final employee = draftRow['employee_name'] as String;
      final startedAt = DateTime.parse(draftRow['started_at'] as String);
      final completedAt = DateTime.now();
      final safeActiveSeconds = activeSeconds < 0 ? 0 : activeSeconds;
      final totalSeconds = completedAt.difference(startedAt).inSeconds.clamp(0, 1 << 31).toInt();

      operationId = await txn.insert('operations', {
        'type': 'stocktake',
        'created_at': completedAt.toIso8601String(),
        'employee_name': employee,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'active_seconds': safeActiveSeconds,
        'total_seconds': totalSeconds,
      });

      for (final line in lines) {
        final currentRows = await txn.rawQuery('''
          SELECT p.*, c.name AS category_name
          FROM products p
          JOIN categories c ON c.id = p.category_id
          WHERE p.id = ?
          LIMIT 1
        ''', [line.productId]);
        if (currentRows.isEmpty) throw StateError('Позиция ${line.productName} больше не существует');
        final current = _productFromMap(currentRows.first);

        final whole = line.wholePackages!;
        final extra = line.stockUnit == StockUnit.piece ? 0 : line.extraAmount!;
        _validateQuantity(whole, extra, line.packageSize, line.stockUnit, line.productName);
        final actual = line.stockUnit == StockUnit.piece ? whole : whole * line.packageSize + extra;
        final beforeInitialized = current.stockInitialized;
        final before = beforeInitialized ? current.totalAmount : 0;
        final difference = beforeInitialized ? actual - before : 0;

        await txn.update(
          'products',
          {
            'bottle_ml': line.stockUnit == StockUnit.piece ? 1 : line.packageSize,
            'whole_bottles': line.stockUnit == StockUnit.piece ? actual : whole,
            'extra_ml': line.stockUnit == StockUnit.piece ? 0 : extra,
            'stock_unit': line.stockUnit.dbValue,
            'stock_initialized': 1,
          },
          where: 'id = ?',
          whereArgs: [line.productId],
        );
        await txn.insert('operation_lines', {
          'operation_id': operationId,
          'product_id': line.productId,
          'product_name': line.productName,
          'category_name': line.categoryName,
          'bottle_ml': line.stockUnit == StockUnit.piece ? 1 : line.packageSize,
          'stock_unit': line.stockUnit.dbValue,
          'before_total_ml': before,
          'before_initialized': beforeInitialized ? 1 : 0,
          'change_total_ml': difference,
          'after_total_ml': actual,
        });
      }

      await txn.delete('stocktake_drafts', where: 'id = ?', whereArgs: [draftId]);
    });

    return operationId;
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
        employeeName: operation['employee_name'] as String?,
        startedAt: operation['started_at'] == null ? null : DateTime.parse(operation['started_at'] as String),
        completedAt: operation['completed_at'] == null ? null : DateTime.parse(operation['completed_at'] as String),
        activeSeconds: (operation['active_seconds'] as int?) ?? 0,
        totalSeconds: (operation['total_seconds'] as int?) ?? 0,
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

  Future<StocktakeDraft> _readDraft(DatabaseExecutor db, int draftId) async {
    final rows = await db.query('stocktake_drafts', where: 'id = ?', whereArgs: [draftId], limit: 1);
    if (rows.isEmpty) throw StateError('Черновик переучёта не найден');
    final row = rows.first;
    final lineRows = await db.query('stocktake_draft_lines', where: 'draft_id = ?', whereArgs: [draftId], orderBy: 'sort_order');
    final lines = lineRows.map(_savedLineFromMap).toList(growable: false);
    return StocktakeDraft(
      id: draftId,
      employeeName: row['employee_name'] as String,
      status: StocktakeDraftStatusX.fromDb(row['status'] as String?),
      startedAt: DateTime.parse(row['started_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      activeSeconds: row['active_seconds'] as int,
      lastProductId: row['last_product_id'] as int?,
      totalCount: row['total_count'] as int,
      filledCount: lines.where((line) => line.isFilled).length,
      lines: lines,
    );
  }

  SavedStocktakeLine _savedLineFromMap(Map<String, Object?> row) => SavedStocktakeLine(
        productId: row['product_id'] as int,
        productName: row['product_name'] as String,
        categoryName: row['category_name'] as String,
        packageSize: row['package_size'] as int,
        stockUnit: StockUnitX.fromDb(row['stock_unit'] as String?),
        beforeTotal: row['before_total'] as int,
        beforeInitialized: (row['before_initialized'] as int? ?? 1) == 1,
        sortOrder: row['sort_order'] as int,
        wholePackages: row['whole_packages'] as int?,
        extraAmount: row['extra_amount'] as int?,
      );

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
