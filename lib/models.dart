enum StockOperationType { delivery, stocktake, writeoff, transfer, correction }

enum StockUnit { ml, gram, piece }

enum StocktakeDraftStatus { draft, inProgress }

extension StockOperationTypeX on StockOperationType {
  String get dbValue => switch (this) {
        StockOperationType.delivery => 'delivery',
        StockOperationType.stocktake => 'stocktake',
        StockOperationType.writeoff => 'writeoff',
        StockOperationType.transfer => 'transfer',
        StockOperationType.correction => 'correction',
      };

  String get displayName => switch (this) {
        StockOperationType.delivery => 'Поставка',
        StockOperationType.stocktake => 'Переучёт',
        StockOperationType.writeoff => 'Списание',
        StockOperationType.transfer => 'Перемещение',
        StockOperationType.correction => 'Корректировка',
      };

  static StockOperationType fromDb(String? value) => switch (value) {
        'delivery' => StockOperationType.delivery,
        'writeoff' => StockOperationType.writeoff,
        'transfer' => StockOperationType.transfer,
        'correction' => StockOperationType.correction,
        _ => StockOperationType.stocktake,
      };
}

extension StocktakeDraftStatusX on StocktakeDraftStatus {
  String get dbValue => this == StocktakeDraftStatus.inProgress ? 'in_progress' : 'draft';
  String get displayName => this == StocktakeDraftStatus.inProgress ? 'В процессе' : 'Черновик';

  static StocktakeDraftStatus fromDb(String? value) =>
      value == 'in_progress' ? StocktakeDraftStatus.inProgress : StocktakeDraftStatus.draft;
}

extension StockUnitX on StockUnit {
  String get dbValue => switch (this) {
        StockUnit.ml => 'ml',
        StockUnit.gram => 'g',
        StockUnit.piece => 'pcs',
      };

  String get symbol => switch (this) {
        StockUnit.ml => 'мл',
        StockUnit.gram => 'г',
        StockUnit.piece => 'шт.',
      };

  String get packageLabel => switch (this) {
        StockUnit.ml => 'бут.',
        StockUnit.gram => 'уп.',
        StockUnit.piece => 'шт.',
      };

  String get displayName => switch (this) {
        StockUnit.ml => 'Миллилитры / бутылки',
        StockUnit.gram => 'Граммы / упаковки',
        StockUnit.piece => 'Штуки',
      };

  static StockUnit fromDb(String? value) => switch (value) {
        'g' => StockUnit.gram,
        'pcs' => StockUnit.piece,
        _ => StockUnit.ml,
      };
}

class Category {
  const Category({required this.id, required this.name, required this.sortOrder});

  final int id;
  final String name;
  final int sortOrder;

  factory Category.fromMap(Map<String, Object?> map) => Category(
        id: map['id'] as int,
        name: map['name'] as String,
        sortOrder: map['sort_order'] as int,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.bottleMl,
    required this.wholeBottles,
    required this.extraMl,
    required this.minimumMl,
    required this.stockUnit,
    required this.stockInitialized,
    required this.active,
    this.targetAmount = 0,
    this.barcode,
    this.defaultCost,
    this.costCurrency = 'BYN',
    this.varianceRecheckAmount = 0,
  });

  final int id;
  final String name;
  final int categoryId;
  final String categoryName;

  /// Legacy SQLite column names are retained for backwards-compatible migrations.
  /// For non-liquid goods these values mean package size / whole packages /
  /// loose remainder / minimum amount in the product's [stockUnit].
  final int bottleMl;
  final int wholeBottles;
  final int extraMl;
  final int minimumMl;
  final StockUnit stockUnit;
  final bool stockInitialized;
  final bool active;

  /// Business-control metadata from the shared database.
  final int targetAmount;
  final String? barcode;
  final double? defaultCost;
  final String costCurrency;
  final int varianceRecheckAmount;

  int get packageSize => bottleMl;
  int get wholePackages => wholeBottles;
  int get extraAmount => extraMl;
  int get minimumAmount => minimumMl;
  int get totalAmount => wholeBottles * bottleMl + extraMl;
  int get totalMl => totalAmount;
  bool get supportsRemainder => stockUnit != StockUnit.piece;
  bool get isEmpty => stockInitialized && totalAmount == 0;
  bool get isLow => stockInitialized && totalAmount <= minimumAmount;
  int get desiredAmount => targetAmount > 0 ? targetAmount : minimumAmount;
  int get suggestedPurchaseAmount => stockInitialized ? (desiredAmount - totalAmount).clamp(0, 1 << 60) : 0;

  Product copyWith({
    int? wholeBottles,
    int? extraMl,
    bool? stockInitialized,
    int? targetAmount,
    String? barcode,
    bool clearBarcode = false,
    double? defaultCost,
    String? costCurrency,
    int? varianceRecheckAmount,
  }) =>
      Product(
        id: id,
        name: name,
        categoryId: categoryId,
        categoryName: categoryName,
        bottleMl: bottleMl,
        wholeBottles: wholeBottles ?? this.wholeBottles,
        extraMl: extraMl ?? this.extraMl,
        minimumMl: minimumMl,
        stockUnit: stockUnit,
        stockInitialized: stockInitialized ?? this.stockInitialized,
        active: active,
        targetAmount: targetAmount ?? this.targetAmount,
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        defaultCost: defaultCost ?? this.defaultCost,
        costCurrency: costCurrency ?? this.costCurrency,
        varianceRecheckAmount: varianceRecheckAmount ?? this.varianceRecheckAmount,
      );
}

class StockOperation {
  const StockOperation({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.lines,
    this.employeeName,
    this.startedAt,
    this.completedAt,
    this.activeSeconds = 0,
    this.totalSeconds = 0,
    this.supplierId,
    this.supplierName,
    this.documentNumber,
    this.comment,
    this.attachmentUrl,
    this.sourceLocationId,
    this.sourceLocationName,
    this.targetLocationId,
    this.targetLocationName,
    this.correctionOf,
    this.totalValue,
  });

  final int id;
  final StockOperationType type;
  final DateTime createdAt;
  final List<StockOperationLine> lines;
  final String? employeeName;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int activeSeconds;
  final int totalSeconds;
  final String? supplierId;
  final String? supplierName;
  final String? documentNumber;
  final String? comment;
  final String? attachmentUrl;
  final String? sourceLocationId;
  final String? sourceLocationName;
  final String? targetLocationId;
  final String? targetLocationName;
  final String? correctionOf;
  final double? totalValue;
}

class StockOperationLine {
  const StockOperationLine({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.bottleMl,
    required this.stockUnit,
    required this.beforeTotalMl,
    required this.beforeInitialized,
    required this.changeTotalMl,
    required this.afterTotalMl,
    this.unitCost,
    this.lineValue,
    this.comment,
    this.sourceLocationId,
    this.targetLocationId,
  });

  final int productId;
  final String productName;
  final String categoryName;
  final int bottleMl;
  final StockUnit stockUnit;
  final int beforeTotalMl;
  final bool beforeInitialized;
  final int changeTotalMl;
  final int afterTotalMl;
  final double? unitCost;
  final double? lineValue;
  final String? comment;
  final String? sourceLocationId;
  final String? targetLocationId;
}

class DeliveryDraftLine {
  const DeliveryDraftLine({
    required this.product,
    required this.bottles,
    required this.extraMl,
    this.unitCost,
    this.sourceText,
    this.confidence,
    this.manuallyCorrected = false,
  });

  final Product product;
  final int bottles;
  final int extraMl;
  final double? unitCost;
  final String? sourceText;
  final double? confidence;
  final bool manuallyCorrected;

  int get addedMl => bottles * product.packageSize + extraMl;

  DeliveryDraftLine copyWith({
    Product? product,
    int? bottles,
    int? extraMl,
    double? unitCost,
    bool clearUnitCost = false,
    String? sourceText,
    double? confidence,
    bool? manuallyCorrected,
  }) =>
      DeliveryDraftLine(
        product: product ?? this.product,
        bottles: bottles ?? this.bottles,
        extraMl: extraMl ?? this.extraMl,
        unitCost: clearUnitCost ? null : (unitCost ?? this.unitCost),
        sourceText: sourceText ?? this.sourceText,
        confidence: confidence ?? this.confidence,
        manuallyCorrected: manuallyCorrected ?? this.manuallyCorrected,
      );
}

class StocktakeDraftLine {
  const StocktakeDraftLine({required this.bottles, required this.extraMl});

  final int bottles;
  final int extraMl;
}

class SavedStocktakeLine {
  const SavedStocktakeLine({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.packageSize,
    required this.stockUnit,
    required this.beforeTotal,
    required this.beforeInitialized,
    required this.sortOrder,
    this.wholePackages,
    this.extraAmount,
  });

  final int productId;
  final String productName;
  final String categoryName;
  final int packageSize;
  final StockUnit stockUnit;
  final int beforeTotal;
  final bool beforeInitialized;
  final int sortOrder;
  final int? wholePackages;
  final int? extraAmount;

  bool get isFilled {
    if (wholePackages == null || wholePackages! < 0) return false;
    if (stockUnit == StockUnit.piece) return true;
    return extraAmount != null && extraAmount! >= 0 && extraAmount! < packageSize;
  }

  int? get actualTotal {
    if (!isFilled) return null;
    if (stockUnit == StockUnit.piece) return wholePackages!;
    return wholePackages! * packageSize + extraAmount!;
  }
}

class StocktakeDraft {
  const StocktakeDraft({
    required this.id,
    required this.employeeName,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    required this.activeSeconds,
    required this.totalCount,
    required this.filledCount,
    required this.lines,
    this.lastProductId,
  });

  final int id;
  final String employeeName;
  final StocktakeDraftStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int activeSeconds;
  final int totalCount;
  final int filledCount;
  final int? lastProductId;
  final List<SavedStocktakeLine> lines;

  bool get isComplete => totalCount > 0 && filledCount == totalCount;
}

class StockSupplier {
  const StockSupplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.notes,
    this.active = true,
  });

  final String id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? notes;
  final bool active;

  factory StockSupplier.fromJson(Map<dynamic, dynamic> json) => StockSupplier(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        contactPerson: _nullableText(json['contact_person']),
        phone: _nullableText(json['phone']),
        email: _nullableText(json['email']),
        notes: _nullableText(json['notes']),
        active: json['active'] != false,
      );
}

class ProductSupplierLink {
  const ProductSupplierLink({
    required this.productKey,
    required this.supplierId,
    this.supplierSku,
    this.lastPrice,
    this.currency = 'BYN',
    this.isPrimary = false,
    this.active = true,
  });

  final String productKey;
  final String supplierId;
  final String? supplierSku;
  final double? lastPrice;
  final String currency;
  final bool isPrimary;
  final bool active;

  factory ProductSupplierLink.fromJson(Map<dynamic, dynamic> json) => ProductSupplierLink(
        productKey: '${json['product_key'] ?? ''}',
        supplierId: '${json['supplier_id'] ?? ''}',
        supplierSku: _nullableText(json['supplier_sku']),
        lastPrice: _asDouble(json['last_price']),
        currency: '${json['currency'] ?? 'BYN'}',
        isPrimary: json['is_primary'] == true,
        active: json['active'] != false,
      );
}

class StockLocation {
  const StockLocation({
    required this.id,
    required this.name,
    this.isPrimary = false,
    this.active = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final bool isPrimary;
  final bool active;
  final int sortOrder;

  factory StockLocation.fromJson(Map<dynamic, dynamic> json) => StockLocation(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        isPrimary: json['is_primary'] == true,
        active: json['active'] != false,
        sortOrder: _asIntValue(json['sort_order']),
      );
}

class StockLocationBalance {
  const StockLocationBalance({
    required this.locationId,
    required this.productKey,
    required this.quantityBase,
    required this.initialized,
  });

  final String locationId;
  final String productKey;
  final int quantityBase;
  final bool initialized;

  factory StockLocationBalance.fromJson(Map<dynamic, dynamic> json) => StockLocationBalance(
        locationId: '${json['location_id'] ?? ''}',
        productKey: '${json['product_key'] ?? ''}',
        quantityBase: _asIntValue(json['quantity_base']),
        initialized: json['initialized'] == true,
      );
}

class PurchaseSuggestion {
  const PurchaseSuggestion({
    required this.productKey,
    required this.name,
    required this.categoryName,
    required this.stockUnit,
    required this.packageSize,
    required this.currentQuantity,
    required this.minimumAmount,
    required this.targetAmount,
    required this.suggestedQuantity,
    this.preferredSupplier,
    this.lastPrice,
    this.currency = 'BYN',
  });

  final String productKey;
  final String name;
  final String categoryName;
  final StockUnit stockUnit;
  final int packageSize;
  final int currentQuantity;
  final int minimumAmount;
  final int targetAmount;
  final int suggestedQuantity;
  final String? preferredSupplier;
  final double? lastPrice;
  final String currency;

  factory PurchaseSuggestion.fromJson(Map<dynamic, dynamic> json) => PurchaseSuggestion(
        productKey: '${json['product_key'] ?? ''}',
        name: '${json['name'] ?? ''}',
        categoryName: '${json['category_name'] ?? ''}',
        stockUnit: StockUnitX.fromDb(json['stock_unit'] as String?),
        packageSize: _asIntValue(json['package_size'], fallback: 1),
        currentQuantity: _asIntValue(json['current_quantity']),
        minimumAmount: _asIntValue(json['minimum_amount']),
        targetAmount: _asIntValue(json['target_amount']),
        suggestedQuantity: _asIntValue(json['suggested_quantity']),
        preferredSupplier: _nullableText(json['preferred_supplier']),
        lastPrice: _asDouble(json['last_price']),
        currency: '${json['currency'] ?? 'BYN'}',
      );
}

class StockAnalytics {
  const StockAnalytics({
    this.periodDays = 30,
    this.operations = 0,
    this.deliveries = 0,
    this.stocktakes = 0,
    this.writeoffs = 0,
    this.transfers = 0,
    this.averageStocktakeSeconds = 0,
    this.fastestStocktakeSeconds = 0,
    this.longestStocktakeSeconds = 0,
    this.largestVariances = const [],
  });

  final int periodDays;
  final int operations;
  final int deliveries;
  final int stocktakes;
  final int writeoffs;
  final int transfers;
  final int averageStocktakeSeconds;
  final int fastestStocktakeSeconds;
  final int longestStocktakeSeconds;
  final List<Map<String, dynamic>> largestVariances;

  factory StockAnalytics.fromJson(Map<dynamic, dynamic>? json) {
    final map = json ?? const {};
    final raw = map['largest_variances'];
    return StockAnalytics(
      periodDays: _asIntValue(map['period_days'], fallback: 30),
      operations: _asIntValue(map['operations']),
      deliveries: _asIntValue(map['deliveries']),
      stocktakes: _asIntValue(map['stocktakes']),
      writeoffs: _asIntValue(map['writeoffs']),
      transfers: _asIntValue(map['transfers']),
      averageStocktakeSeconds: _asIntValue(map['average_stocktake_seconds']),
      fastestStocktakeSeconds: _asIntValue(map['fastest_stocktake_seconds']),
      longestStocktakeSeconds: _asIntValue(map['longest_stocktake_seconds']),
      largestVariances: raw is List
          ? raw.whereType<Map>().map((e) => e.map((key, value) => MapEntry('$key', value))).toList(growable: false)
          : const [],
    );
  }
}

class InvoiceRecognitionLine {
  const InvoiceRecognitionLine({
    required this.sourceText,
    required this.product,
    required this.quantityBase,
    required this.packages,
    required this.extraAmount,
    required this.confidence,
    this.unitCost,
  });

  final String sourceText;
  final Product product;
  final int quantityBase;
  final int packages;
  final int extraAmount;
  final double confidence;
  final double? unitCost;

  DeliveryDraftLine toDeliveryLine() => DeliveryDraftLine(
        product: product,
        bottles: packages,
        extraMl: extraAmount,
        unitCost: unitCost,
        sourceText: sourceText,
        confidence: confidence,
      );
}

String formatBottleVolume(int ml) {
  if (ml % 1000 == 0) return '${ml ~/ 1000} л';
  final value = (ml / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${value.replaceAll('.', ',')} л';
}

String formatPackageSize(int amount, StockUnit unit) {
  switch (unit) {
    case StockUnit.ml:
      return formatBottleVolume(amount);
    case StockUnit.gram:
      if (amount % 1000 == 0) return '${amount ~/ 1000} кг';
      return '$amount г';
    case StockUnit.piece:
      return '$amount шт.';
  }
}

String formatStockParts(int total, int packageSize, [StockUnit unit = StockUnit.ml]) {
  if (unit == StockUnit.piece) return '$total шт.';
  if (packageSize <= 0) return '$total ${unit.symbol}';
  final packages = total ~/ packageSize;
  final extra = total % packageSize;
  return '$packages ${unit.packageLabel} × ${formatPackageSize(packageSize, unit)} + $extra ${unit.symbol}';
}

String formatLiters(int ml) {
  final liters = ml / 1000;
  final value = liters.toStringAsFixed(liters < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${value.replaceAll('.', ',')} л';
}

String formatTotalAmount(int amount, StockUnit unit) {
  switch (unit) {
    case StockUnit.ml:
      return formatLiters(amount);
    case StockUnit.gram:
      if (amount < 1000) return '$amount г';
      final kg = amount / 1000;
      final value = kg.toStringAsFixed(kg < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      return '${value.replaceAll('.', ',')} кг';
    case StockUnit.piece:
      return '$amount шт.';
  }
}

String formatMinimumAmount(int amount, StockUnit unit) => '$amount ${unit.symbol}';

String formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
}

String formatDurationSeconds(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  if (hours > 0) return '$hours ч ${minutes.toString().padLeft(2, '0')} мин';
  if (minutes > 0) return '$minutes мин';
  return '$secs сек';
}

String formatMoney(double? value, [String currency = 'BYN']) {
  if (value == null) return '—';
  final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
  return '$fixed $currency';
}

int _asIntValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.'));
}

String? _nullableText(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
