import 'dart:io';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../screens/product_code_scanner_screen.dart';

enum _UnknownProductCodeAction { assign, manual }

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

Future<Product?> resolveProductCode(
  BuildContext context, {
  required WarehouseController controller,
  required String rawCode,
}) async {
  final code = rawCode.trim();
  if (code.isEmpty) return null;
  final known = findProductByCode(controller.products, code);
  if (known != null) return known;

  final action = await showDialog<_UnknownProductCodeAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Код не найден'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText('Код «$code» не привязан ни к одному товару.'),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_UnknownProductCodeAction.assign),
              child: const Text('Назначить код товару'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(_UnknownProductCodeAction.manual),
              child: const Text('Найти товар вручную'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return null;

  final selected = await _chooseProduct(
    context,
    controller.products,
    title: action == _UnknownProductCodeAction.assign
        ? 'Выберите товар для назначения кода'
        : 'Найдите товар вручную',
  );
  if (!context.mounted || selected == null) return null;
  if (action == _UnknownProductCodeAction.manual) return selected;

  try {
    await controller.updateProductControl(
      product: selected,
      employee: 'Сканирование штрих-кода',
      minimumAmount: selected.minimumAmount,
      targetAmount: selected.targetAmount,
      varianceRecheckAmount: selected.varianceRecheckAmount,
      barcode: code,
    );
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Код назначен товару «${selected.name}».')),
    );
    for (final product in controller.products) {
      if (product.id == selected.id) return product;
    }
    return selected.copyWith(barcode: code);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось назначить код: $error')),
      );
    }
    return null;
  }
}

Future<Product?> _chooseProduct(
  BuildContext context,
  Iterable<Product> products, {
  required String title,
}) async {
  final all = products.toList(growable: false);
  final search = TextEditingController();
  var query = '';
  final selected = await showDialog<Product>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final normalized = query.trim().toLowerCase();
        final visible = all
            .where((product) => normalized.isEmpty ||
                '${product.name} ${product.categoryName} ${product.barcode ?? ''}'.toLowerCase().contains(normalized))
            .take(80)
            .toList(growable: false);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 620,
            height: 430,
            child: Column(
              children: [
                TextField(
                  controller: search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Поиск товара',
                    hintText: 'Название, категория или код',
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('Товары не найдены'))
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = visible[index];
                            return ListTile(
                              title: Text(product.name),
                              subtitle: Text(product.categoryName),
                              onTap: () => Navigator.of(dialogContext).pop(product),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
          ],
        );
      },
    ),
  );
  search.dispose();
  return selected;
}

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
