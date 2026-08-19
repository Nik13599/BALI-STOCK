import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/remote_stock_service.dart';

class CatalogEditorServiceV16 {
  CatalogEditorServiceV16({RemoteStockService? remote}) : _remote = remote ?? RemoteStockService();

  static const endpoint = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-catalog-api';

  final RemoteStockService _remote;

  Future<Map<String, dynamic>> saveBatch({
    required String employee,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw ArgumentError('Не выбраны изменения каталога');
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {..._remote.readHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'catalog_product_batch',
            'employee': employee.trim(),
            'items': items,
          }),
        )
        .timeout(const Duration(seconds: 45));

    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError((data['error'] ?? 'Не удалось сохранить каталог (${response.statusCode})').toString());
    }
    return data;
  }
}
