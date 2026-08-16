enum StockOperationType { delivery, stocktake }

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
    required this.stockInitialized,
    required this.active,
  });

  final int id;
  final String name;
  final int categoryId;
  final String categoryName;
  final int bottleMl;
  final int wholeBottles;
  final int extraMl;
  final int minimumMl;
  final bool stockInitialized;
  final bool active;

  int get totalMl => wholeBottles * bottleMl + extraMl;
  bool get isEmpty => stockInitialized && totalMl == 0;
  bool get isLow => stockInitialized && totalMl <= minimumMl;

  Product copyWith({int? wholeBottles, int? extraMl, bool? stockInitialized}) => Product(
        id: id,
        name: name,
        categoryId: categoryId,
        categoryName: categoryName,
        bottleMl: bottleMl,
        wholeBottles: wholeBottles ?? this.wholeBottles,
        extraMl: extraMl ?? this.extraMl,
        minimumMl: minimumMl,
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
  });

  final int id;
  final StockOperationType type;
  final DateTime createdAt;
  final List<StockOperationLine> lines;
}

class StockOperationLine {
  const StockOperationLine({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.bottleMl,
    required this.beforeTotalMl,
    required this.changeTotalMl,
    required this.afterTotalMl,
  });

  final int productId;
  final String productName;
  final String categoryName;
  final int bottleMl;
  final int beforeTotalMl;
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

  int get addedMl => bottles * product.bottleMl + extraMl;
}

class StocktakeDraftLine {
  const StocktakeDraftLine({required this.bottles, required this.extraMl});

  final int bottles;
  final int extraMl;
}

String formatBottleVolume(int ml) {
  if (ml % 1000 == 0) return '${ml ~/ 1000} л';
  final value = (ml / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${value.replaceAll('.', ',')} л';
}

String formatStockParts(int totalMl, int bottleMl) {
  if (bottleMl <= 0) return '$totalMl мл';
  final bottles = totalMl ~/ bottleMl;
  final extra = totalMl % bottleMl;
  return '$bottles бут. + $extra мл';
}

String formatLiters(int ml) {
  final liters = ml / 1000;
  final value = liters.toStringAsFixed(liters < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${value.replaceAll('.', ',')} л';
}

String formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
}
