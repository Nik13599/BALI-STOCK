import '../models.dart';

class SyncPayloadBuilder {
  const SyncPayloadBuilder._();

  static String productKey({
    required String name,
    required StockUnit unit,
    required int packageSize,
  }) => '${name.trim().toLowerCase()}|${unit.dbValue}|$packageSize';

  static Map<String, dynamic> delivery({
    required List<DeliveryDraftLine> lines,
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? comment,
    String? attachmentUrl,
    String? locationId,
    Map<String, dynamic>? metadata,
  }) => {
        'action': 'delivery',
        'employee': employee,
        'supplier_id': supplierId,
        'document_number': documentNumber,
        'comment': comment,
        'attachment_url': attachmentUrl,
        'location_id': locationId,
        'metadata': metadata ?? const <String, dynamic>{},
        'lines': lines
            .map((line) => {
                  'product_key': productKey(
                    name: line.product.name,
                    unit: line.product.stockUnit,
                    packageSize: line.product.packageSize,
                  ),
                  'quantity_base': line.addedMl,
                  'unit_cost': line.unitCost,
                  'currency': line.product.costCurrency,
                  'metadata': {
                    if (line.sourceText != null) 'ocr_source': line.sourceText,
                    if (line.confidence != null) 'ocr_confidence': line.confidence,
                    'manually_corrected': line.manuallyCorrected,
                  },
                })
            .toList(growable: false),
      };

  static Map<String, dynamic> writeOff({
    required String employee,
    required String reason,
    required List<DeliveryDraftLine> lines,
    String? locationId,
    String? comment,
  }) => {
        'action': 'writeoff',
        'employee': employee,
        'reason': reason,
        'location_id': locationId,
        'comment': comment,
        'lines': lines
            .map((line) => {
                  'product_key': productKey(
                    name: line.product.name,
                    unit: line.product.stockUnit,
                    packageSize: line.product.packageSize,
                  ),
                  'quantity_base': line.addedMl,
                  'comment': line.sourceText,
                })
            .toList(growable: false),
      };

  static Map<String, dynamic> transfer({
    required String employee,
    required String sourceLocationId,
    required String targetLocationId,
    required List<DeliveryDraftLine> lines,
    String? comment,
  }) => {
        'action': 'transfer',
        'employee': employee,
        'source_location_id': sourceLocationId,
        'target_location_id': targetLocationId,
        'comment': comment,
        'lines': lines
            .map((line) => {
                  'product_key': productKey(
                    name: line.product.name,
                    unit: line.product.stockUnit,
                    packageSize: line.product.packageSize,
                  ),
                  'quantity_base': line.addedMl,
                })
            .toList(growable: false),
      };

  static Map<String, dynamic> correction({
    required String employee,
    required String originalOperationId,
    required String reason,
    required Map<Product, int> deltas,
    String? locationId,
  }) => {
        'action': 'correction',
        'employee': employee,
        'correction_of': originalOperationId,
        'reason': reason,
        'location_id': locationId,
        'lines': deltas.entries
            .where((entry) => entry.value != 0)
            .map((entry) => {
                  'product_key': productKey(
                    name: entry.key.name,
                    unit: entry.key.stockUnit,
                    packageSize: entry.key.packageSize,
                  ),
                  'delta_quantity': entry.value,
                })
            .toList(growable: false),
      };

  static Map<String, dynamic> stocktake({
    required StocktakeDraft draft,
    required int activeSeconds,
    required Map<int, String> comments,
    required Set<int> recheckedProductIds,
    required List<List<double>> signaturePoints,
  }) {
    final lines = draft.lines.map((line) {
      if (!line.isFilled) {
        throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
      }
      final quantity = line.stockUnit == StockUnit.piece
          ? line.wholePackages!
          : line.wholePackages! * line.packageSize + line.extraAmount!;
      return {
        'product_key': productKey(
          name: line.productName,
          unit: line.stockUnit,
          packageSize: line.packageSize,
        ),
        'quantity_base': quantity,
        'comment': comments[line.productId]?.trim(),
        'metadata': {
          'rechecked': recheckedProductIds.contains(line.productId),
        },
      };
    }).toList(growable: false);

    return {
      'action': 'stocktake',
      'employee': draft.employeeName,
      'started_at': draft.startedAt.toUtc().toIso8601String(),
      'active_seconds': activeSeconds < 0 ? 0 : activeSeconds,
      'metadata': {
        'employee_confirmed': true,
        'signature_points': signaturePoints,
        'completed_positions': draft.totalCount,
      },
      'lines': lines,
    };
  }

  static Map<String, dynamic> draftDelete(String employee, {DateTime? startedAt}) => {
        'action': 'draft_delete',
        'employee': employee,
        if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
      };

  static Map<String, dynamic> draftSync(StocktakeDraft draft) => {
        'action': 'draft_sync',
        'employee': draft.employeeName,
        'status': draft.status.dbValue,
        'started_at': draft.startedAt.toUtc().toIso8601String(),
        'active_seconds': draft.activeSeconds,
        'filled_count': draft.filledCount,
        'total_count': draft.totalCount,
        'payload': {
          'last_product_id': draft.lastProductId,
          'lines': draft.lines
              .map((line) => {
                    'product_name': line.productName,
                    'category_name': line.categoryName,
                    'package_size': line.packageSize,
                    'stock_unit': line.stockUnit.dbValue,
                    'before_total': line.beforeTotal,
                    'before_initialized': line.beforeInitialized,
                    'sort_order': line.sortOrder,
                    'whole_packages': line.wholePackages,
                    'extra_amount': line.extraAmount,
                  })
              .toList(growable: false),
        },
      };
}
