import 'dart:convert';

import 'package:http/http.dart' as http;

import '../purchase_models.dart';
import 'remote_stock_service.dart';

const _purchaseRestBase = 'https://mvnxfouyoynqyjdpcblh.supabase.co/rest/v1';

extension RemotePurchaseV15Extension on RemoteStockService {
  Future<List<StockPurchaseRequest>> fetchPurchaseRequestsV15() async {
    final requestUri = Uri.parse(
      '$_purchaseRestBase/stock_purchase_requests?select=id,supplier_id,status,created_by,comment,created_at,updated_at&order=created_at.desc&limit=200',
    );
    final lineUri = Uri.parse(
      '$_purchaseRestBase/stock_purchase_request_lines?select=id,request_id,product_key,suggested_quantity,requested_quantity,received_quantity,unit_cost,comment&order=id.asc',
    );
    final responses = await Future.wait([
      http.get(requestUri, headers: readHeaders).timeout(const Duration(seconds: 15)),
      http.get(lineUri, headers: readHeaders).timeout(const Duration(seconds: 15)),
    ]);
    for (final response in responses) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Не удалось загрузить заявки на закупку: HTTP ${response.statusCode}');
      }
    }
    final requestJson = jsonDecode(responses[0].body);
    final lineJson = jsonDecode(responses[1].body);
    final linesByRequest = <String, List<Map<String, dynamic>>>{};
    if (lineJson is List) {
      for (final raw in lineJson.whereType<Map>()) {
        final map = raw.map((key, value) => MapEntry('$key', value));
        final requestId = '${map['request_id'] ?? ''}';
        if (requestId.isNotEmpty) linesByRequest.putIfAbsent(requestId, () => <Map<String, dynamic>>[]).add(map);
      }
    }
    if (requestJson is! List) return const [];
    return requestJson.whereType<Map>().map((raw) {
      final map = raw.map((key, value) => MapEntry('$key', value));
      final id = '${map['id'] ?? ''}';
      map['lines'] = linesByRequest[id] ?? const <Map<String, dynamic>>[];
      return StockPurchaseRequest.fromJson(map);
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> createPurchaseRequestV15({
    required String pin,
    required String employee,
    required List<PurchaseRequestDraftLine> lines,
    String? supplierId,
    String? comment,
  }) {
    return post(pin, {
      'action': 'purchase_request_create',
      'employee': employee,
      'supplier_id': supplierId,
      'comment': comment,
      'lines': lines
          .map((line) => {
                'product_key': line.productKey,
                'suggested_quantity': line.suggestedQuantity,
                'requested_quantity': line.requestedQuantity,
                'unit_cost': line.unitCost,
                'comment': line.comment,
              })
          .toList(growable: false),
    });
  }
}
