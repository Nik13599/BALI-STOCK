import 'dart:async';

import 'controller.dart';
import 'data/offline_mutation_repository.dart';
import 'data/offline_operation_reader.dart';
import 'data/remote_stock_service.dart';
import 'data/remote_stock_sync_extension.dart';
import 'data/remote_sync_repository.dart';
import 'data/repository.dart';
import 'data/sync_payload_builder.dart';
import 'models.dart';
import 'security.dart';

class OfflineFirstWarehouseController extends WarehouseController {
  OfflineFirstWarehouseController({
    WarehouseRepository? localRepository,
    OfflineMutationRepository? offlineRepository,
    OfflineOperationReader? operationReader,
    RemoteStockService? remote,
    RemoteSyncRepository? syncRepository,
  })  : _local = localRepository ?? WarehouseRepository(),
        _offline = offlineRepository ?? OfflineMutationRepository(),
        _operationReader = operationReader ?? OfflineOperationReader(),
        _remoteSync = remote ?? RemoteStockService(),
        _draftReader = syncRepository ?? RemoteSyncRepository(),
        super(
          repository: localRepository,
          remote: remote,
          syncRepository: syncRepository,
        );

  final WarehouseRepository _local;
  final OfflineMutationRepository _offline;
  final OfflineOperationReader _operationReader;
  final RemoteStockService _remoteSync;
  final RemoteSyncRepository _draftReader;

  Timer? _offlinePollTimer;
  String? _syncPin;
  bool _syncing = false;
  bool _offlineOnline = false;
  int _pendingSyncCount = 0;

  int get pendingSyncCount => _pendingSyncCount;
  bool get hasPendingSync => _pendingSyncCount > 0;

  @override
  bool get sharedOnline => _offlineOnline || super.sharedOnline;

  @override
  bool get hasOperationSession => _syncPin != null || super.hasOperationSession;

  @override
  Future<void> initialize() async {
    await _offline.ensureSchema();
    await _reloadLocalOffline();
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount == 0) {
      try {
        await super.refresh();
        _offlineOnline = super.sharedOnline;
      } catch (_) {
        _offlineOnline = false;
      }
    } else {
      syncWarning = _pendingMessage();
      notifyListeners();
    }
    _offlinePollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _backgroundTick());
  }

  @override
  Future<void> refresh() async {
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount > 0) {
      await _reloadLocalOffline();
      await _flushPendingBestEffort();
      return;
    }
    await super.refresh();
    _offlineOnline = super.sharedOnline;
  }

  @override
  Future<void> setOperationSessionPin(String pin) async {
    _syncPin = pin;
    _pendingSyncCount = await _offline.pendingCount();

    if (_pendingSyncCount > 0) {
      try {
        await _remoteSync.authorize(pin);
        _offlineOnline = true;
        await _flushPendingBestEffort(refreshAfter: true);
      } catch (_) {
        _offlineOnline = false;
        syncWarning = _pendingMessage();
        notifyListeners();
      }
      return;
    }

    await super.setOperationSessionPin(pin);
    _offlineOnline = super.sharedOnline;
    if (!_offlineOnline) {
      syncWarning = 'Офлайн-режим: операции будут сохранены на устройстве и отправлены автоматически после восстановления связи.';
      notifyListeners();
    }
  }

  @override
  void clearOperationSessionPin() {
    if (_pendingSyncCount > 0) {
      // Keep the already verified PIN in volatile memory only until the queued
      // operations have been delivered. It is never written to SQLite.
      return;
    }
    _syncPin = null;
    super.clearOperationSessionPin();
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
    _requireLocalPin();
    await _offline.applyDelivery(
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: attachmentUrl,
      locationId: locationId,
    );
    await _offline.enqueue(
      'delivery',
      SyncPayloadBuilder.delivery(
        lines: lines,
        employee: employee,
        supplierId: supplierId,
        documentNumber: documentNumber,
        comment: comment,
        attachmentUrl: attachmentUrl,
        locationId: locationId,
        metadata: metadata,
      ),
    );
    await _afterLocalMutation();
  }

  @override
  Future<void> writeOff({
    required String employee,
    required String reason,
    required List<DeliveryDraftLine> lines,
    String? locationId,
    String? comment,
  }) async {
    _requireLocalPin();
    await _offline.applyWriteOff(
      employee: employee,
      reason: reason,
      lines: lines,
      locationId: locationId,
      comment: comment,
    );
    await _offline.enqueue(
      'writeoff',
      SyncPayloadBuilder.writeOff(
        employee: employee,
        reason: reason,
        lines: lines,
        locationId: locationId,
        comment: comment,
      ),
    );
    await _afterLocalMutation();
  }

  @override
  Future<void> transfer({
    required String employee,
    required String sourceLocationId,
    required String targetLocationId,
    required List<DeliveryDraftLine> lines,
    String? comment,
  }) async {
    _requireLocalPin();
    await _offline.applyTransfer(
      employee: employee,
      sourceLocationId: sourceLocationId,
      targetLocationId: targetLocationId,
      lines: lines,
      comment: comment,
    );
    await _offline.enqueue(
      'transfer',
      SyncPayloadBuilder.transfer(
        employee: employee,
        sourceLocationId: sourceLocationId,
        targetLocationId: targetLocationId,
        lines: lines,
        comment: comment,
      ),
    );
    await _afterLocalMutation();
  }

  @override
  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    _requireLocalPin();
    final draft = await _local.createStocktakeDraft(employeeName);
    await _reloadLocalOffline();
    return draft;
  }

  @override
  Future<void> deleteStocktakeDraft(int draftId) async {
    _requireLocalPin();
    final draft = await _draftReader.readDraft(draftId);
    await _local.deleteStocktakeDraft(draftId);
    await _offline.enqueue('draft_delete', SyncPayloadBuilder.draftDelete(draft.employeeName));
    await _afterLocalMutation();
  }

  @override
  Future<int> completeStocktakeDraft(
    int draftId,
    int activeSeconds, {
    required Map<int, String> comments,
    required Set<int> recheckedProductIds,
    required List<List<double>> signaturePoints,
  }) async {
    _requireLocalPin();
    final draft = await _draftReader.readDraft(draftId);
    if (!draft.isComplete) {
      throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
    }

    final payload = SyncPayloadBuilder.stocktake(
      draft: draft,
      activeSeconds: activeSeconds,
      comments: comments,
      recheckedProductIds: recheckedProductIds,
      signaturePoints: signaturePoints,
    );
    final operationId = await _local.completeStocktakeDraft(draftId, activeSeconds);
    await _offline.enqueue('stocktake', payload);
    await _offline.enqueue('draft_delete', SyncPayloadBuilder.draftDelete(draft.employeeName));
    await _afterLocalMutation();
    return operationId;
  }

  @override
  Future<void> correctOperation({
    required StockOperation operation,
    required String employee,
    required String reason,
    required Map<Product, int> deltas,
    String? locationId,
  }) async {
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount > 0 || !sharedOnline) {
      throw StateError('Корректировка исторической операции требует синхронизации, чтобы однозначно определить серверную операцию. Сначала дождитесь статуса «Синхронизировано».');
    }
    await super.correctOperation(
      operation: operation,
      employee: employee,
      reason: reason,
      deltas: deltas,
      locationId: locationId,
    );
  }

  @override
  Future<void> onAppResumed() async {
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount > 0) {
      await _flushPendingBestEffort(refreshAfter: true);
    } else {
      await super.onAppResumed();
      _offlineOnline = super.sharedOnline;
    }
  }

  Future<void> _backgroundTick() async {
    if (_syncing) return;
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount > 0) {
      await _flushPendingBestEffort(refreshAfter: true);
      return;
    }
    try {
      await super.onAppResumed();
      _offlineOnline = super.sharedOnline;
    } catch (_) {
      _offlineOnline = false;
    }
  }

  Future<void> _afterLocalMutation() async {
    await _reloadLocalOffline();
    _pendingSyncCount = await _offline.pendingCount();
    syncWarning = _pendingMessage();
    notifyListeners();
    await _flushPendingBestEffort(refreshAfter: true);
  }

  Future<void> _flushPendingBestEffort({bool refreshAfter = false}) async {
    if (_syncing) return;
    final pin = _syncPin ?? lastVerifiedOperationPin;
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount == 0) return;
    if (pin == null) {
      syncWarning = _pendingMessage();
      notifyListeners();
      return;
    }

    _syncing = true;
    try {
      await _remoteSync.authorize(pin);
      _offlineOnline = true;
      while (true) {
        final item = await _offline.nextPending();
        if (item == null) break;
        try {
          await _remoteSync.postQueued(pin, item.payload);
          await _offline.removePending(item.id);
        } catch (e) {
          await _offline.markFailed(item.id, e);
          _offlineOnline = false;
          break;
        }
      }
      _pendingSyncCount = await _offline.pendingCount();
      if (_pendingSyncCount == 0) {
        syncWarning = null;
        if (refreshAfter) {
          await super.setOperationSessionPin(pin);
          await super.refresh();
          _offlineOnline = super.sharedOnline;
        }
      } else {
        syncWarning = _pendingMessage();
      }
    } catch (_) {
      _offlineOnline = false;
      _pendingSyncCount = await _offline.pendingCount();
      syncWarning = _pendingMessage();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _reloadLocalOffline() async {
    final values = await Future.wait([
      _local.getCategories(),
      _local.getProducts(),
      _operationReader.getOperations(),
      _local.getActiveStocktakeDrafts(),
    ]);
    categories = values[0] as List<Category>;
    products = values[1] as List<Product>;
    operations = values[2] as List<StockOperation>;
    activeStocktakeDrafts = values[3] as List<StocktakeDraft>;
    loading = false;
    error = null;
    notifyListeners();
  }

  String _requireLocalPin() {
    final pin = _syncPin ?? lastVerifiedOperationPin;
    if (pin == null) throw StateError('Введите PIN для проведения операции.');
    _syncPin ??= pin;
    return pin;
  }

  String _pendingMessage() {
    if (_pendingSyncCount <= 0) return 'Синхронизировано';
    return 'Офлайн: $_pendingSyncCount ${_pendingSyncCount == 1 ? 'операция ожидает' : 'операций ожидают'} отправки. Данные сохранены на устройстве.';
  }

  @override
  void dispose() {
    _offlinePollTimer?.cancel();
    super.dispose();
  }
}
