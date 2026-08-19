import 'package:flutter/material.dart';

import '../models.dart';
import '../services/catalog_editor_service_v16.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
import '../widgets/common.dart';

class BulkProductEditV14Screen extends StatefulWidget {
  const BulkProductEditV14Screen({super.key, required this.controller});

  final V14WarehouseController controller;

  @override
  State<BulkProductEditV14Screen> createState() => _BulkProductEditV14ScreenState();
}

class _BulkProductEditV14ScreenState extends State<BulkProductEditV14Screen> {
  final CatalogEditorServiceV16 _catalog = CatalogEditorServiceV16();
  final Map<int, ProductV14CatalogEdit> drafts = {};
  String query = '';
  String? category;
  bool saving = false;
  bool adding = false;
  int? deletingProductId;

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
    final order = {for (final item in widget.controller.categories) item.name: item.sortOrder};
    final result = widget.controller.products.where((product) {
      final edit = _edit(product);
      if (!product.active) return false;
      if (category != null && edit.categoryName != category) return false;
      if (q.isNotEmpty && !'${edit.name} ${edit.categoryName} ${edit.barcode ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList(growable: true);
    result.sort((a, b) {
      final ea = _edit(a);
      final eb = _edit(b);
      final oa = order[ea.categoryName] ?? ea.categorySort;
      final ob = order[eb.categoryName] ?? eb.categorySort;
      if (oa != ob) return oa.compareTo(ob);
      final byCategory = ea.categoryName.toLowerCase().compareTo(eb.categoryName.toLowerCase());
      if (byCategory != 0) return byCategory;
      return ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
    });
    return result;
  }

  Map<String, dynamic> _newProductPayload(ProductV14CatalogEdit edit) => {
        'old_product_key': null,
        'name': edit.name.trim(),
        'category_name': edit.categoryName.trim(),
        'category_sort': edit.categorySort,
        'package_size': edit.packageSize,
        'stock_unit': edit.stockUnit.dbValue,
        'minimum_amount': edit.minimumAmount,
        'target_amount': edit.targetAmount,
        'barcode': edit.barcode?.trim().isEmpty == true ? null : edit.barcode?.trim(),
        'variance_recheck_amount': edit.varianceRecheckAmount,
        'active': true,
        'sell_by_bottle': edit.meta.sellByBottle,
        'bottle_sale_price': edit.meta.bottleSalePrice,
        'portion_sale': edit.meta.portionSale,
        'portion_prices': edit.meta.portions.map((x) => x.toJson()).toList(growable: false),
        'image_path': edit.meta.imagePath,
      };

  Future<String?> _employee(String title) async {
    final value = await showTextValueDialog(context, title, 'ФИО сотрудника');
    if (!mounted || value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _confirm() async {
    if (drafts.isEmpty || saving) return;
    if (!widget.controller.sharedOnline) {
      showErrorSnack(context, 'Редактирование каталога без пароля требует подключения к общей базе.');
      return;
    }
    final employee = await _employee('Кто подтверждает изменения?');
    if (!mounted || employee == null) return;

    final changes = <Product, ProductV14CatalogEdit>{};
    for (final product in widget.controller.products) {
      final edit = drafts[product.id];
      if (edit != null) changes[product] = edit;
    }

    setState(() => saving = true);
    try {
      await _catalog.saveBatch(
        employee: employee,
        items: changes.entries
            .map((entry) => entry.value.toPayload(product: entry.key, oldProductKey: widget.controller.productKeyFor(entry.key)))
            .toList(growable: false),
      );
      await widget.controller.refresh();
      drafts.clear();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено изменений: ${changes.length}. Пароль не требовался; ФИО записано в аудит.')),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _addProduct() async {
    if (adding) return;
    if (!widget.controller.sharedOnline) {
      showErrorSnack(context, 'Добавление нового товара требует подключения к общей базе.');
      return;
    }
    final categories = widget.controller.categories.toList(growable: true)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (categories.isEmpty) {
      showErrorSnack(context, 'Сначала должна существовать хотя бы одна категория.');
      return;
    }
    final first = categories.first;
    final initial = ProductV14CatalogEdit(
      name: '',
      categoryName: first.name,
      categorySort: first.sortOrder,
      packageSize: 750,
      stockUnit: StockUnit.ml,
      minimumAmount: 0,
      targetAmount: 0,
      varianceRecheckAmount: 0,
      meta: const ProductV14Meta(),
    );
    final edit = await showDialog<ProductV14CatalogEdit>(
      context: context,
      builder: (_) => _CatalogEditDialog(
        initial: initial,
        categories: categories,
      ),
    );
    if (!mounted || edit == null) return;

    final duplicate = widget.controller.products.any((p) =>
        p.active &&
        p.name.trim().toLowerCase() == edit.name.trim().toLowerCase() &&
        p.stockUnit == edit.stockUnit &&
        p.packageSize == edit.packageSize);
    if (duplicate) {
      showErrorSnack(context, 'Такая позиция уже существует: ${edit.name}.');
      return;
    }

    final employee = await _employee('Кто добавляет новый товар?');
    if (!mounted || employee == null) return;
    setState(() => adding = true);
    try {
      await _catalog.saveBatch(employee: employee, items: [_newProductPayload(edit)]);
      await widget.controller.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлен товар «${edit.name}». Остаток будет «не введён» до первой поставки или переучёта.')),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    if (deletingProductId != null) return;
    if (!widget.controller.sharedOnline) {
      showErrorSnack(context, 'Удаление товара требует подключения к общей базе.');
      return;
    }
    if (product.stockInitialized && product.totalAmount != 0) {
      showErrorSnack(
        context,
        'Нельзя удалить «${product.name}»: остаток не равен нулю. Сначала проведите переучёт и установите остаток 0.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(
          '«${product.name}» будет полностью удалён из текущего склада и исчезнет из поиска, поставок, закупок и новых переучётов.\n\n'
          'Проведённая история операций сохранится. Удаление возможно только при нулевом остатке и если товар не участвует в незавершённом переучёте или активной заявке на закупку.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ОТМЕНА')),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('УДАЛИТЬ ТОВАР'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final employee = await _employee('Кто удаляет товар?');
    if (!mounted || employee == null) return;
    setState(() => deletingProductId = product.id);
    try {
      await _catalog.deleteProduct(
        employee: employee,
        productKey: widget.controller.productKeyFor(product),
      );
      drafts.remove(product.id);
      await widget.controller.refresh();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Товар «${product.name}» удалён со склада. История проведённых операций сохранена.')),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => deletingProductId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование склада'),
        actions: [
          IconButton(
            tooltip: 'Добавить новый товар',
            onPressed: adding ? null : _addProduct,
            icon: const Icon(Icons.add_box_outlined),
          ),
          if (drafts.isNotEmpty)
            TextButton(
              onPressed: saving ? null : () => setState(drafts.clear),
              child: const Text('Отменить все'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InfoBanner(
                  icon: Icons.inventory_2_outlined,
                  text: 'Пароль для редактирования склада не требуется. Можно менять, добавлять и удалять товары. Удаление разрешено только при нулевом остатке; проведённая история сохраняется. Закупочная цена вручную не задаётся — её формирует фактическая поставка.',
                ),
                const SizedBox(height: 9),
                LayoutBuilder(builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 680;
                  final search = TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск товара, категории или кода', isDense: true),
                    onChanged: (value) => setState(() => query = value),
                  );
                  final categoryField = DropdownButtonFormField<String?>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Все категории')),
                      ...widget.controller.categories.map((x) => DropdownMenuItem<String?>(value: x.name, child: Text(x.name))),
                    ],
                    onChanged: (value) => setState(() => category = value),
                  );
                  final add = FilledButton.icon(
                    onPressed: adding ? null : _addProduct,
                    icon: adding
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: const Text('ДОБАВИТЬ НОВЫЙ ТОВАР'),
                  );
                  if (narrow) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      search,
                      const SizedBox(height: 8),
                      categoryField,
                      const SizedBox(height: 8),
                      add,
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    SizedBox(width: 220, child: categoryField),
                    const SizedBox(width: 8),
                    add,
                  ]);
                }),
                const SizedBox(height: 7),
                Text('${products.length} позиций • изменено: ${drafts.length}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? const EmptyState(icon: Icons.search_off, title: 'Ничего не найдено', message: 'Измените поиск или фильтр категории.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
                    itemCount: products.length,
                    itemBuilder: (_, i) {
                      final product = products[i];
                      return _BulkRow(
                        product: product,
                        edit: _edit(product),
                        changed: drafts.containsKey(product.id),
                        deleting: deletingProductId == product.id,
                        onChanged: (value) => _set(product, value),
                        onDelete: () => _deleteProduct(product),
                        categories: widget.controller.categories,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 10),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final save = FilledButton.icon(
            onPressed: drafts.isEmpty || saving ? null : _confirm,
            icon: saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
            label: const Text('СОХРАНИТЬ ИЗМЕНЕНИЯ'),
          );
          if (narrow) {
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Изменено: ${drafts.length}', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              save,
            ]);
          }
          return Row(children: [
            Expanded(child: Text('Изменено: ${drafts.length} товаров', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(), child: const Text('ЗАКРЫТЬ')),
            const SizedBox(width: 8),
            save,
          ]);
        }),
      ),
    );
  }
}

class _BulkRow extends StatelessWidget {
  const _BulkRow({
    required this.product,
    required this.edit,
    required this.changed,
    required this.deleting,
    required this.onChanged,
    required this.onDelete,
    required this.categories,
  });

  final Product product;
  final ProductV14CatalogEdit edit;
  final bool changed;
  final bool deleting;
  final ValueChanged<ProductV14CatalogEdit> onChanged;
  final VoidCallback onDelete;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 7),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(edit.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      if (changed) ...[
                        const SizedBox(width: 7),
                        const Chip(label: Text('ИЗМЕНЕНО')),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(edit.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      '${formatPackageSize(edit.packageSize, edit.stockUnit)} • код ${edit.barcode?.trim().isNotEmpty == true ? edit.barcode : '—'} • минимум ${edit.minimumAmount} ${edit.stockUnit.symbol} • цель ${edit.targetAmount} ${edit.stockUnit.symbol}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Продажа: ${edit.meta.sellByBottle ? formatMoney(edit.meta.bottleSalePrice) : 'бутылкой выкл.'}${edit.meta.portionSale ? ' • порций ${edit.meta.portions.length}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: deleting
                        ? null
                        : () async {
                            final value = await showDialog<ProductV14CatalogEdit>(
                              context: context,
                              builder: (_) => _CatalogEditDialog(
                                product: product,
                                initial: edit,
                                categories: categories,
                              ),
                            );
                            if (value != null) onChanged(value);
                          },
                    icon: const Icon(Icons.tune),
                    label: const Text('Настроить'),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: deleting ? null : onDelete,
                    icon: deleting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_forever_outlined),
                    label: const Text('Удалить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _CatalogEditDialog extends StatefulWidget {
  const _CatalogEditDialog({
    this.product,
    required this.initial,
    required this.categories,
  });

  final Product? product;
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
    portions = initial.meta.portions.map((x) => _PortionRow('${x.amount}', '${x.price}'.replaceAll('.', ','))).toList(growable: true);
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
      showErrorSnack(context, 'Проверьте название, минимум, цель и порог перепроверки.');
      return;
    }
    if (stockUnit == StockUnit.piece) package = 1;
    if (package == null || package <= 0) {
      showErrorSnack(context, 'Размер упаковки должен быть больше нуля.');
      return;
    }
    if (bottle && (salePrice == null || salePrice < 0)) {
      showErrorSnack(context, 'Укажите цену продажи бутылки / упаковки.');
      return;
    }

    final parsedPortions = <PortionPrice>[];
    for (final row in portions) {
      final amount = int.tryParse(row.amount.text.trim());
      final price = _double(row.price.text);
      if (amount == null || amount <= 0 || price == null || price < 0) {
        showErrorSnack(context, 'Проверьте объём и цену всех порций.');
        return;
      }
      parsedPortions.add(PortionPrice(amount: amount, price: price));
    }
    if (portion && parsedPortions.isEmpty) {
      showErrorSnack(context, 'Добавьте хотя бы одну порцию.');
      return;
    }

    final selectedCategory = widget.categories.where((x) => x.name == categoryName).firstOrNull;
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
        meta: widget.initial.meta.copyWith(
          sellByBottle: bottle,
          bottleSalePrice: salePrice,
          clearBottleSalePrice: !bottle && salePrice == null,
          portionSale: portion,
          portions: parsedPortions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'Добавить новый товар' : 'Редактировать • ${widget.product!.name}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: name, autofocus: widget.product == null, decoration: const InputDecoration(labelText: 'Название товара *')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: categoryName,
                  decoration: const InputDecoration(labelText: 'Категория *'),
                  items: widget.categories.map((x) => DropdownMenuItem(value: x.name, child: Text(x.name))).toList(growable: false),
                  onChanged: (value) => value == null ? null : setState(() => categoryName = value),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<StockUnit>(
                      initialValue: stockUnit,
                      decoration: const InputDecoration(labelText: 'Единица учёта'),
                      items: StockUnit.values.map((x) => DropdownMenuItem(value: x, child: Text(x.displayName))).toList(growable: false),
                      onChanged: (value) => value == null ? null : setState(() => stockUnit = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: packageSize,
                      enabled: stockUnit != StockUnit.piece,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: stockUnit == StockUnit.piece ? 'Упаковка = 1 шт.' : 'Объём / вес упаковки *'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Штрихкод / код товара')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Минимум'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Целевой остаток'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: variance, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Порог перепроверки'))),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: bottle,
                  onChanged: (value) => setState(() => bottle = value),
                  title: const Text('Продажа бутылкой / упаковкой'),
                ),
                if (bottle)
                  TextField(
                    controller: bottlePrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Цена продажи, BYN'),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: portion,
                  onChanged: (value) => setState(() => portion = value),
                  title: const Text('Порционная продажа'),
                ),
                if (portion) ...[
                  for (var i = 0; i < portions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(children: [
                        Expanded(child: TextField(controller: portions[i].amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Объём'))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: portions[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена BYN'))),
                        IconButton(
                          tooltip: 'Удалить порцию',
                          onPressed: () => setState(() {
                            portions.removeAt(i).dispose();
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ]),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => portions.add(_PortionRow('40', '0'))),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить порцию'),
                    ),
                  ),
                ],
                if (widget.product == null) ...[
                  const SizedBox(height: 10),
                  const InfoBanner(
                    icon: Icons.info_outline,
                    text: 'Новый товар создаётся без начального остатка. Поставщика можно назначить в карточке товара через шестерёнку. Закупочная цена появится только после фактической поставки.',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: _save, child: Text(widget.product == null ? 'ДОБАВИТЬ ТОВАР' : 'СОХРАНИТЬ В ЧЕРНОВИК')),
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
