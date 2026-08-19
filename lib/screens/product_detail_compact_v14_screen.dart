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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.products.where((x) => x.id == product.id).firstOrNull ?? product;
        final meta = controller.metaFor(current);
        final economics = ProductEconomics(product: current, meta: meta);
        final delivery = controller.lastDeliveryFor(current);
        final audit = controller.auditFor(current);
        final lastStocktake = _latestOperation(
          current,
          (type) => type == StockOperationType.stocktake || type == StockOperationType.spotStocktake,
        );
        final lastMovement = _latestOperation(current, (_) => true);
        final status = _statusFor(current);

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(onPressed: controller.refresh, tooltip: 'Обновить', icon: const BaliNavIcon(kind: BaliNavIconKind.sync, size: 22)),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 10, compact ? 12 : 20, 96),
                    children: [
                      _Hero(product: current, meta: meta, status: status),
                      const SizedBox(height: 10),
                      _ResponsivePair(
                        first: _CompactSection(
                          title: 'Склад',
                          icon: const BaliNavIcon(kind: BaliNavIconKind.stock, size: 21),
                          rows: [
                            _RowData(
                              'Сейчас',
                              current.stockInitialized
                                  ? formatStockParts(current.totalAmount, current.packageSize, current.stockUnit)
                                  : 'Не введён',
                              strong: true,
                            ),
                            _RowData('Минимум', formatMinimumAmount(current.minimumAmount, current.stockUnit)),
                            if (current.targetAmount > 0) _RowData('Цель', formatTotalAmount(current.targetAmount, current.stockUnit)),
                            _RowData('Последний переучёт', lastStocktake == null ? '—' : formatDateTime(lastStocktake.createdAt)),
                            _RowData('Последнее движение', _movementLabel(lastMovement, current)),
                          ],
                        ),
                        second: _CompactSection(
                          title: 'Закупка',
                          icon: const BaliNavIcon(kind: BaliNavIconKind.purchases, size: 21),
                          rows: [
                            _RowData('Последняя цена', formatMoney(current.defaultCost, current.costCurrency), strong: true),
                            _RowData('Поставщик', delivery?.supplierName ?? '—'),
                            _RowData('Последняя поставка', delivery == null ? '—' : formatDateTime(delivery.createdAt)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SalesSummary(product: current, meta: meta),
                      const SizedBox(height: 12),
                      _PrimaryActions(
                        onStocktake: () => _spotStocktake(context, current),
                        onSales: () => _editSales(context, current, meta),
                        onPhoto: () => _pickImage(context, current),
                        hasPhoto: meta.imageUrl != null,
                      ),
                      const SizedBox(height: 10),
                      _EconomicsExpansion(product: current, meta: meta, economics: economics),
                      const SizedBox(height: 8),
                      _HistoryExpansion(audit: audit),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  StockOperation? _latestOperation(Product product, bool Function(StockOperationType type) accept) {
    StockOperation? latest;
    for (final operation in controller.operations) {
      if (!accept(operation.type) || !_operationContainsProduct(operation, product)) continue;
      if (latest == null || operation.createdAt.isAfter(latest.createdAt)) latest = operation;
    }
    return latest;
  }

  bool _operationContainsProduct(StockOperation operation, Product product) {
    final wanted = product.name.trim().toLowerCase();
    return operation.lines.any((line) => line.productId == product.id || line.productName.trim().toLowerCase() == wanted);
  }

  String _movementLabel(StockOperation? operation, Product product) {
    if (operation == null) return '—';
    StockOperationLine? line;
    final wanted = product.name.trim().toLowerCase();
    for (final item in operation.lines) {
      if (item.productId == product.id || item.productName.trim().toLowerCase() == wanted) {
        line = item;
        break;
      }
    }
    if (line == null) return '${operation.type.displayName} • ${formatDateTime(operation.createdAt)}';
    final delta = line.changeTotalMl;
    final deltaText = delta == 0
        ? ''
        : ' ${delta > 0 ? '+' : '−'}${formatStockParts(delta.abs(), product.packageSize, product.stockUnit)}';
    return '${operation.type.displayName}$deltaText • ${formatDateTime(operation.createdAt)}';
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

class _StockStatus {
  const _StockStatus(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

_StockStatus _statusFor(Product product) {
  if (!product.stockInitialized) {
    return const _StockStatus('НЕ ВВЕДЕНО', Color(0xFF89948D), Icons.help_outline_rounded);
  }
  if (product.totalAmount <= 0) {
    return const _StockStatus('НЕТ В НАЛИЧИИ', Color(0xFFFF5C67), Icons.remove_circle_outline);
  }
  final minimum = product.minimumAmount;
  if (minimum > 0 && product.totalAmount <= ((minimum + 1) ~/ 2)) {
    return const _StockStatus('КРИТИЧНО', Color(0xFFFF5C67), Icons.error_outline_rounded);
  }
  if (minimum > 0 && product.totalAmount <= minimum) {
    return const _StockStatus('МАЛО', Color(0xFFFFB547), Icons.warning_amber_rounded);
  }
  return const _StockStatus('НОРМА', Color(0xFF39FF6A), Icons.check_circle_outline_rounded);
}

class _Hero extends StatelessWidget {
  const _Hero({required this.product, required this.meta, required this.status});
  final Product product;
  final ProductV14Meta meta;
  final _StockStatus status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 390;
        final imageSize = narrow ? 78.0 : 96.0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.all(narrow ? 12 : 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: meta.imageUrl == null
                      ? const Icon(Icons.inventory_2_outlined, size: 38)
                      : Image.network(
                          meta.imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 36),
                        ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
                      ),
                      const SizedBox(height: 4),
                      Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
                      if ((product.barcode ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Код ${product.barcode}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        product.stockInitialized
                            ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit)
                            : 'Остаток не введён',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: narrow ? 18 : 21, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      _StatusChip(status: status),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final _StockStatus status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: status.color.withValues(alpha: .55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 15, color: status.color),
            const SizedBox(width: 5),
            Text(status.label, style: TextStyle(color: status.color, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: .3)),
          ],
        ),
      );
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(children: [first, const SizedBox(height: 10), second]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ]);
        },
      );
}

class _RowData {
  const _RowData(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
}

class _CompactSection extends StatelessWidget {
  const _CompactSection({required this.title, required this.icon, required this.rows});
  final String title;
  final Widget icon;
  final List<_RowData> rows;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [icon, const SizedBox(width: 7), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
              const SizedBox(height: 7),
              ...rows.map((row) => _ValueRow(row.label, row.value, strong: row.strong)),
            ],
          ),
        ),
      );
}

class _SalesSummary extends StatelessWidget {
  const _SalesSummary({required this.product, required this.meta});
  final Product product;
  final ProductV14Meta meta;

  @override
  Widget build(BuildContext context) {
    final hasBottle = meta.sellByBottle && meta.bottleSalePrice != null;
    final hasPortions = meta.portionSale && meta.portions.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                BaliNavIcon(kind: BaliNavIconKind.prices, size: 21),
                SizedBox(width: 7),
                Text('Продажа', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            if (!hasBottle && !hasPortions)
              Text('Цены продажи пока не настроены.', style: Theme.of(context).textTheme.bodyMedium)
            else ...[
              if (hasBottle) _ValueRow('Бутылка / упаковка', formatMoney(meta.bottleSalePrice), strong: true),
              if (hasPortions) ...[
                if (hasBottle) const Divider(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: meta.portions
                      .map((portion) => Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${portion.amount} ${product.stockUnit.symbol} · ${formatMoney(portion.price)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ))
                      .toList(growable: false),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.onStocktake,
    required this.onSales,
    required this.onPhoto,
    required this.hasPhoto,
  });

  final VoidCallback onStocktake;
  final VoidCallback onSales;
  final VoidCallback onPhoto;
  final bool hasPhoto;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final primary = SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStocktake,
              icon: const BaliNavIcon(kind: BaliNavIconKind.stocktake, active: true, size: 21),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Text('ПЕРЕУЧЕСТЬ ТОВАР', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          );
          final sales = OutlinedButton.icon(
            onPressed: onSales,
            icon: const BaliNavIcon(kind: BaliNavIconKind.prices, size: 19),
            label: const Text('Продажи и цены'),
          );
          final photo = OutlinedButton.icon(
            onPressed: onPhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            label: Text(hasPhoto ? 'Заменить фото' : 'Добавить фото'),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: 8),
              if (constraints.maxWidth < 440)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sales, const SizedBox(height: 7), photo])
              else
                Row(children: [Expanded(child: sales), const SizedBox(width: 8), Expanded(child: photo)]),
            ],
          );
        },
      );
}

class _EconomicsExpansion extends StatelessWidget {
  const _EconomicsExpansion({required this.product, required this.meta, required this.economics});
  final Product product;
  final ProductV14Meta meta;
  final ProductEconomics economics;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const BaliNavIcon(kind: BaliNavIconKind.prices, size: 21),
          title: const Text('Экономика', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('Себестоимость, прибыль и маржа'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            _ValueRow('Закупка за упаковку', formatMoney(product.defaultCost, product.costCurrency), strong: true),
            _ValueRow('Себестоимость 1 ${product.stockUnit.symbol}', formatMoney(economics.costPerBaseUnit)),
            _ValueRow('Стоимость остатка', formatMoney(economics.stockCost)),
            if (meta.sellByBottle) ...[
              const Divider(height: 14),
              _ValueRow('Прибыль с бутылки', formatMoney(economics.bottleGrossProfit)),
              _ValueRow('Наценка', _percent(economics.bottleMarkupPercent)),
              _ValueRow('Маржа', _percent(economics.bottleMarginPercent)),
              _ValueRow('Потенциальная выручка', formatMoney(economics.potentialBottleRevenue())),
            ],
            if (meta.portionSale)
              ...meta.portions.expand((portion) => [
                    const Divider(height: 14),
                    _ValueRow('${portion.amount} ${product.stockUnit.symbol} • себестоимость', formatMoney(economics.portionCost(portion))),
                    _ValueRow('Прибыль', formatMoney(economics.portionGrossProfit(portion))),
                    _ValueRow('Маржа', _percent(economics.portionMarginPercent(portion))),
                  ]),
          ],
        ),
      );
}

class _HistoryExpansion extends StatelessWidget {
  const _HistoryExpansion({required this.audit});
  final List<CatalogAuditEntry> audit;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const BaliNavIcon(kind: BaliNavIconKind.history, size: 21),
          title: const Text('История карточки', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(audit.isEmpty ? 'Изменений пока нет' : 'Последних изменений: ${audit.length.clamp(0, 12)}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: audit.isEmpty
              ? [const Padding(padding: EdgeInsets.fromLTRB(14, 0, 14, 10), child: Align(alignment: Alignment.centerLeft, child: Text('История изменений карточки пока пуста.')))]
              : audit.take(12).map((entry) => _AuditLine(entry: entry)).toList(growable: false),
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
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w900 : FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _AuditLine extends StatelessWidget {
  const _AuditLine({required this.entry});
  final CatalogAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final before = entry.beforeData?['bottle_sale_price'];
    final after = entry.afterData?['bottle_sale_price'];
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const BaliNavIcon(kind: BaliNavIconKind.history, size: 19),
      title: Text(before != after ? 'Цена бутылки: ${before ?? '—'} → ${after ?? '—'} BYN' : 'Изменение карточки товара', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${formatDateTime(entry.createdAt)}${entry.actor == null ? '' : ' • ${entry.actor}'}'),
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
        title: Text('Переучесть • ${widget.product.name}'),
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
                  text: 'Будет создана отдельная операция: было → разница → стало. История не стирается.',
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
