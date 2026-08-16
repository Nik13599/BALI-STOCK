import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class RemoteStockService {
  static const _endpoint = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-api';
  static const _publishableKey = 'sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29';

  String productKey({required String name, required StockUnit unit, required int packageSize}) =>
      '${name.trim().toLowerCase()}|${unit.dbValue}|$packageSize';

  Future<Map<String, dynamic>> fetchSnapshot() async {
    final response = await http.get(Uri.parse('$_endpoint?action=snapshot'), headers: _readHeaders).timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  Future<int> fetchVersion() async {
    final response = await http.get(Uri.parse('$_endpoint?action=version'), headers: _readHeaders).timeout(const Duration(seconds: 8));
    final data = _decode(response);
    final value = data['version'];
    return value is int ? value : int.tryParse('$value') ?? 0;
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
              'active': product.active,
              'initialized': product.stockInitialized,
              'quantity_base': product.stockInitialized ? product.totalAmount : null,
            })
        .toList(growable: false);
    return _post(pin, {'action': 'bootstrap', 'items': items});
  }

  Future<Map<String, dynamic>> receiveDelivery({
    required String pin,
    required List<DeliveryDraftLine> lines,
    String employee = '',
  }) async {
    final payload = lines
        .map((line) => {
              'product_key': productKey(name: line.product.name, unit: line.product.stockUnit, packageSize: line.product.packageSize),
              'quantity_base': line.addedMl,
            })
        .toList(growable: false);
    return _post(pin, {'action': 'delivery', 'employee': employee, 'lines': payload});
  }

  Future<Map<String, dynamic>> completeStocktake({
    required String pin,
    required StocktakeDraft draft,
    required int activeSeconds,
  }) async {
    final lines = draft.lines.map((line) {
      if (!line.isFilled) throw StateError('Переучёт нельзя завершить: заполнены не все позиции');
      final quantity = line.stockUnit == StockUnit.piece
          ? line.wholePackages!
          : line.wholePackages! * line.packageSize + line.extraAmount!;
      return {
        'product_key': productKey(name: line.productName, unit: line.stockUnit, packageSize: line.packageSize),
        'quantity_base': quantity,
      };
    }).toList(growable: false);
    return _post(pin, {
      'action': 'stocktake',
      'employee': draft.employeeName,
      'started_at': draft.startedAt.toUtc().toIso8601String(),
      'active_seconds': activeSeconds < 0 ? 0 : activeSeconds,
      'lines': lines,
    });
  }

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
    await _post(pin, {
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
    await _post(pin, {'action': 'draft_delete', 'employee': employee});
  }

  Future<Map<String, dynamic>> _post(String pin, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {..._readHeaders, 'Content-Type': 'application/json', 'x-bali-stock-pin': pin},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Map<String, String> get _readHeaders => const {
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
