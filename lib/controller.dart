import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import 'data/remote_stock_service.dart';
import 'data/remote_sync_repository.dart';
import 'data/repository.dart';
import 'models.dart';

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

  List<Category> categories = const [];
  List<Product> products = const [];
  List<StockOperation> operations = const [];
  List<StocktakeDraft> activeStocktakeDrafts = const [];
  bool loading = true;
  String? error;
  String? syncWarning;

  String? _sessionPin;
  int? _lastRemoteVersion;
  Timer? _pollTimer;
  bool _remoteBusy = false;

  bool get sharedSyncEnabled => true;
  bool get hasOperationSession => _sessionPin != null;

  Future<void> initialize() async {
    await _loadLocal();
    await _pullRemote(silent: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollRemote());
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
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

  Future<void> setOperationSessionPin(String pin) async {
    _sessionPin = pin;
    syncWarning = null;
    await _syncCatalogToServer();
    await _syncAllDraftsBestEffort();
  }

  void clearOperationSessionPin() {
    _sessionPin = null;
  }

  Future<int> addCategory(String name) async {
    final id = await _repository.addCategory(name);
    categories = await _repository.getCategories();
    notifyListeners();
    await _syncCatalogIfAuthorized();
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
    await _syncCatalogIfAuthorized();
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required int categoryId,
    required int packageSize,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    await _repository.updateProduct(
      productId: productId,
      name: name,
      categoryId: categoryId,
      packageSize: packageSize,
      minimumAmount: minimumAmount,
      stockUnit: stockUnit,
    );
    await _reloadAfterMutation();
    await _syncCatalogIfAuthorized();
  }

  Future<void> receiveDelivery(List<DeliveryDraftLine> lines) async {
    final pin = _requireSessionPin();
    await _syncCatalogToServer();
    final response = await _remote.receiveDelivery(pin: pin, lines: lines);
    await _applyResponseSnapshot(response);
  }

  Future<String?> getLastStocktakeEmployee() => _repository.getLastStocktakeEmployee();

  Future<StocktakeDraft?> getActiveStocktakeDraft(String employeeName) =>
      _repository.getActiveStocktakeDraft(employeeName);

  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    _requireSessionPin();
    await _syncCatalogToServer();
    final draft = await _repository.createStocktakeDraft(employeeName);
    await _reloadDrafts();
    await _syncDraftBestEffort(draft.id);
    return draft;
  }

  Future<StocktakeDraft> resumeStocktakeDraft(int draftId) async {
    final draft = await _repository.resumeStocktakeDraft(draftId);
    await _reloadDrafts();
    await _syncDraftBestEffort(draftId);
    return draft;
  }

  Future<void> pauseStocktakeDraft(int draftId, int activeSeconds) async {
    await _repository.pauseStocktakeDraft(draftId, activeSeconds);
    await _reloadDrafts();
    await _syncDraftBestEffort(draftId);
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
    await _repository.deleteStocktakeDraft(draftId);
    _draftSyncTimers.remove(draftId)?.cancel();
    await _reloadDrafts();
    final pin = _sessionPin;
    if (pin != null) {
      try {
        await _remote.deleteDraft(pin: pin, employee: draft.employeeName);
      } catch (e) {
        syncWarning = 'Черновик удалён локально, но сервер пока недоступен: $e';
        notifyListeners();
      }
    }
  }

  Future<int> completeStocktakeDraft(int draftId, int activeSeconds) async {
    final pin = _requireSessionPin();
    _draftSyncTimers.remove(draftId)?.cancel();
    final draft = await _syncRepository.readDraft(draftId);
    if (!draft.isComplete) throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
    await _syncCatalogToServer();
    final response = await _remote.completeStocktake(pin: pin, draft: draft, activeSeconds: activeSeconds);
    await _repository.deleteStocktakeDraft(draftId);
    await _applyResponseSnapshot(response);
    return operations.isEmpty ? 0 : operations.first.id;
  }

  Future<void> onAppResumed() => _pullRemote(silent: true);

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
      final remoteProducts = snapshot['products'];
      if (remoteProducts is List && remoteProducts.isNotEmpty) {
        await _syncRepository.applySnapshot(snapshot);
        _lastRemoteVersion = _asInt(snapshot['version']);
        syncWarning = null;
        await _loadLocal();
      } else {
        _lastRemoteVersion = _asInt(snapshot['version']);
      }
    } catch (e) {
      if (!silent) rethrow;
      syncWarning = 'Офлайн-режим: общая база временно недоступна. Локальный черновик сохраняется.';
      notifyListeners();
    } finally {
      _remoteBusy = false;
    }
  }

  Future<void> _pollRemote() async {
    if (_remoteBusy) return;
    try {
      final version = await _remote.fetchVersion();
      if (_lastRemoteVersion == null || version != _lastRemoteVersion) {
        await _pullRemote(silent: true);
      }
    } catch (_) {
      // Background polling is best-effort. Local drafts keep working offline.
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
    final snapshot = response['snapshot'];
    if (snapshot is Map<String, dynamic>) {
      await _syncRepository.applySnapshot(snapshot);
      _lastRemoteVersion = _asInt(snapshot['version']);
      await _loadLocal();
    } else if (snapshot is Map) {
      await _syncRepository.applySnapshot(Map<String, dynamic>.from(snapshot));
      _lastRemoteVersion = _asInt(snapshot['version']);
      await _loadLocal();
    }
  }

  Future<void> _applyResponseSnapshot(Map<String, dynamic> response) async {
    final raw = response['snapshot'];
    if (raw is! Map) throw StateError('Сервер не вернул обновлённое состояние склада');
    final snapshot = Map<String, dynamic>.from(raw);
    await _syncRepository.applySnapshot(snapshot);
    _lastRemoteVersion = _asInt(snapshot['version']);
    syncWarning = null;
    await _loadLocal();
  }

  void _scheduleDraftSync(int draftId) {
    _draftSyncTimers.remove(draftId)?.cancel();
    _draftSyncTimers[draftId] = Timer(const Duration(milliseconds: 600), () => _syncDraftBestEffort(draftId));
  }

  Future<void> _syncDraftBestEffort(int draftId) async {
    final pin = _sessionPin;
    if (pin == null) return;
    try {
      final draft = await _syncRepository.readDraft(draftId);
      await _remote.syncDraft(pin: pin, draft: draft);
      syncWarning = null;
    } catch (e) {
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
    final pin = _sessionPin;
    if (pin == null) throw StateError('Сеанс защищённой операции завершён. Введите пароль ещё раз.');
    return pin;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final timer in _draftSyncTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
