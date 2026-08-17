import 'dart:convert';
import 'dart:io';

import '../data/offline_mutation_repository.dart';
import '../data/sync_payload_builder.dart';
import '../models.dart';
import '../offline_first_controller.dart';

class OfflineDeliveryBundleService {
  OfflineDeliveryBundleService({OfflineMutationRepository? repository})
      : _repository = repository ?? OfflineMutationRepository();

  final OfflineMutationRepository _repository;

  Future<void> submit({
    required OfflineFirstWarehouseController controller,
    required List<DeliveryDraftLine> lines,
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? comment,
    String? locationId,
    String? invoicePath,
    String? rawOcrText,
  }) async {
    Map<String, dynamic>? attachment;
    if (invoicePath != null && invoicePath.isNotEmpty) {
      final file = File(invoicePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          if (bytes.length > 15728640) {
            throw StateError('Файл накладной больше 15 МБ. Уменьшите размер изображения.');
          }
          attachment = {
            'file_name': invoicePath.split(Platform.pathSeparator).last,
            'mime_type': _mimeForPath(invoicePath),
            'data_base64': base64Encode(bytes),
          };
        }
      }
    }

    final delivery = SyncPayloadBuilder.delivery(
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: null,
      locationId: locationId,
      metadata: {
        'ocr_used': rawOcrText?.trim().isNotEmpty == true,
        'invoice_archived': attachment != null,
        'offline_first': true,
      },
    );

    Map<String, dynamic>? scan;
    if (rawOcrText?.trim().isNotEmpty == true) {
      scan = {
        'employee': employee,
        'supplier_id': supplierId,
        'document_number': documentNumber,
        'raw_text': rawOcrText!.trim(),
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
    }

    // Commit the warehouse change to SQLite before any network activity.
    await _repository.applyDelivery(
      lines: lines,
      employee: employee,
      supplierId: supplierId,
      documentNumber: documentNumber,
      comment: comment,
      attachmentUrl: attachment == null ? null : 'pending://invoice',
      locationId: locationId,
    );

    await _repository.enqueue('delivery_bundle', {
      'action': 'delivery_bundle',
      'delivery': delivery,
      if (attachment != null) 'attachment': attachment,
      if (scan != null) 'scan': scan,
    });

    // Refresh always shows the just-committed local state. If network is
    // available the controller will also flush the outbox in the background.
    await controller.refresh();
    await controller.onAppResumed();
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }
}
