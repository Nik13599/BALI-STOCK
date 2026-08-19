import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

class ProductDetailV14Screen extends StatelessWidget {
  const ProductDetailV14Screen({super.key, required this.controller, required this.product});

  final V14WarehouseController controller;
  final Product product;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final current = controller.products.where((x) => x.id == product.id).firstOrNull ?? product;
          final meta = controller.metaFor(current);
          final delivery = controller.lastDeliveryFor(current);
          final supplier = _primarySupplier(current);
          final lastCount = _latest(current, (x) => x == StockOperationType.stocktake || x == StockOperationType.spotStocktake);
          final lastMove = _latest(current, (_) => true);
          final status = _stockStatus(current);
          return Scaffold(
            appBar: AppBar(
              title: Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Настройки товара',
                  onPressed: () => _openSettings(context, current, meta),
                  icon: const BaliNavIcon(kind: BaliNavIconKind.settings, size: 23),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: controller.refresh,
                  icon: const BaliNavIcon(kind: BaliNavIconKind.sync, size: 21),
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 10, compact ? 12 : 20, 100),
                      children: [
                        _Hero(
                          product: current,
                          meta: meta,
                          status: status,
                          onSettings: () => _openSettings(context, current, meta),
                        ),
                        const SizedBox(height: 10),
                        _ResponsivePair(
                          first: _Section(
                            title: 'Склад',
                            icon: const BaliNavIcon(kind: BaliNavIconKind.stock, size: 21),
                            rows: [
                              _RowData('Сейчас', current.stockInitialized ? formatStockParts(current.totalAmount, current.packageSize, current.stockUnit) : 'Не введён', strong: true),
                              _RowData('Минимум', formatMinimumAmount(current.minimumAmount, current.stockUnit)),
                              if (current.targetAmount > 0) _RowData('Цель', formatTotalAmount(current.targetAmount, current.stockUnit)),
                              _RowData('Последний переучёт', lastCount == null ? '—' : formatDateTime(lastCount.createdAt)),
                              _RowData('Последнее движение', _movementLabel(lastMove, current)),
                            ],
                          ),
                          second: _Section(
                            title: 'Закупка',
                            icon: const BaliNavIcon(kind: BaliNavIconKind.purchases, size: 21),
                            rows: [
                              _RowData('Поставщик', supplier?.name ?? 'Поставщик не назначен', strong: true),
                              _RowData('Последняя цена', formatMoney(current.defaultCost, current.costCurrency)),
                              _RowData('Последняя поставка', delivery == null ? '—' : formatDateTime(delivery.createdAt)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SalesSummary(product: current, meta: meta),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _spotStocktake(context, current),
                            icon: const BaliNavIcon(kind: BaliNavIconKind.stocktake, active: true, size: 21),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('ПЕРЕУЧЕСТЬ ТОВАР', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _EconomicsExpansion(product: current, meta: meta),
                        const SizedBox(height: 8),
                        _HistoryExpansion(audit: controller.auditFor(current)),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );

  StockSupplier? _primarySupplier(Product product) {
    final links = controller.productSuppliers.where((x) => x.active && x.productKey == controller.productKeyFor(product)).toList(growable: false);
    ProductSupplierLink? preferred;
    for (final link in links) {
      if (link.isPrimary) {
        preferred = link;
        break;
      }
    }
    preferred ??= links.firstOrNull;
    if (preferred == null) return null;
    return controller.suppliers.where((x) => x.active && x.id == preferred!.supplierId).firstOrNull;
  }

  StockOperation? _latest(Product product, bool Function(StockOperationType type) accept) {
    StockOperation? found;
    for (final operation in controller.operations) {
      if (!accept(operation.type)) continue;
      final contains = operation.lines.any((line) => line.productId == product.id || line.productName.trim().toLowerCase() == product.name.trim().toLowerCase());
      if (!contains) continue;
      if (found == null || operation.createdAt.isAfter(found.createdAt)) found = operation;
    }
    return found;
  }

  String _movementLabel(StockOperation? operation, Product product) {
    if (operation == null) return '—';
    StockOperationLine? line;
    for (final item in operation.lines) {
      if (item.productId == product.id || item.productName.trim().toLowerCase() == product.name.trim().toLowerCase()) {
        line = item;
        break;
      }
    }
    if (line == null) return '${operation.type.displayName} • ${formatDateTime(operation.createdAt)}';
    final delta = line.changeTotalMl;
    final amount = delta == 0 ? '' : ' ${delta > 0 ? '+' : '−'}${formatStockParts(delta.abs(), product.packageSize, product.stockUnit)}';
    return '${operation.type.displayName}$amount • ${formatDateTime(operation.createdAt)}';
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

  Future<void> _openSettings(BuildContext context, Product product, ProductV14Meta meta) async {
    if (!await _authorize(context) || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const BaliNavIcon(kind: BaliNavIconKind.settings, active: true, size: 24),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Настройки товара', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                ]),
                const SizedBox(height: 14),
                _SettingsAction(
                  icon: const Icon(Icons.photo_camera_outlined),
                  title: meta.imageUrl == null ? 'Добавить фото товара' : 'Заменить фото товара',
                  subtitle: 'Фото хранится в общей базе и видно на всех устройствах.',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _pickImage(context, product);
                  },
                ),
                const SizedBox(height: 8),
                _SettingsAction(
                  icon: const BaliNavIcon(kind: BaliNavIconKind.delivery, size: 21),
                  title: 'Поставщик',
                  subtitle: _primarySupplier(product)?.name ?? 'Поставщик не назначен',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _chooseSupplier(context, product);
                  },
                ),
                const SizedBox(height: 8),
                _SettingsAction(
                  icon: const BaliNavIcon(kind: BaliNavIconKind.prices, size: 21),
                  title: 'Продажи и цены',
                  subtitle: 'Продажа бутылкой/упаковкой и порционные цены.',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _editSales(context, product, meta);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSupplier(BuildContext context, Product product) async {
    final active = controller.suppliers.where((x) => x.active).toList(growable: false)..sort((a, b) => a.name.compareTo(b.name));
    final chosen = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Поставщик • ${product.name}'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final supplier in active)
                  ListTile(
                    leading: const BaliNavIcon(kind: BaliNavIconKind.delivery, size: 19),
                    title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => Navigator.pop(dialogContext, supplier),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Ввести нового поставщика вручную', style: TextStyle(fontWeight: FontWeight.w900)),
                  onTap: () => Navigator.pop(dialogContext, 'new'),
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена'))],
      ),
    );
    if (!context.mounted || chosen == null) return;
    StockSupplier? supplier;
    if (chosen is StockSupplier) {
      supplier = chosen;
    } else if (chosen == 'new') {
      final name = await showTextValueDialog(context, 'Новый поставщик', 'Название поставщика');
      if (!context.mounted || name == null || name.trim().isEmpty) return;
      try {
        final id = await controller.addSupplier(name: name.trim());
        supplier = StockSupplier(id: id, name: name.trim());
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
        return;
      }
    }
    if (supplier == null) return;
    try {
      await controller.linkSupplier(product: product, supplierId: supplier.id, isPrimary: true);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Основной поставщик: ${supplier.name}')));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _pickImage(BuildContext context, Product product) async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Изображения',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ]);
    if (!context.mounted || file == null) return;
    final employee = await showTextValueDialog(context, 'Кто меняет фото?', 'ФИО сотрудника');
    if (!context.mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await controller.uploadProductImage(product: product, employee: employee.trim(), bytes: await file.readAsBytes(), fileName: file.name, mimeType: _imageMime(file.name));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Фото товара обновлено')));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _editSales(BuildContext context, Product product, ProductV14Meta initial) async {
    final result = await showDialog<ProductV14Meta>(context: context, builder: (_) => _SalesDialog(product: product, initial: initial));
    if (!context.mounted || result == null) return;
    final employee = await showTextValueDialog(context, 'Кто изменяет цены?', 'ФИО сотрудника');
    if (!context.mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await controller.saveProductSales(product: product, employee: employee.trim(), meta: result);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Продажи и цены сохранены')));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _spotStocktake(BuildContext context, Product product) async {
    if (!await _authorize(context) || !context.mounted) return;
    final input = await showDialog<_SpotInput>(context: context, builder: (_) => _SpotDialog(product: product));
    if (!context.mounted || input == null) return;
    try {
      final id = await controller.spotStocktake(product: product, employee: input.employee, quantityBase: input.quantityBase, reason: input.reason, comment: input.comment, device: Theme.of(context).platform.name, locationId: controller.primaryLocation?.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Точечный переучёт №$id сохранён')));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: icon,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _Status {
  const _Status(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

_Status _stockStatus(Product p) {
  if (!p.stockInitialized) return const _Status('НЕ ВВЕДЕНО', Color(0xFF89948D), Icons.help_outline_rounded);
  if (p.totalAmount <= 0) return const _Status('НЕТ В НАЛИЧИИ', Color(0xFFFF5C67), Icons.remove_circle_outline);
  if (p.minimumAmount > 0 && p.totalAmount <= ((p.minimumAmount + 1) ~/ 2)) return const _Status('КРИТИЧНО', Color(0xFFFF5C67), Icons.error_outline_rounded);
  if (p.minimumAmount > 0 && p.totalAmount <= p.minimumAmount) return const _Status('МАЛО', Color(0xFFFFB547), Icons.warning_amber_rounded);
  return const _Status('НОРМА', Color(0xFF39FF6A), Icons.check_circle_outline_rounded);
}

class _Hero extends StatelessWidget {
  const _Hero({required this.product, required this.meta, required this.status, required this.onSettings});
  final Product product;
  final ProductV14Meta meta;
  final _Status status;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 390;
        final size = narrow ? 78.0 : 96.0;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(narrow ? 12 : 15),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: meta.imageUrl == null ? const Icon(Icons.inventory_2_outlined, size: 38) : Image.network(meta.imageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, height: 1.05))),
                  IconButton(visualDensity: VisualDensity.compact, tooltip: 'Настройки товара', onPressed: onSettings, icon: const BaliNavIcon(kind: BaliNavIconKind.settings, size: 21)),
                ]),
                Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
                if ((product.barcode ?? '').trim().isNotEmpty) Text('Код ${product.barcode}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 7),
                Text(product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Остаток не введён', style: TextStyle(fontSize: narrow ? 18 : 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: status.color.withValues(alpha: .6)), color: status.color.withValues(alpha: .12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(status.icon, size: 15, color: status.color), const SizedBox(width: 5), Text(status.label, style: TextStyle(color: status.color, fontSize: 11.5, fontWeight: FontWeight.w900))]),
                ),
              ])),
            ]),
          ),
        );
      });
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});
  final Widget first;
  final Widget second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => constraints.maxWidth < 680
      ? Column(children: [first, const SizedBox(height: 10), second])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: first), const SizedBox(width: 10), Expanded(child: second)]));
}

class _RowData {
  const _RowData(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});
  final String title;
  final Widget icon;
  final List<_RowData> rows;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [icon, const SizedBox(width: 7), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 7),
        ...rows.map((x) => _ValueRow(x.label, x.value, strong: x.strong)),
      ])));
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(width: 10),
        Expanded(flex: 6, child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w900 : FontWeight.w700))),
      ]));
}

class _SalesSummary extends StatelessWidget {
  const _SalesSummary({required this.product, required this.meta});
  final Product product;
  final ProductV14Meta meta;
  @override
  Widget build(BuildContext context) {
    final bottle = meta.sellByBottle && meta.bottleSalePrice != null;
    final portions = meta.portionSale && meta.portions.isNotEmpty;
    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [BaliNavIcon(kind: BaliNavIconKind.prices, size: 21), SizedBox(width: 7), Text('Продажа', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 8),
      if (!bottle && !portions) const Text('Цены продажи пока не настроены.') else ...[
        if (bottle) _ValueRow('Бутылка / упаковка', formatMoney(meta.bottleSalePrice), strong: true),
        if (portions) Wrap(spacing: 7, runSpacing: 7, children: meta.portions.map((x) => Chip(visualDensity: VisualDensity.compact, label: Text('${x.amount} ${product.stockUnit.symbol} · ${formatMoney(x.price)}', style: const TextStyle(fontWeight: FontWeight.w800)))).toList(growable: false)),
      ],
    ])));
  }
}

class _EconomicsExpansion extends StatelessWidget {
  const _EconomicsExpansion({required this.product, required this.meta});
  final Product product;
  final ProductV14Meta meta;
  @override
  Widget build(BuildContext context) {
    final economics = ProductEconomics(product: product, meta: meta);
    return Card(clipBehavior: Clip.antiAlias, child: ExpansionTile(
      leading: const BaliNavIcon(kind: BaliNavIconKind.prices, size: 21),
      title: const Text('Экономика', style: TextStyle(fontWeight: FontWeight.w900)),
      subtitle: const Text('Себестоимость, прибыль и маржа'),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      children: [
        _ValueRow('Закупка за упаковку', formatMoney(product.defaultCost, product.costCurrency), strong: true),
        _ValueRow('Себестоимость 1 ${product.stockUnit.symbol}', formatMoney(economics.costPerBaseUnit)),
        _ValueRow('Стоимость остатка', formatMoney(economics.stockCost)),
        if (meta.sellByBottle) ...[
          _ValueRow('Прибыль с бутылки', formatMoney(economics.bottleGrossProfit)),
          _ValueRow('Наценка', _percent(economics.bottleMarkupPercent)),
          _ValueRow('Маржа', _percent(economics.bottleMarginPercent)),
        ],
      ],
    ));
  }
}

class _HistoryExpansion extends StatelessWidget {
  const _HistoryExpansion({required this.audit});
  final List<CatalogAuditEntry> audit;
  @override
  Widget build(BuildContext context) => Card(clipBehavior: Clip.antiAlias, child: ExpansionTile(
        leading: const BaliNavIcon(kind: BaliNavIconKind.history, size: 21),
        title: const Text('История карточки', style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(audit.isEmpty ? 'Изменений пока нет' : 'Последних изменений: ${audit.length.clamp(0, 12)}'),
        children: audit.take(12).map((x) => ListTile(dense: true, title: const Text('Изменение карточки товара'), subtitle: Text('${formatDateTime(x.createdAt)}${x.actor == null ? '' : ' • ${x.actor}'}'))).toList(growable: false),
      ));
}

class _SalesDialog extends StatefulWidget {
  const _SalesDialog({required this.product, required this.initial});
  final Product product;
  final ProductV14Meta initial;
  @override
  State<_SalesDialog> createState() => _SalesDialogState();
}

class _SalesDialogState extends State<_SalesDialog> {
  late bool sellBottle;
  late bool sellPortion;
  late final TextEditingController bottlePrice;
  late List<_PortionEditors> portions;
  @override
  void initState() {
    super.initState();
    sellBottle = widget.initial.sellByBottle;
    sellPortion = widget.initial.portionSale;
    bottlePrice = TextEditingController(text: widget.initial.bottleSalePrice?.toStringAsFixed(2).replaceAll('.', ',') ?? '');
    portions = widget.initial.portions.map((x) => _PortionEditors('${x.amount}', x.price.toStringAsFixed(2).replaceAll('.', ','))).toList();
  }
  @override
  void dispose() {
    bottlePrice.dispose();
    for (final x in portions) x.dispose();
    super.dispose();
  }
  double? _number(String value) => double.tryParse(value.trim().replaceAll(',', '.'));
  void _save() {
    final bottle = _number(bottlePrice.text);
    if (sellBottle && (bottle == null || bottle < 0)) { showErrorSnack(context, 'Укажите цену бутылки'); return; }
    final parsed = <PortionPrice>[];
    for (final x in portions) {
      final amount = int.tryParse(x.amount.text.trim());
      final price = _number(x.price.text);
      if (amount == null || amount <= 0 || price == null || price < 0) { showErrorSnack(context, 'Проверьте объём и цену порций'); return; }
      parsed.add(PortionPrice(amount: amount, price: price));
    }
    if (sellPortion && parsed.isEmpty) { showErrorSnack(context, 'Добавьте хотя бы одну порцию'); return; }
    Navigator.pop(context, widget.initial.copyWith(sellByBottle: sellBottle, bottleSalePrice: bottle, clearBottleSalePrice: !sellBottle && bottle == null, portionSale: sellPortion, portions: parsed));
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Продажи и цены • ${widget.product.name}'),
    content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, value: sellBottle, onChanged: (v) => setState(() => sellBottle = v), title: const Text('Продажа бутылкой / упаковкой', style: TextStyle(fontWeight: FontWeight.w800))),
      TextField(controller: bottlePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена, BYN')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: sellPortion, onChanged: (v) => setState(() => sellPortion = v), title: const Text('Порционная продажа', style: TextStyle(fontWeight: FontWeight.w800))),
      ...List.generate(portions.length, (i) => Row(children: [
        Expanded(child: TextField(controller: portions[i].amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Объём, ${widget.product.stockUnit.symbol}'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: portions[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цена, BYN'))),
        IconButton(onPressed: () => setState(() { final x = portions.removeAt(i); x.dispose(); }), icon: const Icon(Icons.delete_outline)),
      ])),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => portions.add(_PortionEditors('40', ''))), icon: const Icon(Icons.add), label: const Text('Добавить порцию'))),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: _save, child: const Text('Сохранить'))],
  );
}

class _PortionEditors {
  _PortionEditors(String amount, String price) : amount = TextEditingController(text: amount), price = TextEditingController(text: price);
  final TextEditingController amount;
  final TextEditingController price;
  void dispose() { amount.dispose(); price.dispose(); }
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
      whole.text = widget.product.stockUnit == StockUnit.piece ? '${widget.product.totalAmount}' : '${widget.product.wholePackages}';
      extra.text = widget.product.stockUnit == StockUnit.piece ? '0' : '${widget.product.extraAmount}';
    }
  }
  @override
  void dispose() { employee.dispose(); whole.dispose(); extra.dispose(); comment.dispose(); super.dispose(); }
  void _save() {
    final emp = employee.text.trim();
    final w = int.tryParse(whole.text.trim());
    final e = widget.product.stockUnit == StockUnit.piece ? 0 : int.tryParse(extra.text.trim());
    if (emp.isEmpty || w == null || w < 0 || e == null || e < 0 || (widget.product.stockUnit != StockUnit.piece && e >= widget.product.packageSize)) { showErrorSnack(context, 'Проверьте ФИО и фактический остаток'); return; }
    if (reason == SpotStocktakeReason.other && comment.text.trim().isEmpty) { showErrorSnack(context, 'Комментарий обязателен'); return; }
    final total = widget.product.stockUnit == StockUnit.piece ? w : w * widget.product.packageSize + e;
    Navigator.pop(context, _SpotInput(employee: emp, quantityBase: total, reason: reason, comment: comment.text.trim().isEmpty ? null : comment.text.trim()));
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Переучесть • ${widget.product.name}'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: employee, decoration: const InputDecoration(labelText: 'ФИО сотрудника')),
      const SizedBox(height: 10),
      if (widget.product.stockUnit == StockUnit.piece)
        TextField(controller: whole, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Фактически, шт.'))
      else Row(children: [Expanded(child: TextField(controller: whole, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: widget.product.stockUnit.packageLabel))), const SizedBox(width: 10), Expanded(child: TextField(controller: extra, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Остаток, ${widget.product.stockUnit.symbol}')))]),
      const SizedBox(height: 10),
      DropdownButtonFormField<SpotStocktakeReason>(initialValue: reason, decoration: const InputDecoration(labelText: 'Причина'), items: SpotStocktakeReason.values.map((x) => DropdownMenuItem(value: x, child: Text(x.label))).toList(growable: false), onChanged: (v) => setState(() => reason = v ?? reason)),
      const SizedBox(height: 10),
      TextField(controller: comment, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: reason == SpotStocktakeReason.other ? 'Комментарий — обязательно' : 'Комментарий')),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: _save, child: const Text('Подтвердить'))],
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
