import 'package:flutter/services.dart';

class BaliInvoiceOcr {
  BaliInvoiceOcr._();

  static const MethodChannel _channel = MethodChannel('bali_invoice_ocr');

  static Future<String> recognizeImage({
    required String imagePath,
    String language = 'rus+eng',
    String? tessDataRoot,
  }) async {
    final text = await _channel.invokeMethod<String>('recognizeImage', {
      'imagePath': imagePath,
      'language': language,
      if (tessDataRoot != null) 'tessDataRoot': tessDataRoot,
    });
    return text ?? '';
  }
}
