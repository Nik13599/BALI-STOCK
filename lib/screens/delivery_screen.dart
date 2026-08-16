import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final Map<int, DeliveryDraftLine> _lines = {};
  bool _saving = false;

  Future<void> _addLine() async {
    final line = await showDeliveryLineDialog(context, widget.controller.products);
    if (line == null) return;
    setState(() => _lines[line.product.id] = line);
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.controller.receiveDelivery(_lines.values.toList(growable: false));
      if (!mounted) return;
      setState(_lines.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Поставка принята. Остатки склада обновлены.')));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Принять поставку')),
        body: widget.controller.products.isEmpty
            ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Нет складских позиций', message: 'Сначала добавьте позиции в разделе «Склад».')
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const InfoBanner(
                    icon: Icons.lock_outline,
                    text: 'Доступ к приёмке подтверждается паролем. После проведения поставки количество автоматически прибавляется к текущему складу.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text('Позиции поставки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      FilledButton.icon(onPressed: _saving ? null : _addLine, icon: const Icon(Icons.add), label: const Text('Добавить позицию')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_lines.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
                      child: const Text('Добавьте товары, которые фактически пришли в этой поставке.', textAlign: TextAlign.center),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < _lines.values.length; i++) ...[
                            Builder(
                              builder: (context) {
                                final line = _lines.values.elementAt(i);
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${line.product.categoryName} • бутылка ${formatBottleVolume(line.product.bottleMl)}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('+${line.bottles} бут. + ${line.extraMl} мл', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                      IconButton(onPressed: _saving ? null : () => setState(() => _lines.remove(line.product.id)), icon: const Icon(Icons.delete_outline)),
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (i != _lines.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _lines.isEmpty || _saving ? null : _submit,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ПРОВЕСТИ ПОСТАВКУ')),
                  ),
                ],
              ),
      ),
    );
  }
}

Future<DeliveryDraftLine?> showDeliveryLineDialog(BuildContext context, List<Product> products) async {
  if (products.isEmpty) return null;
  var productId = products.first.id;
  final bottles = TextEditingController(text: '0');
  final extra = TextEditingController(text: '0');
  final key = GlobalKey<FormState>();

  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        return AlertDialog(
          title: const Text('Позиция поставки'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Позиция'),
                    items: products
                        .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name} (${formatBottleVolume(p.bottleMl)})')))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => productId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TwoFields(
                    first: IntegerField(controller: bottles, label: 'Бутылок принято', min: 0),
                    second: IntegerField(
                      controller: extra,
                      label: 'Доп. объём, мл',
                      min: 0,
                      validator: (value) {
                        final base = integerValidator(value, min: 0);
                        if (base != null) return base;
                        final parsed = int.tryParse(value ?? '');
                        if (parsed != null && parsed >= product.bottleMl) return 'Меньше ${product.bottleMl} мл';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (!(key.currentState?.validate() ?? false)) return;
                final bottleCount = int.parse(bottles.text);
                final extraMl = int.parse(extra.text);
                if (bottleCount == 0 && extraMl == 0) {
                  showErrorSnack(dialogContext, 'Количество поставки не может быть нулевым');
                  return;
                }
                Navigator.of(dialogContext).pop(DeliveryDraftLine(product: product, bottles: bottleCount, extraMl: extraMl));
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    ),
  );
  bottles.dispose();
  extra.dispose();
  return result;
}
