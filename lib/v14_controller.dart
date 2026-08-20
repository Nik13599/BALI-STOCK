import 'dart:async';
import 'dart:typed_data';

import 'data/offline_mutation_repository.dart';
import 'data/remote_stock_service.dart';
import 'data/remote_stock_v14_extension.dart';
import 'data/v14_meta_cache_repository.dart';
import 'data/v14_offline_repository.dart';
import 'data/v14_schema_repository.dart';
import 'models.dart';
import 'persistent_offline_controller.dart';
import 'security.dart';
import 'v14_models.dart';

class V14WarehouseController extends PersistentOfflineWarehouseController {
  V14WarehouseController({
    RemoteStockService? v14Remote,
    OfflineMutationRepository? outbox,
    V14OfflineRepository? v14Offline,
    V14SchemaRepository? schema,
    V14MetaCacheRepository? v14Cache,
  })  : _v14Remote = v14Remote ?? RemoteStockService(),
        _outbox = outbox ?? OfflineMutationRepository(),
        _v14Offline = v14Offline ?? V14OfflineRepository(),
        _schema = schema ?? V14SchemaRepository(),
        _v14Cache = v14Cache ?? V14MetaCacheRepository();

  final RemoteStockService _v14Remote;
  final OfflineMutationRepository _outbox;
  final V14OfflineRepository _v14Offline;
  final V14SchemaRepository _schema;
  final V14MetaCacheRepository _v14Cache;

  final Map<int, ProductV14Meta> _productMeta = {};
  List<CatalogAuditEntry> catalogAudit = const [];
  List<Map<String, dynamic>> spotStocktakeHistory = const [];
  String? _v14Pin;

  ProductV14Meta metaFor(Product product) => _productMeta[product.id] ?? const ProductV14Meta();

  String productKeyFor(Product product) =>
      _v14Remote.productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize);

  int categorySortFor(Product product) {
    for (final item in categories) {
      if (item.id == product.categoryId || item.name.toLowerCase() == product.categoryName.toLowerCase()) return item.sortOrder;
    }
    return 0;
  }

  List<CatalogAuditEntry> auditFor(Product product) {
    final key = productKeyFor(product);
    return catalogAudit.where((x) => x.productKey == key).toList(growable: false);
  }

  @override
  Future<void> initialize() async {
    await _schema.ensureSchema();
    await _v14Cache.ensureSchema();
    final cached = await _v14Cache.loadSnapshot();
    await super.initialize();
    if (!sharedOnline && cached != null) _applyV14Snapshot(cached);
    await _applyPendingV14Meta();
  }

  @override
  Future<void> refresh() async {
    await super.refresh();
    await _applyPendingV14Meta();
    if (pendingSyncCount == 0) unawaited(_v14Cache.clearPending());
  }

  @override
  Future<void> setOperationSessionPin(String pin) {
    _v14Pin = pin;
    return super.setOperationSessionPin(pin);
  }

  @override
  void clearOperationSessionPin() {
    _v14Pin = null;
    super.clearOperationSessionPin();
  }

  @override
  Future<void> onAppResumed() => super.onAppResumed();

  @override
  void onSharedSnapshot(Map<String, dynamic> snapshot) {
    _applyV14Snapshot(snapshot);
    unawaited(_v14Cache.saveSnapshot(snapshot));
    if (pendingSyncCount == 0) unawaited(_v14Cache.clearPending());
  }

  @override
  Future<void> receiveDelivery(
    List<DeliveryDraftLine> lines, {
    String employee = '',
    String? supplierId,
    String? documentNumber,
    String? comment,
    String? attachmentUrl,
    String? locationId,
    Map<String, dynamic>? metadata,
  }) async {
    final withoutCost = lines.where((line) => line.unitCost == null).toList(growable: false);
    if (withoutCost.isNotEmpty) {
      final names = withoutCost.take(4).map((x) => x.product.name).join(', ');
      throw ArgumentError('Закупочная цена обязательна для каждой позиции поставки: $names${withoutCost.length > 4 ? '…' : ''}');
    }
    await super.receiveDelivery(
      lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: attachmentUrl,
      locationId: locationId,
      metadata: metadata,
    );
  }

  Future<void> saveProductSales({
    required Product product,
    required String employee,
    required ProductV14Meta meta,
  }) async {
    _requireV14Pin();
    _productMeta[product.id] = meta;
    await _v14Cache.savePending(productKeyFor(product), meta);
    notifyListeners();

    await _outbox.enqueue('product_meta_batch', {
      'action': 'product_meta_batch',
      'employee': employee.trim(),
      'items': [
        {
          'product_key': productKeyFor(product),
          'minimum_amount': product.minimumAmount,
          'target_amount': product.targetAmount,
          'variance_recheck_amount': product.varianceRecheckAmount,
          'barcode': product.barcode,
          'sell_by_bottle': meta.sellByBottle,
          'bottle_sale_price': meta.bottleSalePrice,
          'portion_sale': meta.portionSale,
          'portion_prices': meta.portions.map((x) => x.toJson()).toList(growable: false),
          'image_path': meta.imagePath,
        }
      ],
    });
    unawaited(refresh());
  }

  Future<void> saveProductSalesBatch({
    required String employee,
    required Map<Product, ProductV14Meta> changes,
  }) async {
    _requireV14Pin();
    if (changes.isEmpty) return;
    for (final entry in changes.entries) {
      _productMeta[entry.key.id] = entry.value;
      await _v14Cache.savePending(productKeyFor(entry.key), entry.value);
    }
    notifyListeners();

    await _outbox.enqueue('product_meta_batch', {
      'action': 'product_meta_batch',
      'employee': employee.trim(),
      'items': changes.entries
          .map((entry) => {
                'product_key': productKeyFor(entry.key),
                'minimum_amount': entry.key.minimumAmount,
                'target_amount': entry.key.targetAmount,
                'variance_recheck_amount': entry.key.varianceRecheckAmount,
                'barcode': entry.key.barcode,
                'sell_by_bottle': entry.value.sellByBottle,
                'bottle_sale_price': entry.value.bottleSalePrice,
                'portion_sale': entry.value.portionSale,
                'portion_prices': entry.value.portions.map((x) => x.toJson()).toList(growable: false),
                'image_path': entry.value.imagePath,
              })
          .toList(growable: false),
    });
    unawaited(refresh());
  }

  Future<void> saveProductCatalogBatch({
    required String employee,
    required Map<Product, ProductV14CatalogEdit> changes,
  }) async {
    _requireV14Pin();
    if (changes.isEmpty) return;
    final actor = employee.trim();
    if (actor.isEmpty) throw ArgumentError('Укажите ФИО сотрудника');

    final normalizedNames = <String>{};
    for (final entry in changes.entries) {
      final edit = entry.value;
      if (edit.name.trim().isEmpty) throw ArgumentError('Название товара не может быть пустым');
      if (edit.categoryName.trim().isEmpty) throw ArgumentError('Категория не может быть пустой');
      if (edit.packageSize <= 0) throw ArgumentError('Размер упаковки должен быть больше нуля');
      if (edit.minimumAmount < 0 || edit.targetAmount < 0 || edit.varianceRecheckAmount < 0) {
        throw ArgumentError('Минимум, цель и порог перепроверки не могут быть отрицательными');
      }
      final identity = '${edit.name.trim().toLowerCase()}|${edit.stockUnit.dbValue}|${edit.packageSize}';
      if (!normalizedNames.add(identity)) throw ArgumentError('В пакете есть дублирующиеся SKU: ${edit.name}');
      _productMeta[entry.key.id] = edit.meta;
      await _v14Cache.savePending(productKeyFor(entry.key), edit.meta);
    }
    notifyListeners();

    await _outbox.enqueue('catalog_product_batch', {
      'action': 'catalog_product_batch',
      'employee': actor,
      'items': changes.entries
          .map((entry) => entry.value.toPayload(product: entry.key, oldProductKey: productKeyFor(entry.key)))
          .toList(growable: false),
    });
    unawaited(refresh());
  }

  Future<void> uploadProductImage({
    required Product product,
    required String employee,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final pin = _requireV14Pin();
    if (!sharedOnline) {
      throw StateError('Загрузка изображения требует интернета. Остальные изменения карточки можно сохранить как офлайн-черновик.');
    }
    final response = await _v14Remote.uploadProductImage(
      pin: pin,
      product: product,
      employee: employee.trim(),
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final raw = response['snapshot'];
    if (raw is Map) {
      onSharedSnapshot(raw.map((key, value) => MapEntry('$key', value)));
    }
  }

  Future<int> spotStocktake({
    required Product product,
    required String employee,
    required int quantityBase,
    required SpotStocktakeReason reason,
    required String device,
    String? comment,
    String? locationId,
  }) async {
    _requireV14Pin();
    final operationId = await _v14Offline.applySpotStocktake(
      product: product,
      employee: employee,
      quantityBase: quantityBase,
      reason: reason,
      device: device,
      comment: comment,
    );
    await _outbox.enqueue('spot_stocktake', {
      'action': 'spot_stocktake',
      'employee': employee.trim(),
      'product_key': productKeyFor(product),
      'quantity_base': quantityBase,
      'reason': reason.label,
      'comment': comment,
      'device': device,
      'location_id': locationId,
      'metadata': {
        'local_operation_id': operationId,
        'source': 'BALI STOCK V14',
      },
    });
    unawaited(refresh());
    return operationId;
  }

  StockOperation? lastDeliveryFor(Product product) {
    for (final operation in operations) {
      if (operation.type != StockOperationType.delivery) continue;
      if (operation.lines.any((line) => line.productName.toLowerCase() == product.name.toLowerCase())) return operation;
    }
    return null;
  }

  StockOperationLine? lastDeliveryLineFor(Product product) {
    final operation = lastDeliveryFor(product);
    if (operation == null) return null;
    for (final line in operation.lines) {
      if (line.productName.toLowerCase() == product.name.toLowerCase()) return line;
    }
    return null;
  }

  Future<void> _applyPendingV14Meta() async {
    final pending = await _v14Cache.loadPending();
    if (pending.isEmpty) return;
    for (final product in products) {
      final meta = pending[productKeyFor(product)];
      if (meta != null) _productMeta[product.id] = meta;
    }
    notifyListeners();
  }

  void _applyV14Snapshot(Object? rawSnapshot) {
    if (rawSnapshot is! Map) return;
    final snapshot = rawSnapshot.map((key, value) => MapEntry('$key', value));
    final rawProducts = snapshot['products'];
    if (rawProducts is List) {
      final byKey = <String, Map<dynamic, dynamic>>{};
      for (final item in rawProducts.whereType<Map>()) {
        final key = '${item['product_key'] ?? ''}';
        if (key.isNotEmpty) byKey[key] = item;
      }
      for (final product in products) {
        final raw = byKey[productKeyFor(product)];
        if (raw != null) _productMeta[product.id] = ProductV14Meta.fromJson(raw);
      }
    }

    final rawAudit = snapshot['catalog_audit'];
    if (rawAudit is List) {
      catalogAudit = rawAudit.whereType<Map>().map(CatalogAuditEntry.fromJson).toList(growable: false);
    }

    final rawOperations = snapshot['operations'];
    if (rawOperations is List) {
      spotStocktakeHistory = rawOperations
          .whereType<Map>()
          .where((x) => '${x['operation_type'] ?? ''}' == 'spot_stocktake')
          .map((x) => x.map((key, value) => MapEntry('$key', value)))
          .toList(growable: false);
    }
    notifyListeners();
  }

  String _requireV14Pin() {
    final pin = _v14Pin ?? lastVerifiedOperationPin;
    if (pin == null || pin.isEmpty) throw StateError('Не удалось открыть автоматический сеанс операции.');
    _v14Pin ??= pin;
    return pin;
  }
}
