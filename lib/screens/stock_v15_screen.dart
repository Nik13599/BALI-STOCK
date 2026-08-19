import 'package:flutter/material.dart';

import '../data/v14_settings_repository.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import 'bulk_product_edit_v14_screen.dart';
import 'product_detail_v14_screen.dart';

class StockV14Screen extends StatefulWidget {
  const StockV14Screen({super.key, required this.controller});
  final V14WarehouseController controller;

  @override
  State<StockV14Screen> createState() => _StockV14ScreenState();
}

class _StockV14ScreenState extends State<StockV14Screen> {
  final V14SettingsRepository _settings = V14SettingsRepository();
  String query = '';
  String? category;
  String? supplierId;
  bool onlyLow = false;
  bool onlyZero = false;
  bool onlyPortion = false;
  bool onlyNoPrice = false;
  bool onlyNoCode = false;
  StockListViewMode viewMode = StockListViewMode.compact;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    _restoreViewMode();
  }

  Future<void> _restoreViewMode() async {
    try {
      final saved = await _settings.loadStockViewMode();
      if (mounted) setState(() => viewMode = saved);
    } catch (_) {}
  }

  Future<void> _setViewMode(StockListViewMode mode) async {
    setState(() => viewMode = mode);
    try {
      await _settings.saveStockViewMode(mode);
    } catch (_) {}
  }

  Map<String, int> get _categoryOrder => {for (final item in widget.controller.categories) item.name: item.sortOrder};

  List<Product> _filtered() {
    final q = query.trim().toLowerCase();
    final list = widget.controller.products.where((p) {
      final meta = widget.controller.metaFor(p);
      if (q.isNotEmpty && !'${p.name} ${p.categoryName} ${p.barcode ?? ''}'.toLowerCase().contains(q)) return false;
      if (category != null && p.categoryName != category) return false;
      if (supplierId != null && !widget.controller.suppliersFor(p).any((s) => s.id == supplierId)) return false;
      if (onlyLow && !p.isLow) return false;
      if (onlyZero && !(p.stockInitialized && p.totalAmount == 0)) return false;
      if (onlyPortion && !meta.portionSale) return false;
      if (onlyNoPrice && p.defaultCost != null && (!meta.sellByBottle || meta.bottleSalePrice != null)) return false;
      if (onlyNoCode && (p.barcode ?? '').trim().isNotEmpty) return false;
      return true;
    }).toList(growable: true);
    final order = _categoryOrder;
    list.sort((a, b) {
      final oa = order[a.categoryName] ?? 1 << 30;
      final ob = order[b.categoryName] ?? 1 << 30;
      if (oa != ob) return oa.compareTo(ob);
      final categoryCompare = a.categoryName.toLowerCase().compareTo(b.categoryName.toLowerCase());
      if (categoryCompare != 0) return categoryCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  List<MapEntry<String, List<Product>>> _groups(List<Product> products) {
    final map = <String, List<Product>>{};
    for (final product in products) {
      map.putIfAbsent(product.categoryName, () => <Product>[]).add(product);
    }
    return map.entries.toList(growable: false);
  }

  Future<void> _exportPdf() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await PdfExportService.exportCurrentStock(categories: widget.controller.categories, products: widget.controller.products);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _open(Product product) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailV14Screen(controller: widget.controller, product: product)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final products = _filtered();
          return Scaffold(
            appBar: AppBar(
              title: const Text('Склад'),
              actions: [
                IconButton(
                  tooltip: 'PDF текущих остатков',
                  onPressed: exporting ? null : _exportPdf,
                  icon: exporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(tooltip: 'Обновить', onPressed: widget.controller.refresh, icon: const BaliNavIcon(kind: BaliNavIconKind.sync, size: 21)),
              ],
            ),
            body: Column(children: [
              _toolbar(products.length),
              Expanded(
                child: widget.controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : products.isEmpty
                        ? const EmptyState(icon: Icons.search_off, title: 'Ничего не найдено', message: 'Измените поиск или фильтры.')
                        : _content(products),
              ),
            ]),
          );
        },
      );

  Widget _toolbar(int count) {
    final categories = widget.controller.categories.map((x) => x.name).toList(growable: false);
    final suppliers = widget.controller.suppliers.where((x) => x.active).toList(growable: true)..sort((a, b) => a.name.compareTo(b.name));
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Название, код, категория', isDense: true),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BulkProductEditV14Screen(controller: widget.controller))),
              icon: const Icon(Icons.edit_note),
              label: const Text('Редактировать'),
            ),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                  items: [const DropdownMenuItem<String?>(value: null, child: Text('Все категории')), ...categories.map((x) => DropdownMenuItem<String?>(value: x, child: Text(x)))],
                  onChanged: (value) => setState(() => category = value),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  initialValue: supplierId,
                  decoration: const InputDecoration(labelText: 'Поставщик', isDense: true),
                  items: [const DropdownMenuItem<String?>(value: null, child: Text('Все поставщики')), ...suppliers.map((x) => DropdownMenuItem<String?>(value: x.id, child: Text(x.name)))],
                  onChanged: (value) => setState(() => supplierId = value),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(label: const Text('Критический'), selected: onlyLow, onSelected: (v) => setState(() => onlyLow = v)),
              const SizedBox(width: 6),
              FilterChip(label: const Text('Нулевой'), selected: onlyZero, onSelected: (v) => setState(() => onlyZero = v)),
              const SizedBox(width: 6),
              FilterChip(label: const Text('Порции'), selected: onlyPortion, onSelected: (v) => setState(() => onlyPortion = v)),
              const SizedBox(width: 6),
              FilterChip(label: const Text('Без цены'), selected: onlyNoPrice, onSelected: (v) => setState(() => onlyNoPrice = v)),
              const SizedBox(width: 6),
              FilterChip(label: const Text('Без кода'), selected: onlyNoCode, onSelected: (v) => setState(() => onlyNoCode = v)),
            ]),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SegmentedButton<StockListViewMode>(
                segments: const [
                  ButtonSegment(value: StockListViewMode.compact, icon: Icon(Icons.view_list), label: Text('Компактно')),
                  ButtonSegment(value: StockListViewMode.detailed, icon: Icon(Icons.view_agenda_outlined), label: Text('Подробно')),
                  ButtonSegment(value: StockListViewMode.table, icon: Icon(Icons.table_chart_outlined), label: Text('Таблица')),
                ],
                selected: {viewMode},
                onSelectionChanged: (value) => _setViewMode(value.first),
              ),
              const SizedBox(width: 10),
              const Chip(avatar: Icon(Icons.sort_by_alpha, size: 18), label: Text('Категории → А–Я')),
              const SizedBox(width: 10),
              Text('$count поз.', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _categoryHeader(String categoryName, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 13, 4, 7),
        child: Row(children: [
          Expanded(child: Text(categoryName.toUpperCase(), style: const TextStyle(color: Color(0xFF39FF6A), fontSize: 19, fontWeight: FontWeight.w900))),
          Text('$count поз.', style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _content(List<Product> products) {
    final groups = _groups(products);
    switch (viewMode) {
      case StockListViewMode.compact:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            for (final group in groups) ...[
              _categoryHeader(group.key, group.value.length),
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < group.value.length; i++) ...[
                    _CompactTile(product: group.value[i], controller: widget.controller, onTap: () => _open(group.value[i])),
                    if (i != group.value.length - 1) const Divider(height: 1),
                  ],
                ]),
              ),
            ],
          ],
        );
      case StockListViewMode.detailed:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            for (final group in groups) ...[
              _categoryHeader(group.key, group.value.length),
              for (final product in group.value)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _DetailedTile(product: product, controller: widget.controller, onTap: () => _open(product))),
            ],
          ],
        );
      case StockListViewMode.table:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            for (final group in groups) ...[
              _categoryHeader(group.key, group.value.length),
              _StockTable(products: group.value, controller: widget.controller, onOpen: _open),
            ],
          ],
        );
    }
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({required this.product, required this.controller, required this.onTap});
  final Product product;
  final V14WarehouseController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = controller.metaFor(product);
    return ListTile(
      onTap: onTap,
      leading: _Thumb(url: meta.imageUrl),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Text(
          product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Не пересчитано',
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.w900, color: product.isLow ? Theme.of(context).colorScheme.error : null),
        ),
      ),
    );
  }
}

class _DetailedTile extends StatelessWidget {
  const _DetailedTile({required this.product, required this.controller, required this.onTap});
  final Product product;
  final V14WarehouseController controller;
  final VoidCallback onTap;

  StockSupplier? _supplier() {
    final links = controller.productSuppliers.where((x) => x.active && x.productKey == controller.productKeyFor(product)).toList(growable: false);
    ProductSupplierLink? link;
    for (final item in links) {
      if (item.isPrimary) { link = item; break; }
    }
    link ??= links.firstOrNull;
    if (link == null) return null;
    return controller.suppliers.where((x) => x.active && x.id == link!.supplierId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final meta = controller.metaFor(product);
    final economics = ProductEconomics(product: product, meta: meta);
    final mainPortion = meta.portions.firstOrNull;
    final supplier = _supplier();
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Thumb(url: meta.imageUrl, large: true),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Остаток не введён', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Wrap(spacing: 16, runSpacing: 5, children: [
                Text('Поставщик: ${supplier?.name ?? 'не назначен'}'),
                Text('Закупка: ${formatMoney(product.defaultCost)}'),
                Text('Продажа: ${meta.sellByBottle ? formatMoney(meta.bottleSalePrice) : '—'}'),
                Text('Маржа: ${_percent(economics.bottleMarginPercent)}'),
                if (mainPortion != null) Text('${mainPortion.amount} ${product.stockUnit.symbol}: ${formatMoney(mainPortion.price)}'),
                Text('Стоимость остатка: ${formatMoney(economics.stockCost)}'),
              ]),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.products, required this.controller, required this.onOpen});
  final List<Product> products;
  final V14WarehouseController controller;
  final ValueChanged<Product> onOpen;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Товар')),
              DataColumn(label: Text('Остаток')),
              DataColumn(label: Text('Поставщик')),
              DataColumn(label: Text('Закупка')),
              DataColumn(label: Text('Продажа')),
              DataColumn(label: Text('Порция')),
              DataColumn(label: Text('Маржа')),
              DataColumn(label: Text('Стоимость остатка')),
            ],
            rows: products.map((product) {
              final meta = controller.metaFor(product);
              final economics = ProductEconomics(product: product, meta: meta);
              final portion = meta.portions.firstOrNull;
              final links = controller.productSuppliers.where((x) => x.active && x.productKey == controller.productKeyFor(product)).toList(growable: false);
              ProductSupplierLink? link;
              for (final item in links) { if (item.isPrimary) { link = item; break; } }
              link ??= links.firstOrNull;
              final supplier = link == null ? null : controller.suppliers.where((x) => x.active && x.id == link!.supplierId).firstOrNull;
              return DataRow(
                onSelectChanged: (_) => onOpen(product),
                cells: [
                  DataCell(Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text(product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : '—')),
                  DataCell(Text(supplier?.name ?? '—')),
                  DataCell(Text(formatMoney(product.defaultCost))),
                  DataCell(Text(meta.sellByBottle ? formatMoney(meta.bottleSalePrice) : '—')),
                  DataCell(Text(portion == null ? '—' : '${portion.amount} / ${formatMoney(portion.price)}')),
                  DataCell(Text(_percent(economics.bottleMarginPercent))),
                  DataCell(Text(formatMoney(economics.stockCost))),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url, this.large = false});
  final String? url;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 46.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: url == null ? const Icon(Icons.inventory_2_outlined) : Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
    );
  }
}

String _percent(double? value) => value == null ? '—' : '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
