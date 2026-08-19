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
  String? _syncPin;
  bool _syncing = false;
  bool _polling = false;
  bool _offlineOnline = false;
  int _pendingSyncCount = 0;
  int? _lastSeenRemoteVersion;

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
    await _rememberRemoteVersionBestEffort();
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
    await _rememberRemoteVersionBestEffort();
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
    // This marker is only local and is replaced with the private server path
    // by bali-stock-sync-api when the outbox is delivered.
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
      // The full snapshot already succeeded; a failed lightweight version read
      // should not turn an otherwise healthy session into an offline state.
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
