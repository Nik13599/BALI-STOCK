import 'package:flutter/material.dart';

import '../models.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

class BulkProductEditV14Screen extends StatefulWidget {
  const BulkProductEditV14Screen({super.key, required this.controller});
  final V14WarehouseController controller;

  @override
  State<BulkProductEditV14Screen> createState() => _BulkProductEditV14ScreenState();
}

class _BulkProductEditV14ScreenState extends State<BulkProductEditV14Screen> {
  final Map<int, ProductV14Meta> drafts = {};
  String query = '';
  String? category;
  bool authorized = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authorize());
  }

  Future<void> _authorize() async {
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    try {
      await widget.controller.setOperationSessionPin(pin);
      if (mounted) setState(() => authorized = true);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
      Navigator.of(context).pop();
    }
  }

  ProductV14Meta _meta(Product p) => drafts[p.id] ?? widget.controller.metaFor(p);

  void _set(Product p, ProductV14Meta value) {
    final original = widget.controller.metaFor(p);
    if (_sameMeta(original, value)) {
      drafts.remove(p.id);
    } else {
      drafts[p.id] = value;
    }
    setState(() {});
  }

  List<Product> _products() {
    final q = query.trim().toLowerCase();
    return widget.controller.products.where((p) {
      if (category != null && p.categoryName != category) return false;
      if (q.isNotEmpty && !'${p.name} ${p.barcode ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList(growable: false);
  }

  Future<void> _confirm() async {
    if (drafts.isEmpty || saving) return;
    final employee = await showTextValueDialog(context, 'Кто подтверждает изменения?', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;

    final changes = <Product, ProductV14Meta>{};
    for (final product in widget.controller.products) {
      final meta = drafts[product.id];
      if (meta != null) changes[product] = meta;
    }
    setState(() => saving = true);
    try {
      await widget.controller.saveProductSalesBatch(employee: employee.trim(), changes: changes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сохранено изменений: ${changes.length} товаров')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Массовое редактирование'),
        actions: [
          if (drafts.isNotEmpty)
            TextButton(
              onPressed: saving ? null : () => setState(drafts.clear),
              child: const Text('Отменить все'),
            ),
        ],
      ),
      body: !authorized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    children: [
                      const InfoBanner(
                        icon: Icons.edit_note,
                        text: 'Изменения копятся как черновик. На сервер отправляется один пакет только после «Подтвердить изменения».',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск товара'),
                              onChanged: (value) => setState(() => query = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String?>(
                              initialValue: category,
                              decoration: const InputDecoration(labelText: 'Категория'),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Все категории')),
                                ...widget.controller.categories.map((x) => DropdownMenuItem<String?>(value: x.name, child: Text(x.name))),
                              ],
                              onChanged: (value) => setState(() => category = value),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: products.length,
                    itemBuilder: (_, i) => _BulkRow(
                      product: products[i],
                      meta: _meta(products[i]),
                      changed: drafts.containsKey(products[i].id),
                      onChanged: (value) => _set(products[i], value),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Изменено: ${drafts.length} товаров',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(),
              child: const Text('ОТМЕНИТЬ'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: drafts.isEmpty || saving ? null : _confirm,
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('ПОДТВЕРДИТЬ ИЗМЕНЕНИЯ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkRow extends StatelessWidget {
  const _BulkRow({required this.product, required this.meta, required this.changed, required this.onChanged});
  final Product product;
  final ProductV14Meta meta;
  final bool changed;
  final ValueChanged<ProductV14Meta> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                          if (changed) ...[
                            const SizedBox(width: 8),
                            const Chip(label: Text('ИЗМЕНЕНО')),
                          ],
                        ],
                      ),
                      Text('${product.categoryName} • ${formatPackageSize(product.packageSize, product.stockUnit)}'),
                      Text('Закупка: ${formatMoney(product.defaultCost)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final value = await showDialog<ProductV14Meta>(
                      context: context,
                      builder: (_) => _QuickMetaDialog(product: product, initial: meta),
                    );
                    if (value != null) onChanged(value);
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Настроить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: meta.sellByBottle,
                    onChanged: (v) => onChanged(meta.copyWith(sellByBottle: v)),
                    title: const Text('Бутылкой'),
                    subtitle: Text(meta.bottleSalePrice == null ? 'Цена не задана' : formatMoney(meta.bottleSalePrice)),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: meta.portionSale,
                    onChanged: (v) => onChanged(meta.copyWith(portionSale: v)),
                    title: const Text('Порционно'),
                    subtitle: Text(meta.portions.isEmpty ? 'Порции не заданы' : meta.portions.map((x) => '${x.amount}/${x.price.toStringAsFixed(2)}').join(' • ')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickMetaDialog extends StatefulWidget {
  const _QuickMetaDialog({required this.product, required this.initial});
  final Product product;
  final ProductV14Meta initial;

  @override
  State<_QuickMetaDialog> createState() => _QuickMetaDialogState();
}

class _QuickMetaDialogState extends State<_QuickMetaDialog> {
  late bool bottle;
  late bool portion;
  late final TextEditingController bottlePrice;
  late List<_PortionRow> portions;

  @override
  void initState() {
    super.initState();
    bottle = widget.initial.sellByBottle;
    portion = widget.initial.portionSale;
    bottlePrice = TextEditingController(text: widget.initial.bottleSalePrice?.toString().replaceAll('.', ',') ?? '');
    portions = widget.initial.portions.map((x) => _PortionRow('${x.amount}', '${x.price}'.replaceAll('.', ','))).toList();
  }

  @override
  void dispose() {
    bottlePrice.dispose();
    for (final row in portions) {
      row.dispose();
    }
    super.dispose();
  }

  double? _double(String value) => double.tryParse(value.replaceAll(',', '.').trim());

  void _save() {
    final price = _double(bottlePrice.text);
    if (bottle && (price == null || price < 0)) {
      showErrorSnack(context, 'Укажите цену бутылки');
      return;
    }
    final parsed = <PortionPrice>[];
    for (final row in portions) {
      final amount = int.tryParse(row.amount.text.trim());
      final p = _double(row.price.text);
      if (amount == null || amount <= 0 || p == null || p < 0) {
        showErrorSnack(context, 'Проверьте порции');
        return;
      }
      parsed.add(PortionPrice(amount: amount, price: p));
    }
    if (portion && parsed.isEmpty) {
      showErrorSnack(context, 'Добавьте хотя бы одну порцию');
      return;
    }
    Navigator.of(context).pop(widget.initial.copyWith(
          sellByBottle: bottle,
          bottleSalePrice: price,
          clearBottleSalePrice: !bottle && price == null,
          portionSale: portion,
          portions: parsed,
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product.name),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(value: bottle, onChanged: (v) => setState(() => bottle = v), title: const Text('Продажа бутылкой')),
                TextField(controller: bottlePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена бутылки, BYN')),
                SwitchListTile(value: portion, onChanged: (v) => setState(() => portion = v), title: const Text('Порционная продажа')),
                for (var i = 0; i < portions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: TextField(controller: portions[i].amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Объём, ${widget.product.stockUnit.symbol}'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: portions[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена, BYN'))),
                        IconButton(
                          onPressed: () => setState(() {
                            final row = portions.removeAt(i);
                            row.dispose();
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(onPressed: () => setState(() => portions.add(_PortionRow('40', ''))), icon: const Icon(Icons.add), label: const Text('Добавить порцию')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: _save, child: const Text('Применить в черновик')),
        ],
      );
}

class _PortionRow {
  _PortionRow(String amount, String price)
      : amount = TextEditingController(text: amount),
        price = TextEditingController(text: price);
  final TextEditingController amount;
  final TextEditingController price;
  void dispose() {
    amount.dispose();
    price.dispose();
  }
}

bool _sameMeta(ProductV14Meta a, ProductV14Meta b) {
  if (a.sellByBottle != b.sellByBottle ||
      a.bottleSalePrice != b.bottleSalePrice ||
      a.portionSale != b.portionSale ||
      a.imagePath != b.imagePath ||
      a.portions.length != b.portions.length) {
    return false;
  }
  for (var i = 0; i < a.portions.length; i++) {
    if (a.portions[i].amount != b.portions[i].amount || a.portions[i].price != b.portions[i].price) return false;
  }
  return true;
}
