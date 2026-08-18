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
  final Map<int, ProductV14CatalogEdit> drafts = {};
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

  ProductV14CatalogEdit _original(Product product) => ProductV14CatalogEdit.fromProduct(
        product,
        widget.controller.metaFor(product),
        categorySort: widget.controller.categorySortFor(product),
      );

  ProductV14CatalogEdit _edit(Product product) => drafts[product.id] ?? _original(product);

  void _set(Product product, ProductV14CatalogEdit value) {
    if (value.sameAs(
      product,
      widget.controller.metaFor(product),
      categorySort: widget.controller.categorySortFor(product),
    )) {
      drafts.remove(product.id);
    } else {
      drafts[product.id] = value;
    }
    setState(() {});
  }

  List<Product> _products() {
    final q = query.trim().toLowerCase();
    return widget.controller.products.where((product) {
      final edit = _edit(product);
      if (category != null && edit.categoryName != category) return false;
      if (q.isNotEmpty && !'${edit.name} ${edit.barcode ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList(growable: false);
  }

  Future<void> _confirm() async {
    if (drafts.isEmpty || saving) return;
    final employee = await showTextValueDialog(context, 'Кто подтверждает изменения?', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;

    final changes = <Product, ProductV14CatalogEdit>{};
    for (final product in widget.controller.products) {
      final edit = drafts[product.id];
      if (edit != null) changes[product] = edit;
    }

    setState(() => saving = true);
    try {
      await widget.controller.saveProductCatalogBatch(employee: employee.trim(), changes: changes);
      if (!mounted) return;
      final syncText = widget.controller.sharedOnline ? 'Изменения отправлены в общую базу.' : 'Изменения сохранены локально и ожидают синхронизации.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Изменено: ${changes.length} товаров. $syncText')),
      );
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
                        text: 'Название, категория, объём/упаковка, единица учёта, код, минимум, цель, продажа бутылкой и порции меняются сначала только в черновике. После подтверждения уходит один транзакционный пакет.',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск товара или кода'),
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
                    itemBuilder: (_, i) {
                      final product = products[i];
                      return _BulkRow(
                        product: product,
                        edit: _edit(product),
                        changed: drafts.containsKey(product.id),
                        onChanged: (value) => _set(product, value),
                        controller: widget.controller,
                      );
                    },
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
            TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(), child: const Text('ОТМЕНИТЬ')),
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
  const _BulkRow({
    required this.product,
    required this.edit,
    required this.changed,
    required this.onChanged,
    required this.controller,
  });

  final Product product;
  final ProductV14CatalogEdit edit;
  final bool changed;
  final ValueChanged<ProductV14CatalogEdit> onChanged;
  final V14WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    final meta = edit.meta;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(edit.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                          if (changed) ...[
                            const SizedBox(width: 8),
                            const Chip(label: Text('ИЗМЕНЕНО')),
                          ],
                        ],
                      ),
                      Text('${edit.categoryName} • ${formatPackageSize(edit.packageSize, edit.stockUnit)}'),
                      const SizedBox(height: 2),
                      Text(
                        'Код: ${edit.barcode?.trim().isNotEmpty == true ? edit.barcode : '—'} • минимум ${edit.minimumAmount} ${edit.stockUnit.symbol} • цель ${edit.targetAmount} ${edit.stockUnit.symbol}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text('Последняя закупка: ${formatMoney(product.defaultCost)} — вручную не меняется', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final value = await showDialog<ProductV14CatalogEdit>(
                      context: context,
                      builder: (_) => _CatalogEditDialog(
                        product: product,
                        initial: edit,
                        categories: controller.categories,
                      ),
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
                    onChanged: (value) => onChanged(edit.copyWith(meta: meta.copyWith(sellByBottle: value))),
                    title: const Text('Бутылкой'),
                    subtitle: Text(meta.bottleSalePrice == null ? 'Цена не задана' : formatMoney(meta.bottleSalePrice)),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: meta.portionSale,
                    onChanged: (value) => onChanged(edit.copyWith(meta: meta.copyWith(portionSale: value))),
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

class _CatalogEditDialog extends StatefulWidget {
  const _CatalogEditDialog({required this.product, required this.initial, required this.categories});

  final Product product;
  final ProductV14CatalogEdit initial;
  final List<Category> categories;

  @override
  State<_CatalogEditDialog> createState() => _CatalogEditDialogState();
}

class _CatalogEditDialogState extends State<_CatalogEditDialog> {
  late final TextEditingController name;
  late final TextEditingController packageSize;
  late final TextEditingController barcode;
  late final TextEditingController minimum;
  late final TextEditingController target;
  late final TextEditingController variance;
  late final TextEditingController bottlePrice;
  late String categoryName;
  late StockUnit stockUnit;
  late bool bottle;
  late bool portion;
  late List<_PortionRow> portions;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    name = TextEditingController(text: initial.name);
    packageSize = TextEditingController(text: '${initial.packageSize}');
    barcode = TextEditingController(text: initial.barcode ?? '');
    minimum = TextEditingController(text: '${initial.minimumAmount}');
    target = TextEditingController(text: '${initial.targetAmount}');
    variance = TextEditingController(text: '${initial.varianceRecheckAmount}');
    bottlePrice = TextEditingController(text: initial.meta.bottleSalePrice?.toString().replaceAll('.', ',') ?? '');
    categoryName = initial.categoryName;
    stockUnit = initial.stockUnit;
    bottle = initial.meta.sellByBottle;
    portion = initial.meta.portionSale;
    portions = initial.meta.portions.map((x) => _PortionRow('${x.amount}', '${x.price}'.replaceAll('.', ','))).toList();
  }

  @override
  void dispose() {
    name.dispose();
    packageSize.dispose();
    barcode.dispose();
    minimum.dispose();
    target.dispose();
    variance.dispose();
    bottlePrice.dispose();
    for (final row in portions) {
      row.dispose();
    }
    super.dispose();
  }

  double? _double(String value) => double.tryParse(value.replaceAll(',', '.').trim());

  void _save() {
    final cleanName = name.text.trim();
    var package = int.tryParse(packageSize.text.trim());
    final min = int.tryParse(minimum.text.trim());
    final targetAmount = int.tryParse(target.text.trim());
    final recheck = int.tryParse(variance.text.trim());
    final salePrice = _double(bottlePrice.text);

    if (cleanName.isEmpty || min == null || targetAmount == null || recheck == null || min < 0 || targetAmount < 0 || recheck < 0) {
      showErrorSnack(context, 'Проверьте название, минимум, цель и порог перепроверки');
      return;
    }
    if (stockUnit == StockUnit.piece) package = 1;
    if (package == null || package <= 0) {
      showErrorSnack(context, 'Размер упаковки должен быть больше нуля');
      return;
    }
    if (bottle && (salePrice == null || salePrice < 0)) {
      showErrorSnack(context, 'Укажите цену продажи бутылки');
      return;
    }

    final parsedPortions = <PortionPrice>[];
    for (final row in portions) {
      final amount = int.tryParse(row.amount.text.trim());
      final price = _double(row.price.text);
      if (amount == null || amount <= 0 || price == null || price < 0) {
        showErrorSnack(context, 'Проверьте объём и цену всех порций');
        return;
      }
      parsedPortions.add(PortionPrice(amount: amount, price: price));
    }
    if (portion && parsedPortions.isEmpty) {
      showErrorSnack(context, 'Добавьте хотя бы одну порцию');
      return;
    }

    final selectedCategory = widget.categories.where((x) => x.name == categoryName).firstOrNull;
    final newMeta = widget.initial.meta.copyWith(
      sellByBottle: bottle,
      bottleSalePrice: salePrice,
      clearBottleSalePrice: !bottle && salePrice == null,
      portionSale: portion,
      portions: parsedPortions,
    );
    Navigator.of(context).pop(
      widget.initial.copyWith(
        name: cleanName,
        categoryName: categoryName,
        categorySort: selectedCategory?.sortOrder ?? widget.initial.categorySort,
        packageSize: package,
        stockUnit: stockUnit,
        minimumAmount: min,
        targetAmount: targetAmount,
        varianceRecheckAmount: recheck,
        barcode: barcode.text.trim(),
        clearBarcode: barcode.text.trim().isEmpty,
        meta: newMeta,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Редактировать • ${widget.product.name}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: categoryName,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: widget.categories.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(growable: false),
                onChanged: (value) => setState(() => categoryName = value ?? categoryName),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<StockUnit>(
                      initialValue: stockUnit,
                      decoration: const InputDecoration(labelText: 'Единица учёта'),
                      items: StockUnit.values.map((x) => DropdownMenuItem(value: x, child: Text(x.displayName))).toList(growable: false),
                      onChanged: (value) => setState(() {
                        stockUnit = value ?? stockUnit;
                        if (stockUnit == StockUnit.piece) packageSize.text = '1';
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: packageSize,
                      enabled: stockUnit != StockUnit.piece,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Объём / упаковка, ${stockUnit.symbol}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Штрихкод / код товара')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: minimum, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Минимум, ${stockUnit.symbol}'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: target, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Цель, ${stockUnit.symbol}'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: variance, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Перепроверка, ${stockUnit.symbol}'))),
                ],
              ),
              const SizedBox(height: 10),
              InfoBanner(
                icon: Icons.shopping_cart_checkout_outlined,
                text: 'Последняя закупочная цена: ${formatMoney(widget.product.defaultCost)}. Она приходит только из реальной поставки и здесь не редактируется.',
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: bottle,
                onChanged: (value) => setState(() => bottle = value),
                title: const Text('Продажа бутылкой', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              TextField(controller: bottlePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена бутылки, BYN')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: portion,
                onChanged: (value) => setState(() => portion = value),
                title: const Text('Порционная продажа', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              ...List.generate(portions.length, _portionRow),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => portions.add(_PortionRow('40', ''))),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить порцию'),
                ),
              ),
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

  Widget _portionRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: TextField(controller: portions[i].amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Объём, ${stockUnit.symbol}'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: portions[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена, BYN'))),
            IconButton(
              tooltip: 'Удалить порцию',
              onPressed: () => setState(() {
                final row = portions.removeAt(i);
                row.dispose();
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
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
