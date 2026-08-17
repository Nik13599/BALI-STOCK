import 'dart:convert';

import 'package:http/http.dart' as http;

class InvoiceAttachmentService {
  static const _endpoint = 'https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-invoice-view';
  static const _publishableKey = 'sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29';

  Future<String> createTemporaryUrl(String path) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {'path': path});
    final response = await http.get(uri, headers: const {'apikey': _publishableKey, 'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    final decoded = response.body.isEmpty ? const <String, dynamic>{} : jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('${data['error'] ?? 'Не удалось открыть накладную'}');
    }
    final url = '${data['url'] ?? ''}';
    if (url.isEmpty) throw StateError('Сервер не вернул ссылку на накладную');
    return url;
  }
}
