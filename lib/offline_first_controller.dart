import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  final Map<int, Timer> _draftQueueTimers = {};
  String? _syncPin;
  bool _syncing = false;
  bool _polling = false;
  bool _offlineOnline = false;
  int _pendingSyncCount = 0;
  int? _lastSeenRemoteVersion;
  Future<void>? _sessionPreparation;

  Map<String, dynamic>? _stagedInvoiceAttachment;
  Map<String, dynamic>? _stagedInvoiceScan;

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
        await _rememberRemoteVersionBestEffort();
      } catch (_) {
        _offlineOnline = false;
      }
    } else {
      syncWarning = _pendingMessage();
      notifyListeners();
    }
    _offlinePollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _backgroundTick());
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
    await _rememberRemoteVersionBestEffort();
  }

  @override
  Future<void> setOperationSessionPin(String pin) {
    _syncPin = pin;
    super.primeOperationSessionPin(pin);
    if (_sessionPreparation == null) {
      final task = _prepareOperationSession(pin);
      _sessionPreparation = task;
      unawaited(task.whenComplete(() => _sessionPreparation = null));
    }
    return Future<void>.value();
  }

  Future<void> _prepareOperationSession(String pin) async {
    _pendingSyncCount = await _offline.pendingCount();
    if (_pendingSyncCount > 0) {
      await _flushPendingBestEffort(refreshAfter: true);
      return;
    }

    await super.setOperationSessionPin(pin);
    _offlineOnline = super.sharedOnline;
    await _rememberRemoteVersionBestEffort();
    if (!_offlineOnline) {
      syncWarning = 'Офлайн-режим: операции будут сохранены на устройстве и отправлены автоматически после восстановления связи.';
      notifyListeners();
    }
  }

  @override
  void clearOperationSessionPin() {
    if (_pendingSyncCount > 0) {
      // Keep the already verified automatic credential in volatile memory only
      // until queued operations have been delivered. It is never written to SQLite.
      return;
    }
    _syncPin = null;
    super.clearOperationSessionPin();
  }

  @override
  Future<String> uploadInvoiceAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    _requireLocalPin();
    if (bytes.isEmpty) throw StateError('Файл накладной пустой.');
    if (bytes.length > 15728640) {
      throw StateError('Файл накладной больше 15 МБ. Уменьшите размер изображения.');
    }
    _stagedInvoiceAttachment = {
      'file_name': fileName,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    };
    return 'pending://invoice/${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<String> saveInvoiceScan({
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? attachmentUrl,
    required String rawText,
    required List<DeliveryDraftLine> lines,
  }) async {
    _requireLocalPin();
    _stagedInvoiceScan = {
      'employee': employee,
      'supplier_id': supplierId,
      'document_number': documentNumber,
      'raw_text': rawText,
      'lines': lines
          .map((line) => {
                'source_text': line.sourceText ?? line.product.name,
                'product_key': SyncPayloadBuilder.productKey(
                  name: line.product.name,
                  unit: line.product.stockUnit,
                  packageSize: line.product.packageSize,
                ),
                'recognized_quantity': line.addedMl,
                'recognized_packages': line.bottles,
                'unit_cost': line.unitCost,
                'confidence': line.confidence,
                'manually_corrected': line.manuallyCorrected,
              })
          .toList(growable: false),
    };
    return 'pending://invoice-scan/${DateTime.now().microsecondsSinceEpoch}';
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
    final stagedAttachment = _stagedInvoiceAttachment;
    final stagedScan = _stagedInvoiceScan;
    final hasBundle = stagedAttachment != null || stagedScan != null;

    await _offline.applyDelivery(
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: stagedAttachment == null ? attachmentUrl : 'pending://invoice',
      locationId: locationId,
    );

    final cleanMetadata = <String, dynamic>{...?metadata};
    cleanMetadata.remove('invoice_scan_id');
    cleanMetadata['offline_first'] = true;
    cleanMetadata['ocr_used'] = stagedScan != null || cleanMetadata['ocr_used'] == true;
    cleanMetadata['invoice_archived'] = stagedAttachment != null || cleanMetadata['invoice_archived'] == true;

    final deliveryPayload = SyncPayloadBuilder.delivery(
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: hasBundle ? null : attachmentUrl,
      locationId: locationId,
      metadata: cleanMetadata,
    );

    if (hasBundle) {
      await _offline.enqueue('delivery_bundle', {
        'action': 'delivery_bundle',
        'delivery': deliveryPayload,
        if (stagedAttachment != null) 'attachment': stagedAttachment,
        if (stagedScan != null) 'scan': stagedScan,
      });
    } else {
      await _offline.enqueue('delivery', deliveryPayload);
    }

    _stagedInvoiceAttachment = null;
    _stagedInvoiceScan = null;
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
    _requireLocalPin();
    await _local.updateProductControlCache(
      productId: product.id,
      minimumAmount: minimumAmount,
      targetAmount: targetAmount,
      varianceRecheckAmount: varianceRecheckAmount,
      barcode: barcode,
    );
    final productKey = SyncPayloadBuilder.productKey(
      name: product.name,
      unit: product.stockUnit,
      packageSize: product.packageSize,
    );
    await _offline.enqueueLatest(
      'product_meta',
      {
        'action': 'product_meta',
        'employee': employee.trim(),
        'product_key': productKey,
        'minimum_amount': minimumAmount,
        'target_amount': targetAmount,
        'variance_recheck_amount': varianceRecheckAmount,
        'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      },
      coalesceKey: 'product_meta:$productKey',
    );
    await _afterLocalMutation();
  }

  @override
  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    _requireLocalPin();
    final draft = await _local.createStocktakeDraft(employeeName);
    await _queueDraftSnapshot(draft);
    await _reloadLocalOffline();
    return draft;
  }

  @override
  Future<StocktakeDraft> resumeStocktakeDraft(int draftId) async {
    _requireLocalPin();
    final draft = await _local.resumeStocktakeDraft(draftId);
    await _queueDraftSnapshot(draft);
    await _reloadLocalOffline();
    return draft;
  }

  @override
  Future<void> pauseStocktakeDraft(int draftId, int activeSeconds) async {
    _requireLocalPin();
    await _local.pauseStocktakeDraft(draftId, activeSeconds);
    _draftQueueTimers.remove(draftId)?.cancel();
    await _queueDraftById(draftId);
    await _reloadLocalOffline();
  }

  @override
  Future<void> saveStocktakeActiveSeconds(int draftId, int activeSeconds) async {
    _requireLocalPin();
    await _local.saveStocktakeActiveSeconds(draftId, activeSeconds);
    _scheduleDraftQueue(draftId);
  }

  @override
  Future<void> saveStocktakeDraftLine({
    required int draftId,
    required int productId,
    required int? wholePackages,
    required int? extraAmount,
  }) async {
    _requireLocalPin();
    await _local.saveStocktakeDraftLine(
      draftId: draftId,
      productId: productId,
      wholePackages: wholePackages,
      extraAmount: extraAmount,
    );
    _scheduleDraftQueue(draftId);
  }

  @override
  Future<void> deleteStocktakeDraft(int draftId) async {
    _requireLocalPin();
    final draft = await _draftReader.readDraft(draftId);
    _draftQueueTimers.remove(draftId)?.cancel();
    await _local.deleteStocktakeDraft(draftId);
    final key = _draftCoalesceKey(draft);
    await _offline.removeCoalesced('draft_sync', key);
    await _offline.enqueueLatest(
      'draft_delete',
      SyncPayloadBuilder.draftDelete(
        draft.employeeName,
        startedAt: draft.startedAt,
      ),
      coalesceKey: key,
    );
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
    _draftQueueTimers.remove(draftId)?.cancel();
    final operationId = await _local.completeStocktakeDraft(draftId, activeSeconds);
    final key = _draftCoalesceKey(draft);
    await _offline.removeCoalesced('draft_sync', key);
    await _offline.enqueue('stocktake', payload);
    await _offline.enqueueLatest(
      'draft_delete',
      SyncPayloadBuilder.draftDelete(
        draft.employeeName,
        startedAt: draft.startedAt,
      ),
      coalesceKey: key,
    );
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
      await _rememberRemoteVersionBestEffort();
    }
  }

  Future<void> _backgroundTick() async {
    if (_syncing || _polling) return;
    _polling = true;
    try {
      _pendingSyncCount = await _offline.pendingCount();
      if (_pendingSyncCount > 0) {
        await _flushPendingBestEffort(refreshAfter: true);
        return;
      }

      final version = await _remoteSync.fetchVersion();
      _offlineOnline = true;
      final previousVersion = _lastSeenRemoteVersion;
      _lastSeenRemoteVersion = version;
      if (previousVersion == null || version != previousVersion) {
        await super.onAppResumed();
        _offlineOnline = super.sharedOnline;
        await _rememberRemoteVersionBestEffort();
      }
    } catch (_) {
      _offlineOnline = false;
    } finally {
      _polling = false;
    }
  }

  Future<void> _rememberRemoteVersionBestEffort() async {
    if (!_offlineOnline && !super.sharedOnline) return;
    try {
      _lastSeenRemoteVersion = await _remoteSync.fetchVersion();
    } catch (_) {
      // A failed lightweight version read should not turn a healthy snapshot
      // into a blocking UI error.
    }
  }

  Future<void> _afterLocalMutation() async {
    await _reloadLocalOffline();
    _pendingSyncCount = await _offline.pendingCount();
    syncWarning = _pendingMessage();
    notifyListeners();
    unawaited(_flushPendingBestEffort(refreshAfter: true));
  }

  Future<void> _queueDraftById(int draftId) async {
    final draft = await _draftReader.readDraft(draftId);
    await _queueDraftSnapshot(draft);
  }

  void _scheduleDraftQueue(int draftId) {
    _draftQueueTimers.remove(draftId)?.cancel();
    _draftQueueTimers[draftId] = Timer(const Duration(milliseconds: 600), () async {
      _draftQueueTimers.remove(draftId);
      try {
        await _queueDraftById(draftId);
      } catch (_) {
        // The SQLite draft remains authoritative and will be queued on pause,
        // resume or the next edit if the app lifecycle changed mid-debounce.
      }
    });
  }

  Future<void> _queueDraftSnapshot(StocktakeDraft draft) async {
    await _offline.enqueueLatest(
      'draft_sync',
      SyncPayloadBuilder.draftSync(draft),
      coalesceKey: _draftCoalesceKey(draft),
    );
    _pendingSyncCount = await _offline.pendingCount();
    syncWarning = _pendingMessage();
    notifyListeners();
    unawaited(_flushPendingBestEffort(refreshAfter: true));
  }

  String _draftCoalesceKey(StocktakeDraft draft) =>
      'draft:${draft.employeeName.trim().toLowerCase()}:${draft.startedAt.toUtc().toIso8601String()}';

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
      _offlineOnline = true;
      Map<String, dynamic>? latestSnapshot;
      while (true) {
        final item = await _offline.nextPending();
        if (item == null) break;
        try {
          final response = await _remoteSync.postQueued(pin, item.payload);
          final rawSnapshot = response['snapshot'];
          if (rawSnapshot is Map) {
            latestSnapshot = rawSnapshot.map((key, value) => MapEntry('$key', value));
          } else if (item.actionType != 'invoice_attachment_upload' && item.actionType != 'invoice_scan_save') {
            throw StateError('Сервер подтвердил операцию без обновлённого состояния склада');
          }
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
        if (latestSnapshot != null) {
          await applySharedSnapshot(latestSnapshot);
          _offlineOnline = true;
          await _rememberRemoteVersionBestEffort();
        } else if (refreshAfter) {
          await super.setOperationSessionPin(pin);
          _offlineOnline = super.sharedOnline;
          await _rememberRemoteVersionBestEffort();
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
    if (pin == null) throw StateError('Не удалось открыть автоматический сеанс операции.');
    _syncPin ??= pin;
    super.primeOperationSessionPin(pin);
    return pin;
  }

  String _pendingMessage() {
    if (_pendingSyncCount <= 0) return 'Синхронизировано';
    return 'Офлайн: $_pendingSyncCount ${_pendingSyncCount == 1 ? 'операция ожидает' : 'операций ожидают'} отправки. Данные сохранены на устройстве.';
  }

  @override
  void dispose() {
    _offlinePollTimer?.cancel();
    for (final timer in _draftQueueTimers.values) {
      timer.cancel();
    }
    _draftQueueTimers.clear();
    super.dispose();
  }
}
