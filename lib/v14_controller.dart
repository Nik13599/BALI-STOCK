import 'dart:typed_data';

import 'data/offline_mutation_repository.dart';
import 'data/remote_stock_service.dart';
import 'data/remote_stock_v14_extension.dart';
import 'data/v14_offline_repository.dart';
import 'models.dart';
import 'persistent_offline_controller.dart';
import 'security.dart';
import 'v14_models.dart';

class V14WarehouseController extends PersistentOfflineWarehouseController {
  V14WarehouseController({
    RemoteStockService? v14Remote,
    OfflineMutationRepository? outbox,
    V14OfflineRepository? v14Offline,
  })  : _v14Remote = v14Remote ?? RemoteStockService(),
        _outbox = outbox ?? OfflineMutationRepository(),
        _v14Offline = v14Offline ?? V14OfflineRepository();

  final RemoteStockService _v14Remote;
  final OfflineMutationRepository _outbox;
  final V14OfflineRepository _v14Offline;

  final Map<int, ProductV14Meta> _productMeta = {};
  List<CatalogAuditEntry> catalogAudit = const [];
  String? _v14Pin;

  ProductV14Meta metaFor(Product product) => _productMeta[product.id] ?? const ProductV14Meta();

  String productKeyFor(Product product) =>
      _v14Remote.productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize);

  List<CatalogAuditEntry> auditFor(Product product) {
    final key = productKeyFor(product);
    return catalogAudit.where((x) => x.productKey == key).toList(growable: false);
  }

  @override
  Future<void> initialize() async {
    await super.initialize();
    await _loadV14SnapshotBestEffort();
  }

  @override
  Future<void> refresh() async {
    await super.refresh();
    await _loadV14SnapshotBestEffort();
  }

  @override
  Future<void> setOperationSessionPin(String pin) async {
    _v14Pin = pin;
    await super.setOperationSessionPin(pin);
    await _loadV14SnapshotBestEffort();
  }

  @override
  void clearOperationSessionPin() {
    _v14Pin = null;
    super.clearOperationSessionPin();
  }

  @override
  Future<void> onAppResumed() async {
    await super.onAppResumed();
    await _loadV14SnapshotBestEffort();
  }

  Future<void> saveProductSales({
    required Product product,
    required String employee,
    required ProductV14Meta meta,
  }) async {
    _requireV14Pin();
    _productMeta[product.id] = meta;
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
    await refresh();
  }

  Future<void> saveProductSalesBatch({
    required String employee,
    required Map<Product, ProductV14Meta> changes,
  }) async {
    _requireV14Pin();
    if (changes.isEmpty) return;
    for (final entry in changes.entries) {
      _productMeta[entry.key.id] = entry.value;
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
    await refresh();
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
    _applyV14Snapshot(response['snapshot']);
    await super.refresh();
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
    await refresh();
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

  Future<void> _loadV14SnapshotBestEffort() async {
    try {
      final snapshot = await _v14Remote.fetchSnapshot();
      _applyV14Snapshot(snapshot);
    } catch (_) {
      // The base controller remains authoritative for offline stock quantities.
      // Keep the last V14 metadata in memory while connectivity is unavailable.
    }
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
    notifyListeners();
  }

  String _requireV14Pin() {
    final pin = _v14Pin ?? lastVerifiedOperationPin;
    if (pin == null || pin.isEmpty) throw StateError('Введите PIN для защищённого действия.');
    return pin;
  }
}
