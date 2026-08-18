import 'models.dart';

class PortionPrice {
  const PortionPrice({required this.amount, required this.price});

  final int amount;
  final double price;

  factory PortionPrice.fromJson(Map<dynamic, dynamic> json) => PortionPrice(
        amount: _asInt(json['ml'], fallback: 1).clamp(1, 1 << 31).toInt(),
        price: (_asDouble(json['price']) ?? 0).clamp(0, double.infinity).toDouble(),
      );

  Map<String, dynamic> toJson() => {'ml': amount, 'price': price};
}

class ProductV14Meta {
  const ProductV14Meta({
    this.sellByBottle = false,
    this.bottleSalePrice,
    this.portionSale = false,
    this.portions = const [],
    this.imagePath,
    this.imageUrl,
  });

  final bool sellByBottle;
  final double? bottleSalePrice;
  final bool portionSale;
  final List<PortionPrice> portions;
  final String? imagePath;
  final String? imageUrl;

  factory ProductV14Meta.fromJson(Map<dynamic, dynamic>? json) {
    final map = json ?? const {};
    final rawPortions = map['portion_prices'];
    return ProductV14Meta(
      sellByBottle: map['sell_by_bottle'] == true,
      bottleSalePrice: _asDouble(map['bottle_sale_price']),
      portionSale: map['portion_sale'] == true,
      portions: rawPortions is List
          ? rawPortions.whereType<Map>().map(PortionPrice.fromJson).where((x) => x.amount > 0).toList(growable: false)
          : const [],
      imagePath: _text(map['image_path']),
      imageUrl: _text(map['image_url']),
    );
  }

  ProductV14Meta copyWith({
    bool? sellByBottle,
    double? bottleSalePrice,
    bool clearBottleSalePrice = false,
    bool? portionSale,
    List<PortionPrice>? portions,
    String? imagePath,
    bool clearImagePath = false,
    String? imageUrl,
    bool clearImageUrl = false,
  }) =>
      ProductV14Meta(
        sellByBottle: sellByBottle ?? this.sellByBottle,
        bottleSalePrice: clearBottleSalePrice ? null : (bottleSalePrice ?? this.bottleSalePrice),
        portionSale: portionSale ?? this.portionSale,
        portions: portions ?? this.portions,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      );

  Map<String, dynamic> toJson() => {
        'sell_by_bottle': sellByBottle,
        'bottle_sale_price': bottleSalePrice,
        'portion_sale': portionSale,
        'portion_prices': portions.map((x) => x.toJson()).toList(growable: false),
        'image_path': imagePath,
        'image_url': imageUrl,
      };
}

class ProductV14CatalogEdit {
  const ProductV14CatalogEdit({
    required this.name,
    required this.categoryName,
    required this.categorySort,
    required this.packageSize,
    required this.stockUnit,
    required this.minimumAmount,
    required this.targetAmount,
    required this.varianceRecheckAmount,
    required this.meta,
    this.barcode,
  });

  final String name;
  final String categoryName;
  final int categorySort;
  final int packageSize;
  final StockUnit stockUnit;
  final int minimumAmount;
  final int targetAmount;
  final int varianceRecheckAmount;
  final String? barcode;
  final ProductV14Meta meta;

  factory ProductV14CatalogEdit.fromProduct(
    Product product,
    ProductV14Meta meta, {
    int categorySort = 0,
  }) =>
      ProductV14CatalogEdit(
        name: product.name,
        categoryName: product.categoryName,
        categorySort: categorySort,
        packageSize: product.packageSize,
        stockUnit: product.stockUnit,
        minimumAmount: product.minimumAmount,
        targetAmount: product.targetAmount,
        varianceRecheckAmount: product.varianceRecheckAmount,
        barcode: product.barcode,
        meta: meta,
      );

  ProductV14CatalogEdit copyWith({
    String? name,
    String? categoryName,
    int? categorySort,
    int? packageSize,
    StockUnit? stockUnit,
    int? minimumAmount,
    int? targetAmount,
    int? varianceRecheckAmount,
    String? barcode,
    bool clearBarcode = false,
    ProductV14Meta? meta,
  }) =>
      ProductV14CatalogEdit(
        name: name ?? this.name,
        categoryName: categoryName ?? this.categoryName,
        categorySort: categorySort ?? this.categorySort,
        packageSize: packageSize ?? this.packageSize,
        stockUnit: stockUnit ?? this.stockUnit,
        minimumAmount: minimumAmount ?? this.minimumAmount,
        targetAmount: targetAmount ?? this.targetAmount,
        varianceRecheckAmount: varianceRecheckAmount ?? this.varianceRecheckAmount,
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        meta: meta ?? this.meta,
      );

  bool sameAs(Product product, ProductV14Meta originalMeta, {required int categorySort}) {
    return name == product.name &&
        categoryName == product.categoryName &&
        this.categorySort == categorySort &&
        packageSize == product.packageSize &&
        stockUnit == product.stockUnit &&
        minimumAmount == product.minimumAmount &&
        targetAmount == product.targetAmount &&
        varianceRecheckAmount == product.varianceRecheckAmount &&
        (barcode ?? '') == (product.barcode ?? '') &&
        _sameMeta(meta, originalMeta);
  }

  Map<String, dynamic> toPayload({required Product product, required String oldProductKey}) => {
        'old_product_key': oldProductKey,
        'name': name.trim(),
        'category_name': categoryName.trim(),
        'category_sort': categorySort,
        'package_size': packageSize,
        'stock_unit': stockUnit.dbValue,
        'minimum_amount': minimumAmount,
        'target_amount': targetAmount,
        'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
        'default_cost': product.defaultCost,
        'cost_currency': product.costCurrency,
        'variance_recheck_amount': varianceRecheckAmount,
        'active': product.active,
        'sell_by_bottle': meta.sellByBottle,
        'bottle_sale_price': meta.bottleSalePrice,
        'portion_sale': meta.portionSale,
        'portion_prices': meta.portions.map((x) => x.toJson()).toList(growable: false),
        'image_path': meta.imagePath,
      };
}

class CatalogAuditEntry {
  const CatalogAuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    this.productKey,
    this.actor,
    this.beforeData,
    this.afterData,
  });

  final int id;
  final String action;
  final String? productKey;
  final String? actor;
  final DateTime createdAt;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;

  factory CatalogAuditEntry.fromJson(Map<dynamic, dynamic> json) => CatalogAuditEntry(
        id: _asInt(json['id']),
        action: '${json['action'] ?? ''}',
        productKey: _text(json['product_key']),
        actor: _text(json['actor']),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        beforeData: _stringMap(json['before_data']),
        afterData: _stringMap(json['after_data']),
      );
}

enum StockListViewMode { compact, detailed, table }

enum StockSortMode { name, category, quantity, purchasePrice, salePrice, margin, stockValue }

enum SpotStocktakeReason {
  breakage('бой'),
  spill('пролив'),
  previousCountError('ошибка предыдущего учёта'),
  surplusFound('найден излишек'),
  shortage('недостача'),
  serviceUse('служебное использование'),
  other('другая причина');

  const SpotStocktakeReason(this.label);
  final String label;
}

class ProductEconomics {
  const ProductEconomics({required this.product, required this.meta});

  final Product product;
  final ProductV14Meta meta;

  double? get purchasePerPackage => product.defaultCost;

  double? get costPerBaseUnit {
    final cost = purchasePerPackage;
    if (cost == null || product.packageSize <= 0) return null;
    return cost / product.packageSize;
  }

  double? get stockCost {
    final unit = costPerBaseUnit;
    if (unit == null || !product.stockInitialized) return null;
    return product.totalAmount * unit;
  }

  double? get bottleGrossProfit {
    final cost = purchasePerPackage;
    final sale = meta.bottleSalePrice;
    if (!meta.sellByBottle || cost == null || sale == null) return null;
    return sale - cost;
  }

  double? get bottleMarkupPercent {
    final cost = purchasePerPackage;
    final profit = bottleGrossProfit;
    if (cost == null || cost == 0 || profit == null) return null;
    return profit / cost * 100;
  }

  double? get bottleMarginPercent {
    final sale = meta.bottleSalePrice;
    final profit = bottleGrossProfit;
    if (sale == null || sale == 0 || profit == null) return null;
    return profit / sale * 100;
  }

  double? portionCost(PortionPrice portion) {
    final unit = costPerBaseUnit;
    if (unit == null) return null;
    return unit * portion.amount;
  }

  double? portionGrossProfit(PortionPrice portion) {
    final cost = portionCost(portion);
    return cost == null ? null : portion.price - cost;
  }

  double? portionMarginPercent(PortionPrice portion) {
    final profit = portionGrossProfit(portion);
    if (portion.price == 0 || profit == null) return null;
    return profit / portion.price * 100;
  }

  double? potentialBottleRevenue() {
    final price = meta.bottleSalePrice;
    if (!meta.sellByBottle || price == null || !product.stockInitialized || product.packageSize <= 0) return null;
    return product.totalAmount / product.packageSize * price;
  }

  double? potentialPortionRevenue(PortionPrice portion) {
    if (!meta.portionSale || portion.amount <= 0 || !product.stockInitialized) return null;
    return product.totalAmount / portion.amount * portion.price;
  }
}

bool _sameMeta(ProductV14Meta a, ProductV14Meta b) {
  if (a.sellByBottle != b.sellByBottle ||
      a.bottleSalePrice != b.bottleSalePrice ||
      a.portionSale != b.portionSale ||
      a.imagePath != b.imagePath ||
      a.portions.length != b.portions.length) {
    return false;
  }
  for (var i = 0; i < a.portions.length; i++) {
    if (a.portions[i].amount != b.portions[i].amount || a.portions[i].price != b.portions[i].price) return false;
  }
  return true;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.'));
}

String? _text(Object? value) {
  if (value == null) return null;
  final s = '$value'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry('$key', item));
}
