import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' hide Category;

import 'data/remote_stock_service.dart';
import 'data/remote_sync_repository.dart';
import 'data/repository.dart';
import 'models.dart';
import 'security.dart';

class WarehouseController extends ChangeNotifier {
  WarehouseController({
    WarehouseRepository? repository,
    RemoteStockService? remote,
    RemoteSyncRepository? syncRepository,
  })  : _repository = repository ?? WarehouseRepository(),
        _remote = remote ?? RemoteStockService(),
        _syncRepository = syncRepository ?? RemoteSyncRepository();

  final WarehouseRepository _repository;
  final RemoteStockService _remote;
  final RemoteSyncRepository _syncRepository;
  final Map<int, Timer> _draftSyncTimers = {};
  final Map<int, String> _operationServerIds = {};

  List<Category> categories = const [];
  List<Product> products = const [];
  List<StockOperation> operations = const [];
  List<StocktakeDraft> activeStocktakeDrafts = const [];

  List<StockSupplier> suppliers = const [];
  List<ProductSupplierLink> productSuppliers = const [];
  List<StockLocation> locations = const [];
  List<StockLocationBalance> locationBalances = const [];
  List<PurchaseSuggestion> purchaseSuggestions = const [];
  StockAnalytics analytics = const StockAnalytics();

  bool loading = true;
  String? error;
  String? syncWarning;

  String? _sessionPin;
  int? _lastRemoteVersion;
  Timer? _pollTimer;
  bool _remoteBusy = false;
  bool _sharedOnline = false;

  bool get sharedSyncEnabled => true;
  bool get sharedOnline => _sharedOnline;
  bool get hasOperationSession => _sessionPin != null;
  StockLocation? get primaryLocation {
    for (final location in locations) {
      if (location.isPrimary && location.active) return location;
    }
    return locations.where((location) => location.active).firstOrNull;
  }

  Future<void> initialize() async {
    await _loadLocal();
    await _pullRemote(silent: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollRemote());
  }

  Future<void> refresh() async {
    final showBlockingLoader = products.isEmpty && categories.isEmpty && operations.isEmpty;
    if (showBlockingLoader) {
      loading = true;
      notifyListeners();
    }
    error = null;
    try {
      await _loadLocal();
      await _pullRemote(silent: true);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void primeOperationSessionPin(String pin) {
    _sessionPin = pin;
    syncWarning = null;
  }

  Future<void> setOperationSessionPin(String pin) async {
    primeOperationSessionPin(pin);
    try {
      final snapshot = await _remote.fetchSnapshot();
      _sharedOnline = true;
      final remoteProducts = snapshot['products'];
      if (remoteProducts is List && remoteProducts.isNotEmpty) {
        await _syncRepository.applySnapshot(snapshot);
        _lastRemoteVersion = _asInt(snapshot['version']);
        await _loadLocal();
        _applyControlSnapshot(snapshot);
      } else {
        await _syncCatalogToServer();
      }
      await _syncAllDraftsBestEffort();
    } catch (e) {
      _sharedOnline = false;
      syncWarning = 'Нет связи с общей базой. Существующий черновик можно продолжить офлайн; провести операцию получится после восстановления интернета.';
      notifyListeners();
    }
  }

  void clearOperationSessionPin() {
    _sessionPin = null;
    clearRememberedOperationPin();
  }

  Future<void> _ensureCatalogEditSession() async {
    _sessionPin ??= lastVerifiedOperationPin;
    if (_sessionPin == null) {
      throw StateError('Не удалось открыть автоматический сеанс изменения склада.');
    }
    if (!_sharedOnline) {
      throw StateError('Редактирование каталога требует связи с общей базой.');
    }
  }

  Future<int> addCategory(String name) async {
    await _ensureCatalogEditSession();
    final id = await _repository.addCategory(name);
    categories = await _repository.getCategories();
    notifyListeners();
    unawaited(_syncCatalogIfAuthorized());
    return id;
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
    await _ensureCatalogEditSession();
    await _repository.addProduct(
      name: name,
      categoryId: categoryId,
      packageSize: packageSize,
      wholePackages: wholePackages,
      extraAmount: extraAmount,
      minimumAmount: minimumAmount,
      stockUnit: stockUnit,
    );
    await _reloadAfterMutation();
    unawaited(_syncCatalogIfAuthorized());
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required int categoryId,
    required int packageSize,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    await _ensureCatalogEditSession();
    await _repository.updateProduct(
      productId: productId,
      name: name,
      categoryId: categoryId,
      packageSize: packageSize,
      minimumAmount: minimumAmount,
      stockUnit: stockUnit,
    );
    await _reloadAfterMutation();
    unawaited(_syncCatalogIfAuthorized());
  }

  Future<void> updateProductControl({
    required Product product,
    required String employee,
    required int minimumAmount,
    required int targetAmount,
    required int varianceRecheckAmount,
    String? barcode,
    double? defaultCost,
    String costCurrency = 'BYN',
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Изменение параметров товара');
    final response = await _remote.updateProductMeta(
      pin: pin,
      product: product,
      employee: employee,
      minimumAmount: minimumAmount,
      targetAmount: targetAmount,
      barcode: barcode ?? '',
      defaultCost: defaultCost,
      costCurrency: costCurrency,
      varianceRecheckAmount: varianceRecheckAmount,
    );
    await _applyResponseSnapshot(response);
  }

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
    final pin = _requireSessionPin();
    _ensureOnline('Поставку');
    final response = await _remote.receiveDelivery(
      pin: pin,
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: attachmentUrl,
      locationId: locationId,
      metadata: metadata,
    );
    await _applyResponseSnapshot(response);
  }

  Future<void> writeOff({
    required String employee,
    required String reason,
    required List<DeliveryDraftLine> lines,
    String? locationId,
    String? comment,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Списание');
    final response = await _remote.writeOff(
      pin: pin,
      employee: employee,
      reason: reason,
      lines: lines,
      locationId: locationId,
      comment: comment,
    );
    await _applyResponseSnapshot(response);
  }

  Future<void> transfer({
    required String employee,
    required String sourceLocationId,
    required String targetLocationId,
    required List<DeliveryDraftLine> lines,
    String? comment,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Перемещение');
    final response = await _remote.transfer(
      pin: pin,
      employee: employee,
      sourceLocationId: sourceLocationId,
      targetLocationId: targetLocationId,
      lines: lines,
      comment: comment,
    );
    await _applyResponseSnapshot(response);
  }

  Future<void> correctOperation({
    required StockOperation operation,
    required String employee,
    required String reason,
    required Map<Product, int> deltas,
    String? locationId,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Корректировку');
    final serverId = _operationServerIds[operation.id];
    if (serverId == null || serverId.isEmpty) throw StateError('Серверный номер операции не найден. Обновите историю.');
    final response = await _remote.correctOperation(
      pin: pin,
      employee: employee,
      originalOperationId: serverId,
      reason: reason,
      deltas: deltas,
      locationId: locationId,
    );
    await _applyResponseSnapshot(response);
  }

  Future<String> addSupplier({
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Добавление поставщика');
    final response = await _remote.upsertSupplier(
      pin: pin,
      name: name,
      contactPerson: contactPerson,
      phone: phone,
      email: email,
      notes: notes,
    );
    await _applyResponseSnapshot(response);
    return '${response['id'] ?? ''}';
  }

  Future<void> updateSupplier(StockSupplier supplier) async {
    final pin = _requireSessionPin();
    _ensureOnline('Изменение поставщика');
    final response = await _remote.upsertSupplier(
      pin: pin,
      id: supplier.id,
      name: supplier.name,
      contactPerson: supplier.contactPerson,
      phone: supplier.phone,
      email: supplier.email,
      notes: supplier.notes,
    );
    await _applyResponseSnapshot(response);
  }

  Future<void> linkSupplier({
    required Product product,
    required String supplierId,
    String? supplierSku,
    double? lastPrice,
    String currency = 'BYN',
    bool isPrimary = false,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Привязка поставщика');
    final response = await _remote.linkProductSupplier(
      pin: pin,
      product: product,
      supplierId: supplierId,
      supplierSku: supplierSku,
      lastPrice: lastPrice,
      currency: currency,
      isPrimary: isPrimary,
    );
    await _applyResponseSnapshot(response);
  }

  Future<String> addLocation(String name) async {
    final pin = _requireSessionPin();
    _ensureOnline('Добавление места хранения');
    final response = await _remote.upsertLocation(pin: pin, name: name);
    await _applyResponseSnapshot(response);
    return '${response['id'] ?? ''}';
  }

  Future<String> uploadInvoiceAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Загрузка накладной');
    return _remote.uploadInvoiceAttachment(pin: pin, bytes: bytes, fileName: fileName, mimeType: mimeType);
  }

  Future<String> invoiceAttachmentUrl(String path) async {
    final pin = _requireSessionPin();
    _ensureOnline('Открытие накладной');
    return _remote.createInvoiceAttachmentUrl(pin: pin, path: path);
  }

  Future<String> saveInvoiceScan({
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? attachmentUrl,
    required String rawText,
    required List<DeliveryDraftLine> lines,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Сохранение распознанной накладной');
    return _remote.saveInvoiceScan(
      pin: pin,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      attachmentUrl: attachmentUrl,
      rawText: rawText,
      lines: lines,
    );
  }

  Future<String> createPurchaseRequest({
    required String employee,
    required List<PurchaseSuggestion> items,
    String? supplierId,
    String? comment,
  }) async {
    final pin = _requireSessionPin();
    _ensureOnline('Создание заявки на закупку');
    final response = await _remote.createPurchaseRequest(
      pin: pin,
      employee: employee,
      items: items,
      supplierId: supplierId,
      comment: comment,
    );
    await _applyResponseSnapshot(response);
    return '${response['id'] ?? ''}';
  }

  List<StockSupplier> suppliersFor(Product product) {
    final key = _remote.productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize);
    final ids = productSuppliers.where((link) => link.productKey == key && link.active).map((link) => link.supplierId).toSet();
    return suppliers.where((supplier) => ids.contains(supplier.id) && supplier.active).toList(growable: false);
  }

  ProductSupplierLink? supplierLink(Product product, String supplierId) {
    final key = _remote.productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize);
    for (final link in productSuppliers) {
      if (link.productKey == key && link.supplierId == supplierId && link.active) return link;
    }
    return null;
  }

  int quantityAt(Product product, StockLocation location) {
    final key = _remote.productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize);
    for (final balance in locationBalances) {
      if (balance.productKey == key && balance.locationId == location.id && balance.initialized) return balance.quantityBase;
    }
    return 0;
  }

  Future<String?> getLastStocktakeEmployee() => _repository.getLastStocktakeEmployee();

  Future<StocktakeDraft?> getActiveStocktakeDraft(String employeeName) =>
      _repository.getActiveStocktakeDraft(employeeName);

  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    _requireSessionPin();
    if (!_sharedOnline) {
      throw StateError('Без интернета можно продолжить только уже сохранённый черновик. Новый переучёт требует актуального общего склада.');
    }
    final draft = await _repository.createStocktakeDraft(employeeName);
    await _reloadDrafts();
    unawaited(_syncDraftBestEffort(draft.id));
    return draft;
  }

  Future<StocktakeDraft> resumeStocktakeDraft(int draftId) async {
    final draft = await _repository.resumeStocktakeDraft(draftId);
    await _reloadDrafts();
    unawaited(_syncDraftBestEffort(draftId));
    return draft;
  }

  Future<void> pauseStocktakeDraft(int draftId, int activeSeconds) async {
    await _repository.pauseStocktakeDraft(draftId, activeSeconds);
    await _reloadDrafts();
    unawaited(_syncDraftBestEffort(draftId));
  }

  Future<void> saveStocktakeActiveSeconds(int draftId, int activeSeconds) async {
    await _repository.saveStocktakeActiveSeconds(draftId, activeSeconds);
    _scheduleDraftSync(draftId);
  }

  Future<void> saveStocktakeDraftLine({
    required int draftId,
    required int productId,
    required int? wholePackages,
    required int? extraAmount,
  }) async {
    await _repository.saveStocktakeDraftLine(
      draftId: draftId,
      productId: productId,
      wholePackages: wholePackages,
      extraAmount: extraAmount,
    );
    _scheduleDraftSync(draftId);
  }

  Future<void> deleteStocktakeDraft(int draftId) async {
    final draft = await _syncRepository.readDraft(draftId);
    if (!_sharedOnline) {
      throw StateError('Чтобы удалить общий черновик и начать заново, восстановите интернет. Текущий черновик можно продолжить офлайн.');
    }
    await _repository.deleteStocktakeDraft(draftId);
    _draftSyncTimers.remove(draftId)?.cancel();
    await _reloadDrafts();
    final pin = _sessionPin;
    if (pin != null) {
      await _remote.deleteDraft(pin: pin, employee: draft.employeeName);
    }
  }

  Future<int> completeStocktakeDraft(
    int draftId,
    int activeSeconds, {
    required Map<int, String> comments,
    required Set<int> recheckedProductIds,
    required List<List<double>> signaturePoints,
  }) async {
    final pin = _requireSessionPin();
    if (!_sharedOnline) {
      throw StateError('Переучёт сохранён как черновик, но провести его без интернета нельзя. Подключитесь к сети и нажмите «Завершить переучёт» ещё раз.');
    }
    _draftSyncTimers.remove(draftId)?.cancel();
    final draft = await _syncRepository.readDraft(draftId);
    if (!draft.isComplete) throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
    final response = await _remote.completeStocktake(
      pin: pin,
      draft: draft,
      activeSeconds: activeSeconds,
      comments: comments,
      recheckedProductIds: recheckedProductIds,
      signaturePoints: signaturePoints,
    );
    await _repository.deleteStocktakeDraft(draftId);
    await _applyResponseSnapshot(response);
    return operations.isEmpty ? 0 : operations.first.id;
  }

  Future<void> onAppResumed() async {
    await _pullRemote(silent: true);
    if (_sharedOnline && _sessionPin != null) {
      await _syncAllDraftsBestEffort();
    }
  }

  Future<void> _loadLocal() async {
    final values = await Future.wait([
      _repository.getCategories(),
      _repository.getProducts(),
      _repository.getOperations(),
      _repository.getActiveStocktakeDrafts(),
    ]);
    categories = values[0] as List<Category>;
    products = values[1] as List<Product>;
    operations = values[2] as List<StockOperation>;
    activeStocktakeDrafts = values[3] as List<StocktakeDraft>;
    loading = false;
    notifyListeners();
  }

  Future<void> _pullRemote({required bool silent}) async {
    if (_remoteBusy) return;
    _remoteBusy = true;
    try {
      final snapshot = await _remote.fetchSnapshot();
      _sharedOnline = true;
      final remoteProducts = snapshot['products'];
      if (remoteProducts is List && remoteProducts.isNotEmpty) {
        await _syncRepository.applySnapshot(snapshot);
        _lastRemoteVersion = _asInt(snapshot['version']);
        syncWarning = null;
        await _loadLocal();
        _applyControlSnapshot(snapshot);
      } else {
        _lastRemoteVersion = _asInt(snapshot['version']);
      }
    } catch (e) {
      _sharedOnline = false;
      if (!silent) rethrow;
      syncWarning = 'Офлайн-режим: общая база временно недоступна. Локальный черновик сохраняется.';
      notifyListeners();
    } finally {
      _remoteBusy = false;
    }
  }

  void _applyControlSnapshot(Map<String, dynamic> snapshot) {
    suppliers = _maps(snapshot['suppliers']).map(StockSupplier.fromJson).toList(growable: false);
    productSuppliers = _maps(snapshot['product_suppliers']).map(ProductSupplierLink.fromJson).toList(growable: false);
    locations = _maps(snapshot['locations']).map(StockLocation.fromJson).toList(growable: false);
    locationBalances = _maps(snapshot['location_balances']).map(StockLocationBalance.fromJson).toList(growable: false);
    purchaseSuggestions = _maps(snapshot['purchase_suggestions']).map(PurchaseSuggestion.fromJson).toList(growable: false);
    final analyticsRaw = snapshot['analytics'];
    analytics = StockAnalytics.fromJson(analyticsRaw is Map ? analyticsRaw : null);

    final remoteProducts = _maps(snapshot['products']);
    final metadataByName = <String, Map<dynamic, dynamic>>{
      for (final raw in remoteProducts) '${raw['name'] ?? ''}'.toLowerCase(): raw,
    };
    products = products.map((product) {
      final raw = metadataByName[product.name.toLowerCase()];
      if (raw == null) return product;
      return product.copyWith(
        targetAmount: _asInt(raw['target_amount']),
        barcode: _textOrNull(raw['barcode']),
        clearBarcode: raw['barcode'] == null || '${raw['barcode']}'.isEmpty,
        defaultCost: _asDouble(raw['default_cost']),
        costCurrency: '${raw['cost_currency'] ?? 'BYN'}',
        varianceRecheckAmount: _asInt(raw['variance_recheck_amount']),
      );
    }).toList(growable: false);

    final supplierNames = {for (final supplier in suppliers) supplier.id: supplier.name};
    final locationNames = {for (final location in locations) location.id: location.name};
    final remoteOperations = _maps(snapshot['operations']);
    final localIds = operations.map((operation) => operation.id).toList(growable: false);
    _operationServerIds.clear();
    final rebuilt = <StockOperation>[];
    for (var i = 0; i < remoteOperations.length; i++) {
      final raw = remoteOperations[i];
      final localId = i < localIds.length ? localIds[i] : -(i + 1);
      final serverId = '${raw['id'] ?? ''}';
      if (serverId.isNotEmpty) _operationServerIds[localId] = serverId;
      final supplierId = _textOrNull(raw['supplier_id']);
      final sourceId = _textOrNull(raw['source_location_id']);
      final targetId = _textOrNull(raw['target_location_id']);
      rebuilt.add(StockOperation(
        id: localId,
        type: StockOperationTypeX.fromDb(raw['operation_type'] as String?),
        createdAt: _date(raw['created_at']),
        employeeName: _textOrNull(raw['employee_name']),
        startedAt: _nullableDate(raw['started_at']),
        completedAt: _nullableDate(raw['completed_at']),
        activeSeconds: _asInt(raw['active_seconds']),
        totalSeconds: _asInt(raw['total_seconds']),
        supplierId: supplierId,
        supplierName: supplierId == null ? null : supplierNames[supplierId],
        documentNumber: _textOrNull(raw['document_number']),
        comment: _textOrNull(raw['comment']),
        attachmentUrl: _textOrNull(raw['attachment_url']),
        sourceLocationId: sourceId,
        sourceLocationName: sourceId == null ? null : locationNames[sourceId],
        targetLocationId: targetId,
        targetLocationName: targetId == null ? null : locationNames[targetId],
        correctionOf: _textOrNull(raw['correction_of']),
        totalValue: _asDouble(raw['total_value']),
        lines: _operationLines(raw['lines']),
      ));
    }
    operations = rebuilt;
    onSharedSnapshot(snapshot);
    notifyListeners();
  }

  @protected
  void onSharedSnapshot(Map<String, dynamic> snapshot) {}

  List<StockOperationLine> _operationLines(Object? value) {
    return _maps(value).map((line) {
      final productName = '${line['product_name'] ?? ''}';
      Product? product;
      for (final item in products) {
        if (item.name.toLowerCase() == productName.toLowerCase()) {
          product = item;
          break;
        }
      }
      return StockOperationLine(
        productId: product?.id ?? 0,
        productName: productName,
        categoryName: '${line['category_name'] ?? ''}',
        bottleMl: _asInt(line['package_size'], fallback: 1),
        stockUnit: StockUnitX.fromDb(line['stock_unit'] as String?),
        beforeTotalMl: _asInt(line['before_quantity']),
        beforeInitialized: line['before_initialized'] == true,
        changeTotalMl: _asInt(line['change_quantity']),
        afterTotalMl: _asInt(line['after_quantity']),
        unitCost: _asDouble(line['unit_cost']),
        lineValue: _asDouble(line['line_value']),
        comment: _textOrNull(line['comment']),
        sourceLocationId: _textOrNull(line['source_location_id']),
        targetLocationId: _textOrNull(line['target_location_id']),
      );
    }).toList(growable: false);
  }

  Future<void> _pollRemote() async {
    if (_remoteBusy) return;
    try {
      final version = await _remote.fetchVersion();
      _sharedOnline = true;
      if (_lastRemoteVersion == null || version != _lastRemoteVersion) {
        await _pullRemote(silent: true);
      }
    } catch (_) {
      _sharedOnline = false;
    }
  }

  Future<void> _syncCatalogIfAuthorized() async {
    if (_sessionPin == null) return;
    try {
      await _syncCatalogToServer();
    } catch (e) {
      syncWarning = 'Изменение сохранено локально, синхронизация каталога ожидает интернет: $e';
      notifyListeners();
    }
  }

  Future<void> _syncCatalogToServer() async {
    final pin = _requireSessionPin();
    final response = await _remote.syncCatalog(pin: pin, categories: categories, products: products);
    _sharedOnline = true;
    final snapshot = response['snapshot'];
    if (snapshot is Map) {
      final mapped = Map<String, dynamic>.from(snapshot);
      await _syncRepository.applySnapshot(mapped);
      _lastRemoteVersion = _asInt(mapped['version']);
      await _loadLocal();
      _applyControlSnapshot(mapped);
    }
  }

  Future<void> _applyResponseSnapshot(Map<String, dynamic> response) async {
    final raw = response['snapshot'];
    if (raw is! Map) throw StateError('Сервер не вернул обновлённое состояние склада');
    final snapshot = Map<String, dynamic>.from(raw);
    await _syncRepository.applySnapshot(snapshot);
    _lastRemoteVersion = _asInt(snapshot['version']);
    _sharedOnline = true;
    syncWarning = null;
    await _loadLocal();
    _applyControlSnapshot(snapshot);
  }

  void _scheduleDraftSync(int draftId) {
    _draftSyncTimers.remove(draftId)?.cancel();
    _draftSyncTimers[draftId] = Timer(const Duration(milliseconds: 600), () => _syncDraftBestEffort(draftId));
  }

  Future<void> _syncDraftBestEffort(int draftId) async {
    final pin = _sessionPin;
    if (pin == null || !_sharedOnline) return;
    try {
      final draft = await _syncRepository.readDraft(draftId);
      await _remote.syncDraft(pin: pin, draft: draft);
      syncWarning = null;
    } catch (e) {
      _sharedOnline = false;
      syncWarning = 'Черновик сохранён на устройстве. Сервер синхронизируется после восстановления связи.';
    }
    notifyListeners();
  }

  Future<void> _syncAllDraftsBestEffort() async {
    for (final draft in activeStocktakeDrafts) {
      await _syncDraftBestEffort(draft.id);
    }
  }

  Future<void> _reloadDrafts() async {
    activeStocktakeDrafts = await _repository.getActiveStocktakeDrafts();
    notifyListeners();
  }

  Future<void> _reloadAfterMutation() async {
    products = await _repository.getProducts();
    operations = await _repository.getOperations();
    activeStocktakeDrafts = await _repository.getActiveStocktakeDrafts();
    notifyListeners();
  }

  String _requireSessionPin() {
    final pin = _sessionPin ?? lastVerifiedOperationPin;
    if (pin == null || pin.isEmpty) throw StateError('Не удалось открыть автоматический сеанс операции.');
    _sessionPin ??= pin;
    return pin;
  }

  void _ensureOnline(String action) {
    if (!_sharedOnline) throw StateError('$action нельзя провести без связи с общей базой.');
  }

  static List<Map<dynamic, dynamic>> _maps(Object? value) =>
      value is List ? value.whereType<Map>().toList(growable: false) : const [];

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String? _textOrNull(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static DateTime _date(Object? value) => DateTime.tryParse('$value')?.toLocal() ?? DateTime.now();
  static DateTime? _nullableDate(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final timer in _draftSyncTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
