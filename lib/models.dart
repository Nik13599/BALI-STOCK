enum StockOperationType { delivery, stocktake }

enum StockUnit { ml, gram, piece }

enum StocktakeDraftStatus { draft, inProgress }

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

  int get packageSize => bottleMl;
  int get wholePackages => wholeBottles;
  int get extraAmount => extraMl;
  int get minimumAmount => minimumMl;
  int get totalAmount => wholeBottles * bottleMl + extraMl;
  int get totalMl => totalAmount;
  bool get supportsRemainder => stockUnit != StockUnit.piece;
  bool get isEmpty => stockInitialized && totalAmount == 0;
  bool get isLow => stockInitialized && totalAmount <= minimumAmount;

  Product copyWith({int? wholeBottles, int? extraMl, bool? stockInitialized}) => Product(
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
}

class DeliveryDraftLine {
  const DeliveryDraftLine({
    required this.product,
    required this.bottles,
    required this.extraMl,
  });

  final Product product;
  final int bottles;
  final int extraMl;

  int get addedMl => bottles * product.packageSize + extraMl;
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
