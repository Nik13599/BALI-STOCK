import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../data/remote_purchase_v15_extension.dart';
import '../data/remote_stock_service.dart';
import '../models.dart';
import '../purchase_models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

enum _PurchaseTab { needed, catalog, requests }
enum _PurchaseFilter { all, critical, belowMinimum, belowTarget, ordered }

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final RemoteStockService _remote = RemoteStockService();
  final TextEditingController _search = TextEditingController();
  final Map<int, int> _selectedPackages = <int, int>{};
  final Map<int, String?> _supplierOverrides = <int, String?>{};
  List<StockPurchaseRequest> _requests = const [];
  _PurchaseTab _tab = _PurchaseTab.needed;
  _PurchaseFilter _filter = _PurchaseFilter.all;
  String? _supplierFilter;
  bool _loading = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _key(Product product) => _remote.productKey(
        name: product.name,
        unit: product.stockUnit,
        packageSize: product.packageSize,
      );

  int _packageBase(Product product) => product.stockUnit == StockUnit.piece ? 1 : math.max(product.packageSize, 1);

  Future<void> _reload() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final requests = await _remote.fetchPurchaseRequestsV15();
      await widget.controller.refresh();
      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _openOrderedBase(Product product) {
    final key = _key(product);
    var value = 0;
    for (final request in _requests) {
      if (!request.isOpen) continue;
      for (final line in request.lines) {
        if (line.productKey == key) value += line.outstandingQuantity;
      }
    }
    return value;
  }

  int _recommendedBase(Product product) {
    if (!product.stockInitialized) return 0;
    final desired = product.targetAmount > 0 ? product.targetAmount : product.minimumAmount;
    return math.max(desired - product.totalAmount - _openOrderedBase(product), 0);
  }

  int _recommendedPackages(Product product) {
    final base = _recommendedBase(product);
    if (base <= 0) return 0;
    return (base / _packageBase(product)).ceil();
  }

  int _packages(Product product) => _selectedPackages[product.id] ?? _recommendedPackages(product);

  ProductSupplierLink? _primaryLink(Product product) {
    final key = _key(product);
    final links = widget.controller.productSuppliers.where((x) => x.active && x.productKey == key).toList(growable: false);
    for (final link in links) {
      if (link.isPrimary) return link;
    }
    return links.firstOrNull;
  }

  String? _supplierId(Product product) => _supplierOverrides.containsKey(product.id)
      ? _supplierOverrides[product.id]
      : _primaryLink(product)?.supplierId;

  StockSupplier? _supplierById(String? id) {
    if (id == null) return null;
    return widget.controller.suppliers.where((x) => x.active && x.id == id).firstOrNull;
  }

  ProductSupplierLink? _supplierLink(Product product, String? supplierId) {
    if (supplierId == null) return null;
    final key = _key(product);
    return widget.controller.productSuppliers.where((x) => x.active && x.productKey == key && x.supplierId == supplierId).firstOrNull;
  }

  double? _price(Product product) => _supplierLink(product, _supplierId(product))?.lastPrice ?? product.defaultCost;

  List<StockSupplier> _availableSuppliers(Product product) {
    final key = _key(product);
    final ids = widget.controller.productSuppliers.where((x) => x.active && x.productKey == key).map((x) => x.supplierId).toSet();
    final result = widget.controller.suppliers.where((x) => x.active && ids.contains(x.id)).toList(growable: true);
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  bool _passesQuickFilter(Product product) {
    final current = product.totalAmount;
    final minimum = product.minimumAmount;
    final target = product.targetAmount > 0 ? product.targetAmount : minimum;
    return switch (_filter) {
      _PurchaseFilter.all => true,
      _PurchaseFilter.critical => product.stockInitialized && minimum > 0 && current <= ((minimum + 1) ~/ 2),
      _PurchaseFilter.belowMinimum => product.stockInitialized && minimum > 0 && current <= minimum,
      _PurchaseFilter.belowTarget => product.stockInitialized && target > 0 && current < target,
      _PurchaseFilter.ordered => _openOrderedBase(product) > 0,
    };
  }

  List<Product> _visibleProducts() {
    final query = _search.text.trim().toLowerCase();
    final categoryOrder = {for (final category in widget.controller.categories) category.name: category.sortOrder};
    final result = widget.controller.products.where((product) {
      if (!product.active) return false;
      if (_tab == _PurchaseTab.needed && !product.stockInitialized) return false;
      if (_tab == _PurchaseTab.needed && _recommendedBase(product) <= 0 && _packages(product) <= 0) return false;
      if (!_passesQuickFilter(product)) return false;
      if (_supplierFilter != null && _supplierId(product) != _supplierFilter) return false;
      if (query.isNotEmpty) {
        final supplier = _supplierById(_supplierId(product))?.name ?? '';
        final haystack = '${product.name} ${product.categoryName} ${product.barcode ?? ''} $supplier'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList(growable: true);
    result.sort((a, b) {
      final ca = categoryOrder[a.categoryName] ?? 1 << 30;
      final cb = categoryOrder[b.categoryName] ?? 1 << 30;
      if (ca != cb) return ca.compareTo(cb);
      final byCategory = a.categoryName.toLowerCase().compareTo(b.categoryName.toLowerCase());
      if (byCategory != 0) return byCategory;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<Product> _selectedProducts() => widget.controller.products.where((p) => p.active && _packages(p) > 0).toList(growable: false);

  double _estimatedTotal() {
    var total = 0.0;
    for (final product in _selectedProducts()) {
      final price = _price(product);
      if (price != null) total += price * _packages(product);
    }
    return total;
  }

  Future<String?> _authorize() async {
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return null;
    try {
      await _remote.authorize(pin);
      await widget.controller.setOperationSessionPin(pin);
      return pin;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return null;
    }
  }

  List<PurchaseSuggestion> _pdfItems() => _selectedProducts().map((product) {
        return PurchaseSuggestion(
          productKey: _key(product),
          name: product.name,
          categoryName: product.categoryName,
          stockUnit: product.stockUnit,
          packageSize: product.packageSize,
          currentQuantity: product.stockInitialized ? product.totalAmount : 0,
          minimumAmount: product.minimumAmount,
          targetAmount: product.targetAmount,
          suggestedQuantity: _packages(product) * _packageBase(product),
          preferredSupplier: _supplierId(product),
          lastPrice: _price(product),
          currency: product.costCurrency,
        );
      }).toList(growable: false);

  Future<void> _exportPdf() async {
    final items = _pdfItems();
    if (items.isEmpty) return;
    try {
      await PdfExportService.exportPurchaseList(items: items, suppliers: widget.controller.suppliers);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<bool?> _preview(List<Product> selected) {
    final grouped = <String, List<Product>>{};
    for (final product in selected) {
      final supplierId = _supplierId(product);
      if (supplierId != null) grouped.putIfAbsent(supplierId, () => <Product>[]).add(product);
    }
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Проверить заявки'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in grouped.entries) ...[
                  Text((_supplierById(entry.key)?.name ?? 'Поставщик').toUpperCase(), style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  for (final product in entry.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('${_packages(product)} ${product.stockUnit.packageLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  const SizedBox(height: 12),
                ],
                Text('Ориентировочная сумма: ${formatMoney(_estimatedTotal())}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Изменить')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ПОДТВЕРДИТЬ ЗАЯВКИ')),
        ],
      ),
    );
  }

  Future<void> _createRequests() async {
    final selected = _selectedProducts();
    if (selected.isEmpty || _creating) return;
    final missingSupplier = selected.where((product) => _supplierId(product) == null).toList(growable: false);
    if (missingSupplier.isNotEmpty) {
      showErrorSnack(context, 'У ${missingSupplier.length} выбранных позиций не назначен поставщик. Назначьте его в карточке товара или выберите здесь.');
      return;
    }
    if (await _preview(selected) != true || !mounted) return;
    final pin = await _authorize();
    if (!mounted || pin == null) return;
    final employee = await showTextValueDialog(context, 'Кто формирует заявки?', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      final groups = <String, List<Product>>{};
      for (final product in selected) {
        groups.putIfAbsent(_supplierId(product)!, () => <Product>[]).add(product);
      }
      for (final entry in groups.entries) {
        final response = await _remote.createPurchaseRequestV15(
          pin: pin,
          employee: employee.trim(),
          supplierId: entry.key,
          comment: 'Сформировано в BALI STOCK.',
          lines: entry.value.map((product) => PurchaseRequestDraftLine(
            productKey: _key(product),
            suggestedQuantity: _recommendedBase(product),
            requestedQuantity: _packages(product) * _packageBase(product),
            unitCost: _price(product),
          )).toList(growable: false),
        );
        final id = '${response['id'] ?? ''}';
        if (id.isNotEmpty) {
          await _remote.setPurchaseRequestStatus(pin: pin, id: id, status: 'confirmed', employee: employee.trim());
        }
      }
      _selectedPackages.clear();
      await _reload();
      if (mounted) {
        setState(() => _tab = _PurchaseTab.requests);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Создано заявок: ${groups.length}. Товары сгруппированы по поставщикам.')));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _setRequestStatus(StockPurchaseRequest request, String status) async {
    final pin = await _authorize();
    if (!mounted || pin == null) return;
    final employee = await showTextValueDialog(context, 'Изменить статус заявки', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await _remote.setPurchaseRequestStatus(pin: pin, id: request.id, status: status, employee: employee.trim());
      await _reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Закупки'),
            actions: [IconButton(onPressed: _loading ? null : _reload, tooltip: 'Обновить', icon: const BaliNavIcon(kind: BaliNavIconKind.sync, size: 21))],
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 10, compact ? 12 : 20, 110),
                  children: [
                    _tabs(),
                    const SizedBox(height: 12),
                    if (_tab == _PurchaseTab.requests)
                      _requestsView()
                    else ...[
                      _summary(),
                      const SizedBox(height: 10),
                      _filters(),
                      const SizedBox(height: 10),
                      _catalog(),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      );

  Widget _tabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_PurchaseTab>(
          segments: const [
            ButtonSegment(value: _PurchaseTab.needed, label: Text('Нужно заказать'), icon: BaliNavIcon(kind: BaliNavIconKind.purchases, size: 18)),
            ButtonSegment(value: _PurchaseTab.catalog, label: Text('Все товары'), icon: BaliNavIcon(kind: BaliNavIconKind.stock, size: 18)),
            ButtonSegment(value: _PurchaseTab.requests, label: Text('Заявки'), icon: BaliNavIcon(kind: BaliNavIconKind.history, size: 18)),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _tab = value.first),
        ),
      );

  Widget _summary() {
    final selected = _selectedProducts();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Заявка на закупку', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('${selected.length} поз. • ≈ ${formatMoney(_estimatedTotal())}', style: Theme.of(context).textTheme.bodyMedium),
          ]);
          final actions = Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: selected.isEmpty ? null : _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
            FilledButton.icon(onPressed: selected.isEmpty || _creating ? null : _createRequests, icon: const BaliNavIcon(kind: BaliNavIconKind.purchases, active: true, size: 19), label: Text(_creating ? 'СОЗДАЮ…' : 'СФОРМИРОВАТЬ ЗАЯВКИ')),
          ]);
          return narrow ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 10), actions]) : Row(children: [Expanded(child: info), actions]);
        }),
      ),
    );
  }

  Widget _filters() {
    final suppliers = widget.controller.suppliers.where((x) => x.active).toList(growable: true)..sort((a, b) => a.name.compareTo(b.name));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Товар, категория, код или поставщик',
              suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.clear)),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String?>(
                initialValue: _supplierFilter,
                decoration: const InputDecoration(labelText: 'Поставщик', isDense: true),
                items: [const DropdownMenuItem<String?>(value: null, child: Text('Все поставщики')), ...suppliers.map((x) => DropdownMenuItem<String?>(value: x.id, child: Text(x.name)))],
                onChanged: (value) => setState(() => _supplierFilter = value),
              ),
            ),
            const SizedBox(width: 8),
            _filterChip('Все', _PurchaseFilter.all),
            _filterChip('Критично', _PurchaseFilter.critical),
            _filterChip('Ниже минимума', _PurchaseFilter.belowMinimum),
            _filterChip('Ниже цели', _PurchaseFilter.belowTarget),
            _filterChip('Уже заказано', _PurchaseFilter.ordered),
          ])),
        ]),
      ),
    );
  }

  Widget _filterChip(String label, _PurchaseFilter value) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: _filter == value, onSelected: (_) => setState(() => _filter = value)),
      );

  Widget _catalog() {
    final products = _visibleProducts();
    if (products.isEmpty) {
      final hasUninitialized = widget.controller.products.any((product) => product.active && !product.stockInitialized);
      final message = _tab == _PurchaseTab.needed && hasUninitialized
          ? 'Автоматические рекомендации появятся после первичного переучёта. Полный ассортимент уже доступен во вкладке «Все товары».'
          : 'Измените фильтры или откройте «Все товары».';
      return EmptyState(icon: Icons.shopping_cart_outlined, title: 'Нет позиций', message: message);
    }
    final groups = <String, List<Product>>{};
    for (final product in products) {
      groups.putIfAbsent(product.categoryName, () => <Product>[]).add(product);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 7),
          child: Text('${entry.key.toUpperCase()} • ${entry.value.length}', style: const TextStyle(color: Color(0xFF39FF6A), fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        for (final product in entry.value) _productCard(product),
      ],
    ]);
  }

  Widget _productCard(Product product) {
    final supplierId = _supplierId(product);
    final supplier = _supplierById(supplierId);
    final available = _availableSuppliers(product);
    final ordered = _openOrderedBase(product);
    final recommended = _recommendedPackages(product);
    final packages = _packages(product);
    final price = _price(product);
    final estimate = price == null ? null : price * packages;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(supplier?.name ?? 'Поставщик не назначен', style: TextStyle(fontWeight: FontWeight.w700, color: supplier == null ? Theme.of(context).colorScheme.error : null)),
            ])),
            if (price != null) Text(formatMoney(price, product.costCurrency), style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
          if (available.length > 1) ...[
            const SizedBox(height: 7),
            DropdownButtonFormField<String>(
              initialValue: supplierId,
              decoration: const InputDecoration(labelText: 'Поставщик для этой заявки', isDense: true),
              items: available.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(growable: false),
              onChanged: (value) => setState(() => _supplierOverrides[product.id] = value),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 5, children: [
            Text('Сейчас: ${product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'остаток не введён'}'),
            Text('Минимум: ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}'),
            if (product.targetAmount > 0) Text('Цель: ${formatTotalAmount(product.targetAmount, product.stockUnit)}'),
            Text('Уже заказано: ${ordered == 0 ? '0' : formatStockParts(ordered, product.packageSize, product.stockUnit)}'),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 460;
            final recommendation = Text(
              product.stockInitialized
                  ? 'Рекомендуется: $recommended ${product.stockUnit.packageLabel}'
                  : 'Рекомендация — после первичного переучёта',
              style: const TextStyle(fontWeight: FontWeight.w900),
            );
            final counter = _Counter(
              value: packages,
              unit: product.stockUnit.packageLabel,
              onChanged: (value) => setState(() => _selectedPackages[product.id] = value),
            );
            return narrow ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [recommendation, const SizedBox(height: 7), counter]) : Row(children: [Expanded(child: recommendation), counter]);
          }),
          if (estimate != null && packages > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('≈ ${formatMoney(estimate, product.costCurrency)}', textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }

  Widget _requestsView() {
    if (_loading && _requests.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    if (_requests.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'Заявок пока нет', message: 'Сформируйте первую заявку из каталога закупок.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final request in _requests) _requestCard(request),
    ]);
  }

  Widget _requestCard(StockPurchaseRequest request) {
    final supplier = _supplierById(request.supplierId);
    var requested = 0;
    var received = 0;
    double estimated = 0;
    for (final line in request.lines) {
      requested += line.requestedQuantity;
      received += line.receivedQuantity;
      if (line.unitCost != null) {
        final product = widget.controller.products.where((p) => _key(p) == line.productKey).firstOrNull;
        final base = product == null ? 1 : _packageBase(product);
        estimated += line.unitCost! * (line.requestedQuantity / base);
      }
    }
    final progress = requested <= 0 ? 0.0 : (received / requested).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.shortNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              Text(supplier?.name ?? 'Поставщик не указан', style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w800)),
            ])),
            Chip(label: Text(request.statusLabel, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          Text('${request.lines.length} поз. • ${formatDateTime(request.createdAt)} • ≈ ${formatMoney(estimated)}'),
          if (request.status == 'partial' || request.status == 'completed') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text('Принято ${(progress * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          ...request.lines.take(8).map((line) {
            final product = widget.controller.products.where((p) => _key(p) == line.productKey).firstOrNull;
            final name = product?.name ?? line.productKey;
            final requestedText = product == null ? '${line.requestedQuantity}' : formatStockParts(line.requestedQuantity, product.packageSize, product.stockUnit);
            final outstandingText = product == null ? '${line.outstandingQuantity}' : formatStockParts(line.outstandingQuantity, product.packageSize, product.stockUnit);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(line.outstandingQuantity > 0 ? '$requestedText • осталось $outstandingText' : '$requestedText • принято', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            );
          }),
          if (request.lines.length > 8) Text('Ещё ${request.lines.length - 8} поз.', style: Theme.of(context).textTheme.bodySmall),
          if (request.status == 'confirmed') ...[
            const SizedBox(height: 9),
            FilledButton.tonal(onPressed: () => _setRequestStatus(request, 'sent'), child: const Text('ОТМЕТИТЬ КАК ОТПРАВЛЕННУЮ')),
          ],
          if (request.isOpen && request.status != 'partial')
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _setRequestStatus(request, 'cancelled'), child: const Text('Отменить заявку'))),
        ]),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.unit, required this.onChanged});
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(onPressed: value <= 0 ? null : () => onChanged(value - 1), icon: const Icon(Icons.remove)),
        SizedBox(width: 74, child: Text('$value $unit', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
        IconButton.filled(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add)),
      ]);
}
