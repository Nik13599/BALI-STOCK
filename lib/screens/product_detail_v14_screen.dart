import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

class ProductDetailV14Screen extends StatelessWidget {
  const ProductDetailV14Screen({super.key, required this.controller, required this.product});

  final V14WarehouseController controller;
  final Product product;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.products.where((x) => x.id == product.id).firstOrNull ?? product;
        final meta = controller.metaFor(current);
        final economics = ProductEconomics(product: current, meta: meta);
        final delivery = controller.lastDeliveryFor(current);
        final deliveryLine = controller.lastDeliveryLineFor(current);
        final audit = controller.auditFor(current);

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name),
            actions: [
              IconButton(onPressed: controller.refresh, tooltip: 'Обновить', icon: const Icon(Icons.refresh)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _Hero(product: current, meta: meta),
              const SizedBox(height: 14),
              _Section(
                title: 'Склад',
                icon: Icons.inventory_2_outlined,
                rows: [
                  ('Категория', current.categoryName, false),
                  (
                    'Остаток',
                    current.stockInitialized
                        ? formatStockParts(current.totalAmount, current.packageSize, current.stockUnit)
                        : 'Остаток ещё не введён',
                    true,
                  ),
                  if (current.stockInitialized) ('Всего', formatTotalAmount(current.totalAmount, current.stockUnit), false),
                  ('Минимум', formatMinimumAmount(current.minimumAmount, current.stockUnit), false),
                  if (current.targetAmount > 0) ('Цель', formatTotalAmount(current.targetAmount, current.stockUnit), false),
                  ('Код', current.barcode?.trim().isNotEmpty == true ? current.barcode! : 'Не задан', false),
                ],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Закупка',
                icon: Icons.shopping_cart_checkout_outlined,
                rows: [
                  ('Последняя закупочная цена', formatMoney(current.defaultCost, current.costCurrency), true),
                  ('Последняя поставка', delivery == null ? '—' : formatDateTime(delivery.createdAt), false),
                  ('Поставщик', delivery?.supplierName ?? '—', false),
                  if (deliveryLine?.unitCost != null)
                    ('Цена в последней поставке', formatMoney(deliveryLine!.unitCost, current.costCurrency), false),
                ],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Продажа бутылкой',
                icon: Icons.local_bar_outlined,
                rows: [
                  ('Статус', meta.sellByBottle ? 'Включена' : 'Выключена', false),
                  ('Цена бутылки', meta.sellByBottle ? formatMoney(meta.bottleSalePrice) : '—', true),
                  ('Валовая прибыль', formatMoney(economics.bottleGrossProfit), false),
                  ('Наценка', _percent(economics.bottleMarkupPercent), false),
                  ('Валовая маржа', _percent(economics.bottleMarginPercent), false),
                ],
              ),
              const SizedBox(height: 10),
              _PortionSection(product: current, meta: meta, economics: economics),
              const SizedBox(height: 10),
              _Section(
                title: 'Аналитика',
                icon: Icons.analytics_outlined,
                rows: [
                  ('Себестоимость 1 ${current.stockUnit.symbol}', formatMoney(economics.costPerBaseUnit), false),
                  ('Стоимость фактического остатка', formatMoney(economics.stockCost), true),
                  ('Потенциальная выручка бутылками', formatMoney(economics.potentialBottleRevenue()), false),
                  if (meta.portions.isNotEmpty)
                    (
                      'Потенциальная выручка (${meta.portions.first.amount} ${current.stockUnit.symbol})',
                      formatMoney(economics.potentialPortionRevenue(meta.portions.first)),
                      false,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => _spotStocktake(context, current),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Точечный переучёт'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editSales(context, current, meta),
                    icon: const Icon(Icons.price_change_outlined),
                    label: const Text('Продажи и цены'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickImage(context, current),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(meta.imageUrl == null ? 'Добавить фото' : 'Заменить фото'),
                  ),
                ],
              ),
              if (audit.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('История карточки и цен', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...audit.take(12).map((entry) => _AuditTile(entry: entry)),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<bool> _authorize(BuildContext context) async {
    final pin = await showOperationPinValueDialog(context);
    if (!context.mounted || pin == null) return false;
    try {
      await controller.setOperationSessionPin(pin);
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
      return false;
    }
  }

  Future<void> _editSales(BuildContext context, Product product, ProductV14Meta meta) async {
    if (!await _authorize(context) || !context.mounted) return;
    final result = await showDialog<ProductV14Meta>(
      context: context,
      builder: (_) => _SalesDialog(product: product, initial: meta),
    );
    if (!context.mounted || result == null) return;
    final employee = await showTextValueDialog(context, 'Кто изменяет карточку?', 'ФИО сотрудника');
    if (!context.mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await controller.saveProductSales(product: product, employee: employee.trim(), meta: result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Изменения карточки сохранены')));
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _pickImage(BuildContext context, Product product) async {
    if (!await _authorize(context) || !context.mounted) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Изображения',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (!context.mounted || file == null) return;
    final employee = await showTextValueDialog(context, 'Кто добавляет фото?', 'ФИО сотрудника');
    if (!context.mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await controller.uploadProductImage(
        product: product,
        employee: employee.trim(),
        bytes: await file.readAsBytes(),
        fileName: file.name,
        mimeType: _imageMime(file.name),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Фото товара сохранено в общей базе')));
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _spotStocktake(BuildContext context, Product product) async {
    if (!await _authorize(context) || !context.mounted) return;
    final input = await showDialog<_SpotInput>(context: context, builder: (_) => _SpotDialog(product: product));
    if (!context.mounted || input == null) return;
    try {
      final id = await controller.spotStocktake(
        product: product,
        employee: input.employee,
        quantityBase: input.quantityBase,
        reason: input.reason,
        comment: input.comment,
        device: Theme.of(context).platform.name,
        locationId: controller.primaryLocation?.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Точечный переучёт №$id сохранён')));
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.product, required this.meta});
  final Product product;
  final ProductV14Meta meta;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: meta.imageUrl == null
                    ? const Icon(Icons.inventory_2_outlined, size: 46)
                    : Image.network(
                        meta.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 42),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(
                      product.stockInitialized
                          ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit)
                          : 'Остаток не введён',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

typedef _RowData = (String label, String value, bool strong);

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});
  final String title;
  final IconData icon;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 12),
              ...rows.map((row) => _ValueRow(row.$1, row.$2, strong: row.$3)),
            ],
          ),
        ),
      );
}

class _PortionSection extends StatelessWidget {
  const _PortionSection({required this.product, required this.meta, required this.economics});
  final Product product;
  final ProductV14Meta meta;
  final ProductEconomics economics;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.liquor_outlined), SizedBox(width: 8), Text('Порционная продажа', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 12),
              _ValueRow('Статус', meta.portionSale ? 'Включена' : 'Выключена'),
              if (meta.portionSale && meta.portions.isEmpty) const Text('Размеры порций пока не заданы.'),
              ...meta.portions.expand((portion) => [
                    const Divider(height: 18),
                    _ValueRow('${portion.amount} ${product.stockUnit.symbol}', formatMoney(portion.price), strong: true),
                    _ValueRow('Себестоимость', formatMoney(economics.portionCost(portion))),
                    _ValueRow('Валовая прибыль', formatMoney(economics.portionGrossProfit(portion))),
                    _ValueRow('Маржа', _percent(economics.portionMarginPercent(portion))),
                  ]),
            ],
          ),
        ),
      );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700))),
          ],
        ),
      );
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});
  final CatalogAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final before = entry.beforeData?['bottle_sale_price'];
    final after = entry.afterData?['bottle_sale_price'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(before != after ? 'Цена бутылки: ${before ?? '—'} → ${after ?? '—'} BYN' : 'Изменение карточки товара'),
        subtitle: Text('${formatDateTime(entry.createdAt)}${entry.actor == null ? '' : ' • ${entry.actor}'}'),
      ),
    );
  }
}

class _SalesDialog extends StatefulWidget {
  const _SalesDialog({required this.product, required this.initial});
  final Product product;
  final ProductV14Meta initial;

  @override
  State<_SalesDialog> createState() => _SalesDialogState();
}

class _SalesDialogState extends State<_SalesDialog> {
  late bool sellByBottle;
  late bool portionSale;
  late final TextEditingController bottlePrice;
  late List<_PortionEditors> portions;

  @override
  void initState() {
    super.initState();
    sellByBottle = widget.initial.sellByBottle;
    portionSale = widget.initial.portionSale;
    bottlePrice = TextEditingController(text: widget.initial.bottleSalePrice?.toStringAsFixed(2).replaceAll('.', ',') ?? '');
    portions = widget.initial.portions
        .map((x) => _PortionEditors('${x.amount}', x.price.toStringAsFixed(2).replaceAll('.', ',')))
        .toList();
  }

  @override
  void dispose() {
    bottlePrice.dispose();
    for (final editor in portions) {
      editor.dispose();
    }
    super.dispose();
  }

  double? _number(String value) => double.tryParse(value.trim().replaceAll(',', '.'));

  void _save() {
    final bottle = _number(bottlePrice.text);
    if (sellByBottle && (bottle == null || bottle < 0)) {
      showErrorSnack(context, 'Укажите цену продажи бутылки');
      return;
    }
    final parsed = <PortionPrice>[];
    for (final editor in portions) {
      final amount = int.tryParse(editor.amount.text.trim());
      final price = _number(editor.price.text);
      if (amount == null || amount <= 0 || price == null || price < 0) {
        showErrorSnack(context, 'Проверьте объём и цену всех порций');
        return;
      }
      parsed.add(PortionPrice(amount: amount, price: price));
    }
    if (portionSale && parsed.isEmpty) {
      showErrorSnack(context, 'Добавьте хотя бы одну порцию');
      return;
    }
    Navigator.of(context).pop(widget.initial.copyWith(
          sellByBottle: sellByBottle,
          bottleSalePrice: bottle,
          clearBottleSalePrice: !sellByBottle && bottle == null,
          portionSale: portionSale,
          portions: parsed,
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Продажи • ${widget.product.name}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: sellByBottle,
                  onChanged: (value) => setState(() => sellByBottle = value),
                  title: const Text('Продажа бутылкой', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                TextField(
                  controller: bottlePrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена бутылки, BYN'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: portionSale,
                  onChanged: (value) => setState(() => portionSale = value),
                  title: const Text('Порционная продажа', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                ...List.generate(portions.length, (i) => _portionRow(i)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => portions.add(_PortionEditors('40', ''))),
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
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      );

  Widget _portionRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: portions[i].amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Объём, ${widget.product.stockUnit.symbol}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: portions[i].price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Цена, BYN'),
              ),
            ),
            IconButton(
              tooltip: 'Удалить порцию',
              onPressed: () => setState(() {
                final editor = portions.removeAt(i);
                editor.dispose();
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      );
}

class _PortionEditors {
  _PortionEditors(String amount, String price)
      : amount = TextEditingController(text: amount),
        price = TextEditingController(text: price);
  final TextEditingController amount;
  final TextEditingController price;

  void dispose() {
    amount.dispose();
    price.dispose();
  }
}

class _SpotInput {
  const _SpotInput({required this.employee, required this.quantityBase, required this.reason, this.comment});
  final String employee;
  final int quantityBase;
  final SpotStocktakeReason reason;
  final String? comment;
}

class _SpotDialog extends StatefulWidget {
  const _SpotDialog({required this.product});
  final Product product;

  @override
  State<_SpotDialog> createState() => _SpotDialogState();
}

class _SpotDialogState extends State<_SpotDialog> {
  final employee = TextEditingController();
  final whole = TextEditingController();
  final extra = TextEditingController();
  final comment = TextEditingController();
  SpotStocktakeReason reason = SpotStocktakeReason.shortage;

  @override
  void initState() {
    super.initState();
    if (widget.product.stockInitialized) {
      if (widget.product.stockUnit == StockUnit.piece) {
        whole.text = '${widget.product.totalAmount}';
      } else {
        whole.text = '${widget.product.wholePackages}';
        extra.text = '${widget.product.extraAmount}';
      }
    }
  }

  @override
  void dispose() {
    employee.dispose();
    whole.dispose();
    extra.dispose();
    comment.dispose();
    super.dispose();
  }

  void _save() {
    final employeeName = employee.text.trim();
    final packages = int.tryParse(whole.text.trim());
    final remainder = widget.product.stockUnit == StockUnit.piece ? 0 : int.tryParse(extra.text.trim());
    if (employeeName.isEmpty || packages == null || packages < 0 || remainder == null || remainder < 0) {
      showErrorSnack(context, 'Заполните ФИО и фактический остаток');
      return;
    }
    if (widget.product.stockUnit != StockUnit.piece && remainder >= widget.product.packageSize) {
      showErrorSnack(context, 'Остаток в открытой таре должен быть меньше размера упаковки');
      return;
    }
    if (reason == SpotStocktakeReason.other && comment.text.trim().isEmpty) {
      showErrorSnack(context, 'Для «Другой причины» комментарий обязателен');
      return;
    }
    final quantity = widget.product.stockUnit == StockUnit.piece
        ? packages
        : packages * widget.product.packageSize + remainder;
    Navigator.of(context).pop(_SpotInput(
          employee: employeeName,
          quantityBase: quantity,
          reason: reason,
          comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Точечный переучёт • ${widget.product.name}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: employee, decoration: const InputDecoration(labelText: 'ФИО сотрудника')),
                const SizedBox(height: 10),
                if (widget.product.stockUnit == StockUnit.piece)
                  TextField(
                    controller: whole,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Фактически, шт.'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: whole,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: widget.product.stockUnit.packageLabel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: extra,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Остаток, ${widget.product.stockUnit.symbol}'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SpotStocktakeReason>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Причина'),
                  items: SpotStocktakeReason.values.map((x) => DropdownMenuItem(value: x, child: Text(x.label))).toList(growable: false),
                  onChanged: (value) => setState(() => reason = value ?? reason),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: reason == SpotStocktakeReason.other ? 'Комментарий — обязательно' : 'Комментарий'),
                ),
                const SizedBox(height: 12),
                const InfoBanner(
                  icon: Icons.history_toggle_off,
                  text: 'Остаток не переписывается бесследно: создаётся отдельная операция «Точечный переучёт» с было → разница → стало.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: _save, child: const Text('Подтвердить')),
        ],
      );
}

String _percent(double? value) => value == null ? '—' : '${value.toStringAsFixed(1).replaceAll('.', ',')}%';

String _imageMime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}
