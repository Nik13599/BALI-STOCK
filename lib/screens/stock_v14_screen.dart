import 'package:flutter/material.dart';

import '../models.dart';
import '../services/pdf_export_service.dart';
import '../v14_controller.dart';
import '../v14_models.dart';
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
  String query = '';
  String? category;
  String? supplierId;
  bool onlyLow = false;
  bool onlyZero = false;
  bool onlyPortion = false;
  bool onlyNoPrice = false;
  bool onlyNoCode = false;
  StockListViewMode viewMode = StockListViewMode.compact;
  StockSortMode sortMode = StockSortMode.name;
  bool exporting = false;

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

    int compareDouble(double? a, double? b) => (a ?? double.negativeInfinity).compareTo(b ?? double.negativeInfinity);
    list.sort((a, b) {
      final ma = widget.controller.metaFor(a);
      final mb = widget.controller.metaFor(b);
      switch (sortMode) {
        case StockSortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case StockSortMode.category:
          final c = a.categoryName.toLowerCase().compareTo(b.categoryName.toLowerCase());
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case StockSortMode.quantity:
          return b.totalAmount.compareTo(a.totalAmount);
        case StockSortMode.purchasePrice:
          return compareDouble(b.defaultCost, a.defaultCost);
        case StockSortMode.salePrice:
          return compareDouble(mb.bottleSalePrice, ma.bottleSalePrice);
        case StockSortMode.margin:
          return compareDouble(
            ProductEconomics(product: b, meta: mb).bottleMarginPercent,
            ProductEconomics(product: a, meta: ma).bottleMarginPercent,
          );
        case StockSortMode.stockValue:
          return compareDouble(
            ProductEconomics(product: b, meta: mb).stockCost,
            ProductEconomics(product: a, meta: ma).stockCost,
          );
      }
    });
    return list;
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

  void _open(Product p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailV14Screen(controller: widget.controller, product: p)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final list = _filtered();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Склад'),
            actions: [
              IconButton(
                tooltip: 'PDF текущих остатков',
                onPressed: exporting ? null : _exportPdf,
                icon: exporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
              ),
              IconButton(tooltip: 'Обновить', onPressed: widget.controller.refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: Column(
            children: [
              _toolbar(list.length),
              Expanded(
                child: widget.controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? const EmptyState(icon: Icons.search_off, title: 'Ничего не найдено', message: 'Измените поиск или фильтры.')
                        : _content(list),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(int count) {
    final categories = widget.controller.categories.map((x) => x.name).toList(growable: false);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
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
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String?>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Категория', isDense: true),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Все категории')),
                        ...categories.map((x) => DropdownMenuItem<String?>(value: x, child: Text(x))),
                      ],
                      onChanged: (value) => setState(() => category = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String?>(
                      initialValue: supplierId,
                      decoration: const InputDecoration(labelText: 'Поставщик', isDense: true),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Все поставщики')),
                        ...widget.controller.suppliers.where((x) => x.active).map((x) => DropdownMenuItem<String?>(value: x.id, child: Text(x.name))),
                      ],
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
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<StockListViewMode>(
                    segments: const [
                      ButtonSegment(value: StockListViewMode.compact, icon: Icon(Icons.view_list), label: Text('Компактно')),
                      ButtonSegment(value: StockListViewMode.detailed, icon: Icon(Icons.view_agenda_outlined), label: Text('Подробно')),
                      ButtonSegment(value: StockListViewMode.table, icon: Icon(Icons.table_chart_outlined), label: Text('Таблица')),
                    ],
                    selected: {viewMode},
                    onSelectionChanged: (value) => setState(() => viewMode = value.first),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<StockSortMode>(
                  value: sortMode,
                  items: const [
                    DropdownMenuItem(value: StockSortMode.name, child: Text('По названию')),
                    DropdownMenuItem(value: StockSortMode.category, child: Text('По категории')),
                    DropdownMenuItem(value: StockSortMode.quantity, child: Text('По остатку')),
                    DropdownMenuItem(value: StockSortMode.purchasePrice, child: Text('По закупке')),
                    DropdownMenuItem(value: StockSortMode.salePrice, child: Text('По продаже')),
                    DropdownMenuItem(value: StockSortMode.margin, child: Text('По марже')),
                    DropdownMenuItem(value: StockSortMode.stockValue, child: Text('По стоимости остатка')),
                  ],
                  onChanged: (value) => setState(() => sortMode = value ?? sortMode),
                ),
                const SizedBox(width: 10),
                Text('$count поз.', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<Product> list) {
    switch (viewMode) {
      case StockListViewMode.compact:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _CompactTile(product: list[i], controller: widget.controller, onTap: () => _open(list[i])),
        );
      case StockListViewMode.detailed:
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
          itemCount: list.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DetailedTile(product: list[i], controller: widget.controller, onTap: () => _open(list[i])),
          ),
        );
      case StockListViewMode.table:
        return _StockTable(products: list, controller: widget.controller, onOpen: _open);
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
      subtitle: Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w700)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
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

  @override
  Widget build(BuildContext context) {
    final meta = controller.metaFor(product);
    final e = ProductEconomics(product: product, meta: meta);
    final mainPortion = meta.portions.isEmpty ? null : meta.portions.first;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(url: meta.imageUrl, large: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Остаток не введён', style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text('Закупка: ${formatMoney(product.defaultCost)}'),
                        Text('Бутылка: ${meta.sellByBottle ? formatMoney(meta.bottleSalePrice) : '—'}'),
                        Text('Маржа: ${_percent(e.bottleMarginPercent)}'),
                        if (mainPortion != null) Text('${mainPortion.amount} ${product.stockUnit.symbol}: ${formatMoney(mainPortion.price)}'),
                        Text('Остаток по закупке: ${formatMoney(e.stockCost)}'),
                        Text('Потенц. выручка: ${formatMoney(e.potentialBottleRevenue())}'),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
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
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Товар')),
              DataColumn(label: Text('Категория')),
              DataColumn(label: Text('Остаток')),
              DataColumn(label: Text('Закупка')),
              DataColumn(label: Text('Продажа')),
              DataColumn(label: Text('Порция')),
              DataColumn(label: Text('Маржа')),
              DataColumn(label: Text('Стоимость остатка')),
            ],
            rows: products.map((p) {
              final meta = controller.metaFor(p);
              final e = ProductEconomics(product: p, meta: meta);
              final portion = meta.portions.isEmpty ? null : meta.portions.first;
              return DataRow(
                onSelectChanged: (_) => onOpen(p),
                cells: [
                  DataCell(Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  DataCell(Text(p.categoryName)),
                  DataCell(Text(p.stockInitialized ? formatStockParts(p.totalAmount, p.packageSize, p.stockUnit) : '—')),
                  DataCell(Text(formatMoney(p.defaultCost))),
                  DataCell(Text(meta.sellByBottle ? formatMoney(meta.bottleSalePrice) : '—')),
                  DataCell(Text(portion == null ? '—' : '${portion.amount} / ${formatMoney(portion.price)}')),
                  DataCell(Text(_percent(e.bottleMarginPercent))),
                  DataCell(Text(formatMoney(e.stockCost))),
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
