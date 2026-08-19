import '../purchase_models.dart';
import 'remote_stock_service.dart';

extension RemotePurchaseV15Extension on RemoteStockService {
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
