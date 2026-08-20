import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/product_code_scanner_screen.dart';

Product? findProductByCode(Iterable<Product> products, String rawValue) {
  final wanted = rawValue.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final product in products) {
    final code = (product.barcode ?? '').trim().toLowerCase();
    if (code.isNotEmpty && code == wanted) return product;
  }
  return null;
}

String get productCodeScanActionLabel =>
    Platform.isAndroid || Platform.isIOS ? 'Сканировать камерой' : 'Сканировать сканером';

Future<String?> scanProductCode(BuildContext context) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProductCodeScannerScreen()),
    );
  }
  return _showCodeDialog(
    context,
    title: 'Сканировать код товара',
    helper: 'Отсканируйте код USB/Bluetooth-сканером. Поле уже в фокусе; большинство сканеров отправляют Enter автоматически.',
    hint: 'Сканируйте штрихкод / QR-код',
  );
}

Future<String?> enterProductCode(BuildContext context) => _showCodeDialog(
      context,
      title: 'Введите код товара',
      hint: 'Например: 4601234567890',
    );

Future<String?> _showCodeDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String? helper,
}) async {
  final field = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (helper != null) ...[
              Text(helper),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: field,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Код товара', hintText: hint),
              onSubmitted: (value) => _closeWithCode(dialogContext, value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: () => _closeWithCode(dialogContext, field.text), child: const Text('Найти')),
      ],
    ),
  );
  field.dispose();
  return result;
}

void _closeWithCode(BuildContext context, String value) {
  final code = value.trim();
  if (code.isNotEmpty) Navigator.of(context).pop(code);
}
