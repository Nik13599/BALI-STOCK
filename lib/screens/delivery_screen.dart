import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';

String _productUnitLabel(Product product) => switch (product.stockUnit) {
      StockUnit.ml => 'бутылка ${formatPackageSize(product.packageSize, product.stockUnit)}',
      StockUnit.gram => 'упаковка ${formatPackageSize(product.packageSize, product.stockUnit)}',
      StockUnit.piece => 'штучный учёт',
    };

Future<DeliveryDraftLine?> showDeliveryLineDialog(
  BuildContext context,
  List<Product> products, {
  DeliveryDraftLine? initial,
  Product? preselectedProduct,
  bool scanWorkflow = false,
}) async {
  if (products.isEmpty) return null;
  var productId = initial?.product.id ?? preselectedProduct?.id ?? products.first.id;
  final whole = TextEditingController(text: '${initial?.bottles ?? 0}');
  final extra = TextEditingController(text: '${initial?.extraMl ?? 0}');
  final cost = TextEditingController(text: initial?.unitCost?.toStringAsFixed(2) ?? '');
  final key = GlobalKey<FormState>();

  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    barrierDismissible: !scanWorkflow,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        final wholeLabel = switch (product.stockUnit) {
          StockUnit.ml => 'Бутылок принято',
          StockUnit.gram => 'Упаковок принято',
          StockUnit.piece => 'Количество, шт.',
        };
        final extraLabel = product.stockUnit == StockUnit.ml ? 'Доп. объём, мл' : 'Доп. остаток, г';
        final productLocked = initial != null || preselectedProduct != null;
        return AlertDialog(
          title: Row(children: [
            const BaliNavIcon(kind: BaliNavIconKind.delivery, active: true, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(initial == null ? 'Позиция поставки' : 'Проверить позицию поставки')),
          ]),
          content: SizedBox(
            width: 580,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<int>(
                    initialValue: productId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Позиция',
                      helperText: productLocked ? 'Товар зафиксирован выбранным или отсканированным кодом.' : null,
                    ),
                    items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name} (${_productUnitLabel(p)})'))).toList(growable: false),
                    onChanged: productLocked
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              productId = value;
                              whole.text = '0';
                              extra.text = '0';
                              cost.text = '';
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  if (product.stockUnit == StockUnit.piece)
                    IntegerField(controller: whole, label: wholeLabel, min: 0)
                  else
                    TwoFields(
                      first: IntegerField(controller: whole, label: wholeLabel, min: 0),
                      second: IntegerField(
                        controller: extra,
                        label: extraLabel,
                        min: 0,
                        validator: (value) {
                          final base = integerValidator(value, min: 0);
                          if (base != null) return base;
                          final parsed = int.tryParse(value ?? '');
                          if (parsed != null && parsed >= product.packageSize) return 'Меньше ${product.packageSize} ${product.stockUnit.symbol}';
                          return null;
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Закупочная цена за упаковку / единицу, ${product.costCurrency} *'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Закупочная цена обязательна';
                      final parsed = double.tryParse(value.replaceAll(',', '.'));
                      return parsed == null || parsed < 0 ? 'Некорректная цена' : null;
                    },
                  ),
                  if (initial?.sourceText != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('OCR: ${initial!.sourceText}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                  if (scanWorkflow) ...[
                    const SizedBox(height: 10),
                    const InfoBanner(icon: Icons.qr_code_scanner, text: 'Сохраните данные — затем откроется следующий скан.'),
                  ],
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton.icon(
              onPressed: () {
                if (!(key.currentState?.validate() ?? false)) return;
                final wholeCount = int.parse(whole.text);
                final extraAmount = product.stockUnit == StockUnit.piece ? 0 : int.parse(extra.text);
                if (wholeCount == 0 && extraAmount == 0) {
                  showErrorSnack(dialogContext, 'Количество поставки не может быть нулевым');
                  return;
                }
                Navigator.pop(dialogContext, DeliveryDraftLine(
                  product: product,
                  bottles: wholeCount,
                  extraMl: extraAmount,
                  unitCost: double.parse(cost.text.replaceAll(',', '.')),
                  sourceText: initial?.sourceText,
                  confidence: initial?.confidence,
                  manuallyCorrected: initial != null,
                ));
              },
              icon: scanWorkflow ? const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 19) : const Icon(Icons.check_circle_outline),
              label: Text(scanWorkflow ? 'Сохранить → следующий скан' : (initial == null ? 'Добавить' : 'Подтвердить')),
            ),
          ],
        );
      },
    ),
  );
  whole.dispose();
  extra.dispose();
  cost.dispose();
  return result;
}
