import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';

class RemoteStockService {
  static const endpoint = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-client-api';
  static const _publishableKey = 'sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29';

  String productKey({required String name, required StockUnit unit, required int packageSize}) =>
      '${name.trim().toLowerCase()}|${unit.dbValue}|$packageSize';

  Future<Map<String, dynamic>> fetchSnapshot() async {
    final response = await http.get(Uri.parse('$endpoint?action=snapshot'), headers: readHeaders).timeout(const Duration(seconds: 18));
    return _decode(response);
  }

  Future<int> fetchVersion() async {
    final response = await http.get(Uri.parse('$endpoint?action=version'), headers: readHeaders).timeout(const Duration(seconds: 10));
    final data = _decode(response);
    final value = data['version'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  Future<Map<String, dynamic>> fetchPurchaseSuggestions() async {
    final response = await http.get(Uri.parse('$endpoint?action=purchase_suggestions'), headers: readHeaders).timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchAnalytics({int days = 30}) async {
    final response = await http.get(Uri.parse('$endpoint?action=analytics&days=$days'), headers: readHeaders).timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  Future<void> authorize(String _) async {
    // The production client API authenticates every request with the embedded
    // Supabase publishable app key. A separate authorize round-trip only adds
    // latency and carries no additional authorization state.
  }

  Future<Map<String, dynamic>> syncCatalog({
    required String pin,
    required List<Category> categories,
    required List<Product> products,
  }) async {
    final order = {for (final category in categories) category.name: category.sortOrder};
    final items = products
        .map((product) => {
              'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
              'name': product.name,
              'category_name': product.categoryName,
              'category_sort': order[product.categoryName] ?? 0,
              'package_size': product.packageSize,
              'stock_unit': product.stockUnit.dbValue,
              'minimum_amount': product.minimumAmount,
              'target_amount': product.targetAmount,
              'barcode': product.barcode,
              'default_cost': product.defaultCost,
              'cost_currency': product.costCurrency,
              'variance_recheck_amount': product.varianceRecheckAmount,
              'active': product.active,
              'initialized': product.stockInitialized,
              'quantity_base': product.stockInitialized ? product.totalAmount : null,
            })
        .toList(growable: false);
    return post(pin, {'action': 'bootstrap', 'items': items});
  }

  Future<Map<String, dynamic>> receiveDelivery({
    required String pin,
    required List<DeliveryDraftLine> lines,
    String employee = '',
    String? supplierId,
    String? documentNumber,
    String? comment,
    String? attachmentUrl,
    String? locationId,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = lines
        .map((line) => {
              'product_key': productKey(name: line.product.name, unit: line.product.stockUnit, packageSize: line.product.packageSize),
              'quantity_base': line.addedMl,
              'unit_cost': line.unitCost,
              'currency': line.product.costCurrency,
              'metadata': {
                if (line.sourceText != null) 'ocr_source': line.sourceText,
                if (line.confidence != null) 'ocr_confidence': line.confidence,
                'manually_corrected': line.manuallyCorrected,
              },
            })
        .toList(growable: false);
    return post(pin, {
      'action': 'delivery',
      'employee': employee,
      'supplier_id': supplierId,
      'document_number': documentNumber,
      'comment': comment,
      'attachment_url': attachmentUrl,
      'location_id': locationId,
      'metadata': metadata ?? const {},
      'lines': payload,
    });
  }

  Future<Map<String, dynamic>> writeOff({
    required String pin,
    required String employee,
    required String reason,
    required List<DeliveryDraftLine> lines,
    String? locationId,
    String? comment,
  }) async {
    return post(pin, {
      'action': 'writeoff',
      'employee': employee,
      'reason': reason,
      'location_id': locationId,
      'comment': comment,
      'lines': lines
          .map((line) => {
                'product_key': productKey(name: line.product.name, unit: line.product.stockUnit, packageSize: line.product.packageSize),
                'quantity_base': line.addedMl,
                'comment': line.sourceText,
              })
          .toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> transfer({
    required String pin,
    required String employee,
    required String sourceLocationId,
    required String targetLocationId,
    required List<DeliveryDraftLine> lines,
    String? comment,
  }) async {
    return post(pin, {
      'action': 'transfer',
      'employee': employee,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
      'comment': comment,
      'lines': lines
          .map((line) => {
                'product_key': productKey(name: line.product.name, unit: line.product.stockUnit, packageSize: line.product.packageSize),
                'quantity_base': line.addedMl,
              })
          .toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> correctOperation({
    required String pin,
    required String employee,
    required String originalOperationId,
    required String reason,
    required Map<Product, int> deltas,
    String? locationId,
  }) async {
    return post(pin, {
      'action': 'correction',
      'employee': employee,
      'correction_of': originalOperationId,
      'reason': reason,
      'location_id': locationId,
      'lines': deltas.entries
          .where((entry) => entry.value != 0)
          .map((entry) => {
                'product_key': productKey(name: entry.key.name, unit: entry.key.stockUnit, packageSize: entry.key.packageSize),
                'delta_quantity': entry.value,
              })
          .toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> completeStocktake({
    required String pin,
    required StocktakeDraft draft,
    required int activeSeconds,
    required Map<int, String> comments,
    required Set<int> recheckedProductIds,
    required List<List<double>> signaturePoints,
  }) async {
    final lines = draft.lines.map((line) {
      if (!line.isFilled) throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
      final quantity = line.stockUnit == StockUnit.piece
          ? line.wholePackages!
          : line.wholePackages! * line.packageSize + line.extraAmount!;
      return {
        'product_key': productKey(name: line.productName, unit: line.stockUnit, packageSize: line.packageSize),
        'quantity_base': quantity,
        'comment': comments[line.productId]?.trim(),
        'metadata': {
          'rechecked': recheckedProductIds.contains(line.productId),
        },
      };
    }).toList(growable: false);
    return post(pin, {
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
    });
  }

  Future<Map<String, dynamic>> upsertSupplier({
    required String pin,
    String? id,
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? notes,
  }) =>
      post(pin, {
        'action': 'supplier_upsert',
        'id': id,
        'name': name,
        'contact_person': contactPerson,
        'phone': phone,
        'email': email,
        'notes': notes,
      });

  Future<Map<String, dynamic>> linkProductSupplier({
    required String pin,
    required Product product,
    required String supplierId,
    String? supplierSku,
    double? lastPrice,
    String currency = 'BYN',
    bool isPrimary = false,
  }) =>
      post(pin, {
        'action': 'supplier_link',
        'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
        'supplier_id': supplierId,
        'supplier_sku': supplierSku,
        'last_price': lastPrice,
        'currency': currency,
        'is_primary': isPrimary,
      });

  Future<Map<String, dynamic>> upsertLocation({
    required String pin,
    String? id,
    required String name,
    bool isPrimary = false,
  }) =>
      post(pin, {'action': 'location_upsert', 'id': id, 'name': name, 'is_primary': isPrimary});

  Future<Map<String, dynamic>> updateProductMeta({
    required String pin,
    required Product product,
    required String employee,
    int? minimumAmount,
    int? targetAmount,
    String? barcode,
    double? defaultCost,
    String? costCurrency,
    int? varianceRecheckAmount,
  }) =>
      post(pin, {
        'action': 'product_meta',
        'employee': employee,
        'product_key': productKey(name: product.name, unit: product.stockUnit, packageSize: product.packageSize),
        if (minimumAmount != null) 'minimum_amount': minimumAmount,
        if (targetAmount != null) 'target_amount': targetAmount,
        if (barcode != null) 'barcode': barcode,
        if (defaultCost != null) 'default_cost': defaultCost,
        if (costCurrency != null) 'cost_currency': costCurrency,
        if (varianceRecheckAmount != null) 'variance_recheck_amount': varianceRecheckAmount,
      });

  Future<String> uploadInvoiceAttachment({
    required String pin,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final response = await post(pin, {
      'action': 'invoice_attachment_upload',
      'file_name': fileName,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    });
    return '${response['path'] ?? ''}';
  }

  Future<String> createInvoiceAttachmentUrl({required String pin, required String path}) async {
    final response = await post(pin, {'action': 'invoice_attachment_url', 'path': path});
    return '${response['url'] ?? ''}';
  }

  Future<String> saveInvoiceScan({
    required String pin,
    required String employee,
    String? supplierId,
    String? documentNumber,
    String? attachmentUrl,
    required String rawText,
    required List<DeliveryDraftLine> lines,
  }) async {
    final response = await post(pin, {
      'action': 'invoice_scan_save',
      'employee': employee,
      'supplier_id': supplierId,
      'document_number': documentNumber,
      'attachment_url': attachmentUrl,
      'raw_text': rawText,
      'status': 'reviewed',
      'lines': lines
          .map((line) => {
                'source_text': line.sourceText ?? line.product.name,
                'product_key': productKey(name: line.product.name, unit: line.product.stockUnit, packageSize: line.product.packageSize),
                'recognized_quantity': line.addedMl,
                'recognized_packages': line.bottles,
                'unit_cost': line.unitCost,
                'confidence': line.confidence,
                'manually_corrected': line.manuallyCorrected,
              })
          .toList(growable: false),
    });
    return '${response['id'] ?? ''}';
  }

  Future<Map<String, dynamic>> createPurchaseRequest({
    required String pin,
    required String employee,
    required List<PurchaseSuggestion> items,
    String? supplierId,
    String? comment,
  }) async {
    return post(pin, {
      'action': 'purchase_request_create',
      'employee': employee,
      'supplier_id': supplierId,
      'comment': comment,
      'lines': items
          .map((item) => {
                'product_key': item.productKey,
                'suggested_quantity': item.suggestedQuantity,
                'requested_quantity': item.suggestedQuantity,
                'unit_cost': item.lastPrice,
              })
          .toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> setPurchaseRequestStatus({
    required String pin,
    required String id,
    required String status,
    String? employee,
  }) =>
      post(pin, {'action': 'purchase_request_status', 'id': id, 'status': status, 'employee': employee});

  Future<void> syncDraft({required String pin, required StocktakeDraft draft}) async {
    final payload = {
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
    };
    await post(pin, {
      'action': 'draft_sync',
      'employee': draft.employeeName,
      'status': draft.status.dbValue,
      'started_at': draft.startedAt.toUtc().toIso8601String(),
      'active_seconds': draft.activeSeconds,
      'filled_count': draft.filledCount,
      'total_count': draft.totalCount,
      'payload': payload,
    });
  }

  Future<void> deleteDraft({required String pin, required String employee}) async {
    await post(pin, {'action': 'draft_delete', 'employee': employee});
  }

  Future<Map<String, dynamic>> post(String _, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {...readHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  Map<String, String> get readHeaders => const {
        'apikey': _publishableKey,
        'Accept': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError((data['error'] ?? 'Ошибка синхронизации (${response.statusCode})').toString());
    }
    return data;
  }
}
