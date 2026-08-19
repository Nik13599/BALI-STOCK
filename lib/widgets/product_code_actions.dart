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

Future<String?> scanProductCode(BuildContext context) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProductCodeScannerScreen()),
    );
  }

  final field = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Сканировать код товара'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Отсканируйте код USB/Bluetooth-сканером. Поле уже в фокусе; большинство сканеров отправляют Enter автоматически.'),
            const SizedBox(height: 14),
            TextField(
              controller: field,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Код товара', hintText: 'Сканируйте штрихкод / QR-код'),
              onSubmitted: (value) {
                final code = value.trim();
                if (code.isNotEmpty) Navigator.of(dialogContext).pop(code);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final code = field.text.trim();
            if (code.isNotEmpty) Navigator.of(dialogContext).pop(code);
          },
          child: const Text('Найти'),
        ),
      ],
    ),
  );
  field.dispose();
  return result;
}

Future<String?> enterProductCode(BuildContext context) async {
  final field = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Введите код товара'),
      content: TextField(
        controller: field,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Код товара', hintText: 'Например: 4601234567890'),
        onSubmitted: (value) {
          final code = value.trim();
          if (code.isNotEmpty) Navigator.of(dialogContext).pop(code);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final code = field.text.trim();
            if (code.isNotEmpty) Navigator.of(dialogContext).pop(code);
          },
          child: const Text('Найти'),
        ),
      ],
    ),
  );
  field.dispose();
  return result;
}
