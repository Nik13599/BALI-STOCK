import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_stock_service.dart';

extension RemoteStockQueuedSync on RemoteStockService {
  static const syncEndpoint = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-sync-api';

  Future<Map<String, dynamic>> postQueued(String pin, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse(syncEndpoint),
          headers: {
            ...readHeaders,
            'Content-Type': 'application/json',
            'x-bali-stock-pin': pin,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));

    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('${data['error'] ?? 'Ошибка синхронизации'}');
    }
    return data;
  }
}
