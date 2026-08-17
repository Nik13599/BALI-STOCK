import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';
import 'delivery_screen.dart' show showSupplierDialog;

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _authorize() async {
    if (widget.controller.hasOperationSession && widget.controller.sharedOnline) return true;
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return false;
    try {
      await widget.controller.setOperationSessionPin(pin);
      return widget.controller.sharedOnline;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }

  Future<void> _writeOff() async {
    if (!await _authorize() || !mounted) return;
    final result = await showWriteOffDialog(context, widget.controller);
    if (result == null || !mounted) return;
    try {
      await widget.controller.writeOff(
        employee: result.employee,
        reason: result.reason,
        lines: result.lines,
        locationId: result.locationId,
        comment: result.comment,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Списание проведено и видно всем устройствам.')));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _transfer() async {
    if (!await _authorize() || !mounted) return;
    final result = await showTransferDialog(context, widget.controller);
    if (result == null || !mounted) return;
    try {
      await widget.controller.transfer(
        employee: result.employee,
        sourceLocationId: result.sourceId,
        targetLocationId: result.targetId,
        lines: result.lines,
        comment: result.comment,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Перемещение проведено. Общий остаток не изменился, место хранения обновлено.')));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _addLocation() async {
    if (!await _authorize() || !mounted) return;
    final name = await showTextValueDialog(context, 'Новое место хранения', 'Например: Бар 1, Бар 2, Кухня, Резерв');
    if (name == null || name.trim().isEmpty) return;
    try {
      await widget.controller.addLocation(name.trim());
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _addSupplier() async {
    if (!await _authorize() || !mounted) return;
    await showSupplierDialog(context, widget.controller);
  }

  Future<void> _editProduct(Product product) async {
    if (!await _authorize() || !mounted) return;
    await showProductControlDialog(context, widget.controller, product);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Контроль склада'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  child: Chip(
                    avatar: Icon(widget.controller.sharedOnline ? Icons.cloud_done : Icons.cloud_off, size: 18),
                    label: Text(widget.controller.sharedOnline ? 'Синхронизировано' : 'Офлайн'),
                  ),
                ),
              ),
              IconButton(onPressed: widget.controller.refresh, tooltip: 'Обновить', icon: const Icon(Icons.refresh)),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Закупки'),
                Tab(icon: Icon(Icons.swap_horiz), text: 'Движения'),
                Tab(icon: Icon(Icons.business_outlined), text: 'Поставщики'),
                Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Товары'),
                Tab(icon: Icon(Icons.analytics_outlined), text: 'Аналитика'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _PurchasesTab(controller: widget.controller),
              _MovementsTab(controller: widget.controller, onWriteOff: _writeOff, onTransfer: _transfer, onAddLocation: _addLocation),
              _SuppliersTab(controller: widget.controller, onAdd: _addSupplier),
              _ProductsTab(controller: widget.controller, search: _search, onEdit: _editProduct),
              _AnalyticsTab(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab({required this.controller});
  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.purchaseSuggestions;
    if (items.isEmpty) {
      return const EmptyState(icon: Icons.check_circle_outline, title: 'Закупка сейчас не требуется', message: 'Все инициализированные позиции выше минимального остатка.');
    }
    final suppliers = {for (final supplier in controller.suppliers) supplier.id: supplier.name};
    final grouped = <String, List<PurchaseSuggestion>>{};
    for (final item in items) {
      final name = item.preferredSupplier == null ? 'Поставщик не назначен' : (suppliers[item.preferredSupplier] ?? 'Неизвестный поставщик');
      grouped.putIfAbsent(name, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InfoBanner(icon: Icons.auto_awesome, text: 'Список формируется автоматически: если остаток достиг минимума, система предлагает довести позицию до целевого остатка. Если цель не задана — до минимума.'),
        const SizedBox(height: 16),
        for (final entry in grouped.entries) ...[
          Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF39FF6A))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  Builder(builder: (context) {
                    final item = entry.value[i];
                    final packages = item.stockUnit == StockUnit.piece ? item.suggestedQuantity : (item.suggestedQuantity / item.packageSize).ceil();
                    return ListTile(
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${item.categoryName} • сейчас ${formatStockParts(item.currentQuantity, item.packageSize, item.stockUnit)} • минимум ${formatMinimumAmount(item.minimumAmount, item.stockUnit)}${item.targetAmount > 0 ? ' • цель ${formatMinimumAmount(item.targetAmount, item.stockUnit)}' : ''}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Заказать: $packages ${item.stockUnit.packageLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          if (item.lastPrice != null) Text('≈ ${formatMoney(item.lastPrice! * packages, item.currency)}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    );
                  }),
                  if (i != entry.value.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _MovementsTab extends StatelessWidget {
  const _MovementsTab({required this.controller, required this.onWriteOff, required this.onTransfer, required this.onAddLocation});
  final WarehouseController controller;
  final VoidCallback onWriteOff;
  final VoidCallback onTransfer;
  final VoidCallback onAddLocation;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(onPressed: onWriteOff, icon: const Icon(Icons.remove_circle_outline), label: const Text('Списать товар')),
            FilledButton.tonalIcon(onPressed: controller.locations.length < 2 ? null : onTransfer, icon: const Icon(Icons.swap_horiz), label: const Text('Переместить')),
            OutlinedButton.icon(onPressed: onAddLocation, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Добавить место')),
          ],
        ),
        const SizedBox(height: 22),
        Text('Места хранения', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < controller.locations.length; i++) ...[
                ListTile(
                  leading: Icon(controller.locations[i].isPrimary ? Icons.warehouse : Icons.inventory_2_outlined),
                  title: Text(controller.locations[i].name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(controller.locations[i].isPrimary ? 'Основное место хранения' : 'Дополнительное место хранения'),
                  trailing: controller.locations[i].isPrimary ? const Chip(label: Text('Основной')) : null,
                ),
                if (i != controller.locations.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Последние движения', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        for (final operation in controller.operations.take(20))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Icon(_operationIcon(operation.type))),
              title: Text('${operation.type.displayName} №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${formatDateTime(operation.createdAt)}${operation.employeeName == null ? '' : ' • ${operation.employeeName}'}'),
              trailing: Text(_operationTotal(operation), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab({required this.controller, required this.onAdd});
  final WarehouseController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_business), label: const Text('Новый поставщик'))),
        const SizedBox(height: 12),
        if (controller.suppliers.isEmpty)
          const EmptyState(icon: Icons.business_outlined, title: 'Поставщиков пока нет', message: 'Добавьте первого поставщика. Одну складскую позицию можно привязать к нескольким поставщикам.')
        else
          for (final supplier in controller.suppliers)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.business_outlined)),
                title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text([
                  if (supplier.contactPerson?.isNotEmpty == true) supplier.contactPerson!,
                  if (supplier.phone?.isNotEmpty == true) supplier.phone!,
                  if (supplier.email?.isNotEmpty == true) supplier.email!,
                ].join(' • ').isEmpty ? 'Контакты не указаны' : [
                  if (supplier.contactPerson?.isNotEmpty == true) supplier.contactPerson!,
                  if (supplier.phone?.isNotEmpty == true) supplier.phone!,
                  if (supplier.email?.isNotEmpty == true) supplier.email!,
                ].join(' • ')),
                trailing: Text('${controller.productSuppliers.where((link) => link.supplierId == supplier.id && link.active).length} поз.'),
              ),
            ),
      ],
    );
  }
}

class _ProductsTab extends StatefulWidget {
  const _ProductsTab({required this.controller, required this.search, required this.onEdit});
  final WarehouseController controller;
  final TextEditingController search;
  final ValueChanged<Product> onEdit;

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  @override
  void initState() {
    super.initState();
    widget.search.addListener(_changed);
  }

  @override
  void dispose() {
    widget.search.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final q = widget.search.text.trim().toLowerCase();
    final products = widget.controller.products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.categoryName.toLowerCase().contains(q)).toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(controller: widget.search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Поиск товара / категории')),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final suppliers = widget.controller.suppliersFor(product);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${product.categoryName} • ${product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'остаток не введён'}\nМинимум ${formatMinimumAmount(product.minimumAmount, product.stockUnit)} • цель ${formatMinimumAmount(product.targetAmount, product.stockUnit)} • поставщиков ${suppliers.length}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(onPressed: () => showProductHistory(context, widget.controller, product), tooltip: 'История позиции', icon: const Icon(Icons.history)),
                      IconButton(onPressed: () => widget.onEdit(product), tooltip: 'Параметры контроля', icon: const Icon(Icons.tune)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab({required this.controller});
  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.analytics;
    final initialized = controller.products.where((p) => p.stockInitialized).toList(growable: false);
    final value = initialized.fold<double>(0, (sum, product) {
      final price = product.defaultCost;
      if (price == null || product.packageSize <= 0) return sum;
      return sum + (product.totalAmount / product.packageSize) * price;
    });
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(label: 'Операций / ${data.periodDays} дн.', value: '${data.operations}', icon: Icons.receipt_long_outlined),
            MetricCard(label: 'Переучётов', value: '${data.stocktakes}', icon: Icons.fact_check_outlined),
            MetricCard(label: 'Списаний', value: '${data.writeoffs}', icon: Icons.remove_circle_outline),
            MetricCard(label: 'Стоимость склада', value: formatMoney(value), icon: Icons.payments_outlined),
            MetricCard(label: 'Среднее время', value: formatDurationSeconds(data.averageStocktakeSeconds), icon: Icons.timer_outlined),
            MetricCard(label: 'Самый быстрый', value: formatDurationSeconds(data.fastestStocktakeSeconds), icon: Icons.bolt_outlined),
            MetricCard(label: 'Самый долгий', value: formatDurationSeconds(data.longestStocktakeSeconds), icon: Icons.hourglass_bottom),
          ],
        ),
        const SizedBox(height: 24),
        Text('Наибольшие расхождения за период', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (data.largestVariances.isEmpty)
          const Text('Пока недостаточно данных.')
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < data.largestVariances.length; i++) ...[
                  ListTile(
                    title: Text('${data.largestVariances[i]['product_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: Text('${data.largestVariances[i]['variance'] ?? 0}', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.error)),
                  ),
                  if (i != data.largestVariances.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> showProductHistory(BuildContext context, WarehouseController controller, Product product) async {
  final rows = <({StockOperation operation, StockOperationLine line})>[];
  for (final operation in controller.operations) {
    for (final line in operation.lines) {
      if (line.productId == product.id || line.productName.toLowerCase() == product.name.toLowerCase()) rows.add((operation: operation, line: line));
    }
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)), title: Text('История: ${product.name}')),
        body: rows.isEmpty
            ? const EmptyState(icon: Icons.history, title: 'Движений пока нет', message: 'Для этой позиции ещё нет завершённых операций.')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_operationIcon(row.operation.type))),
                      title: Text('${row.operation.type.displayName} • ${formatDateTime(row.operation.createdAt)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Было: ${formatStockParts(row.line.beforeTotalMl, row.line.bottleMl, row.line.stockUnit)}\nИзменение: ${row.line.changeTotalMl >= 0 ? '+' : ''}${formatTotalAmount(row.line.changeTotalMl.abs(), row.line.stockUnit)} • стало: ${formatStockParts(row.line.afterTotalMl, row.line.bottleMl, row.line.stockUnit)}'),
                    ),
                  );
                },
              ),
      ),
    ),
  );
}

Future<void> showProductControlDialog(BuildContext context, WarehouseController controller, Product product) async {
  final minimum = TextEditingController(text: '${product.minimumAmount}');
  final target = TextEditingController(text: '${product.targetAmount}');
  final recheck = TextEditingController(text: '${product.varianceRecheckAmount}');
  final barcode = TextEditingController(text: product.barcode ?? '');
  final cost = TextEditingController(text: product.defaultCost?.toStringAsFixed(2) ?? '');
  final employee = TextEditingController();
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final linked = controller.productSuppliers.where((link) {
          final key = '${product.name.trim().toLowerCase()}|${product.stockUnit.dbValue}|${product.packageSize}';
          return link.productKey == key && link.active;
        }).toList(growable: false);
        return AlertDialog(
          title: Text('Контроль: ${product.name}'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: employee, decoration: const InputDecoration(labelText: 'Кто меняет настройки, ФИО *')),
                  const SizedBox(height: 12),
                  TwoFields(
                    first: IntegerField(controller: minimum, label: 'Минимальный остаток, ${product.stockUnit.symbol}', min: 0),
                    second: IntegerField(controller: target, label: 'Целевой остаток, ${product.stockUnit.symbol}', min: 0),
                  ),
                  const SizedBox(height: 12),
                  TwoFields(
                    first: IntegerField(controller: recheck, label: 'Повторный пересчёт при расхождении от, ${product.stockUnit.symbol}', min: 0),
                    second: TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Закупочная цена, BYN')),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Штрихкод / QR-код'))),
                      if (Platform.isAndroid || Platform.isIOS) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Сканировать код',
                          onPressed: () async {
                            final value = await _scanBarcode(dialogContext);
                            if (value != null) barcode.text = value;
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Text('Поставщики (${linked.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                      TextButton.icon(
                        onPressed: () async {
                          await showLinkSupplierDialog(dialogContext, controller, product);
                          setState(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Привязать'),
                      ),
                    ],
                  ),
                  if (linked.isEmpty)
                    const Text('Поставщики не привязаны.')
                  else
                    for (final link in linked)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(controller.suppliers.where((s) => s.id == link.supplierId).map((s) => s.name).firstOrNull ?? 'Поставщик'),
                        subtitle: Text('${link.isPrimary ? 'Основной • ' : ''}${link.supplierSku == null ? '' : 'арт. ${link.supplierSku} • '}${formatMoney(link.lastPrice, link.currency)}'),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Закрыть')),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (employee.text.trim().isEmpty) {
                        showErrorSnack(dialogContext, 'Укажите ФИО');
                        return;
                      }
                      final minValue = int.tryParse(minimum.text);
                      final targetValue = int.tryParse(target.text);
                      final recheckValue = int.tryParse(recheck.text);
                      final price = cost.text.trim().isEmpty ? null : double.tryParse(cost.text.replaceAll(',', '.'));
                      if (minValue == null || targetValue == null || recheckValue == null || minValue < 0 || targetValue < 0 || recheckValue < 0 || (cost.text.trim().isNotEmpty && price == null)) {
                        showErrorSnack(dialogContext, 'Проверьте числовые поля');
                        return;
                      }
                      setState(() => saving = true);
                      try {
                        await controller.updateProductControl(
                          product: product,
                          employee: employee.text.trim(),
                          minimumAmount: minValue,
                          targetAmount: targetValue,
                          varianceRecheckAmount: recheckValue,
                          barcode: barcode.text.trim(),
                          defaultCost: price,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) showErrorSnack(dialogContext, e);
                        setState(() => saving = false);
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Сохранить'),
            ),
          ],
        );
      },
    ),
  );
  minimum.dispose();
  target.dispose();
  recheck.dispose();
  barcode.dispose();
  cost.dispose();
  employee.dispose();
}

Future<void> showLinkSupplierDialog(BuildContext context, WarehouseController controller, Product product) async {
  if (controller.suppliers.isEmpty) {
    showErrorSnack(context, 'Сначала добавьте поставщика');
    return;
  }
  String supplierId = controller.suppliers.first.id;
  final sku = TextEditingController();
  final price = TextEditingController();
  var primary = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Привязать поставщика'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: supplierId,
                decoration: const InputDecoration(labelText: 'Поставщик'),
                items: controller.suppliers.where((s) => s.active).map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => supplierId = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: sku, decoration: const InputDecoration(labelText: 'Артикул у поставщика')),
              const SizedBox(height: 12),
              TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Последняя цена, BYN')),
              SwitchListTile(value: primary, onChanged: (value) => setState(() => primary = value), title: const Text('Основной поставщик')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              try {
                await controller.linkSupplier(
                  product: product,
                  supplierId: supplierId,
                  supplierSku: sku.text.trim().isEmpty ? null : sku.text.trim(),
                  lastPrice: price.text.trim().isEmpty ? null : double.tryParse(price.text.replaceAll(',', '.')),
                  isPrimary: primary,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) showErrorSnack(dialogContext, e);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  sku.dispose();
  price.dispose();
}

Future<String?> _scanBarcode(BuildContext context) async {
  String? result;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (pageContext) => Scaffold(
      appBar: AppBar(title: const Text('Сканировать штрихкод'), leading: IconButton(onPressed: () => Navigator.pop(pageContext), icon: const Icon(Icons.close))),
      body: MobileScanner(
        onDetect: (capture) {
          if (result != null || capture.barcodes.isEmpty) return;
          final value = capture.barcodes.first.rawValue;
          if (value == null || value.isEmpty) return;
          result = value;
          Navigator.pop(pageContext);
        },
      ),
    ),
  ));
  return result;
}

Future<_WriteOffResult?> showWriteOffDialog(BuildContext context, WarehouseController controller) async {
  final employee = TextEditingController();
  final comment = TextEditingController();
  const reasons = ['Бой', 'Пролив', 'Испорчено', 'Просрочено', 'Комплимент гостю', 'Служебное использование', 'Другое'];
  var reason = reasons.first;
  var locationId = controller.primaryLocation?.id;
  final lines = <int, DeliveryDraftLine>{};
  return showDialog<_WriteOffResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Списание товара'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: employee, decoration: const InputDecoration(labelText: 'Сотрудник, ФИО *')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(initialValue: reason, decoration: const InputDecoration(labelText: 'Причина *'), items: reasons.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (value) { if (value != null) setState(() => reason = value); }),
                const SizedBox(height: 10),
                if (controller.locations.isNotEmpty)
                  DropdownButtonFormField<String>(initialValue: locationId, decoration: const InputDecoration(labelText: 'Откуда списать'), items: controller.locations.where((l) => l.active).map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(), onChanged: (value) => setState(() => locationId = value)),
                if (controller.locations.isNotEmpty) const SizedBox(height: 10),
                TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий')),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: () async {
                  final line = await _quantityLineDialog(dialogContext, controller.products, title: 'Что списать');
                  if (line != null) setState(() => lines[line.product.id] = line);
                }, icon: const Icon(Icons.add), label: const Text('Добавить позицию'))),
                for (final line in lines.values) ListTile(title: Text(line.product.name), subtitle: Text(formatStockParts(line.addedMl, line.product.packageSize, line.product.stockUnit)), trailing: IconButton(onPressed: () => setState(() => lines.remove(line.product.id)), icon: const Icon(Icons.delete_outline))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (employee.text.trim().isEmpty || lines.isEmpty || locationId == null) { showErrorSnack(dialogContext, 'Заполните ФИО и добавьте позиции'); return; }
            Navigator.pop(dialogContext, _WriteOffResult(employee.text.trim(), reason, lines.values.toList(growable: false), locationId!, comment.text.trim().isEmpty ? null : comment.text.trim()));
          }, child: const Text('Провести списание')),
        ],
      ),
    ),
  ).whenComplete(() { employee.dispose(); comment.dispose(); });
}

Future<_TransferResult?> showTransferDialog(BuildContext context, WarehouseController controller) async {
  if (controller.locations.length < 2) return null;
  final employee = TextEditingController();
  final comment = TextEditingController();
  var source = controller.primaryLocation?.id ?? controller.locations.first.id;
  var target = controller.locations.firstWhere((l) => l.id != source).id;
  final lines = <int, DeliveryDraftLine>{};
  return showDialog<_TransferResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Перемещение между складами'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: employee, decoration: const InputDecoration(labelText: 'Сотрудник, ФИО *')),
                const SizedBox(height: 10),
                TwoFields(
                  first: DropdownButtonFormField<String>(initialValue: source, decoration: const InputDecoration(labelText: 'Откуда'), items: controller.locations.where((l) => l.active).map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(), onChanged: (value) { if (value != null) setState(() { source = value; if (target == source) target = controller.locations.firstWhere((l) => l.id != source).id; }); }),
                  second: DropdownButtonFormField<String>(initialValue: target, decoration: const InputDecoration(labelText: 'Куда'), items: controller.locations.where((l) => l.active && l.id != source).map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(), onChanged: (value) { if (value != null) setState(() => target = value); }),
                ),
                const SizedBox(height: 10),
                TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий')),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(onPressed: () async {
                  final line = await _quantityLineDialog(dialogContext, controller.products, title: 'Что переместить');
                  if (line != null) setState(() => lines[line.product.id] = line);
                }, icon: const Icon(Icons.add), label: const Text('Добавить позицию'))),
                for (final line in lines.values) ListTile(title: Text(line.product.name), subtitle: Text(formatStockParts(line.addedMl, line.product.packageSize, line.product.stockUnit)), trailing: IconButton(onPressed: () => setState(() => lines.remove(line.product.id)), icon: const Icon(Icons.delete_outline))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (employee.text.trim().isEmpty || lines.isEmpty || source == target) { showErrorSnack(dialogContext, 'Проверьте ФИО, склады и позиции'); return; }
            Navigator.pop(dialogContext, _TransferResult(employee.text.trim(), source, target, lines.values.toList(growable: false), comment.text.trim().isEmpty ? null : comment.text.trim()));
          }, child: const Text('Переместить')),
        ],
      ),
    ),
  ).whenComplete(() { employee.dispose(); comment.dispose(); });
}

Future<DeliveryDraftLine?> _quantityLineDialog(BuildContext context, List<Product> products, {required String title}) async {
  if (products.isEmpty) return null;
  var productId = products.first.id;
  final whole = TextEditingController(text: '0');
  final extra = TextEditingController(text: '0');
  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(initialValue: productId, isExpanded: true, decoration: const InputDecoration(labelText: 'Позиция'), items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name}'))).toList(), onChanged: (value) { if (value != null) setState(() { productId = value; whole.text = '0'; extra.text = '0'; }); }),
                const SizedBox(height: 12),
                if (product.stockUnit == StockUnit.piece)
                  IntegerField(controller: whole, label: 'Количество, шт.', min: 0)
                else
                  TwoFields(first: IntegerField(controller: whole, label: product.stockUnit == StockUnit.ml ? 'Бутылок' : 'Упаковок', min: 0), second: IntegerField(controller: extra, label: 'Доп. ${product.stockUnit.symbol}', min: 0)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(onPressed: () {
              final w = int.tryParse(whole.text) ?? -1;
              final e = product.stockUnit == StockUnit.piece ? 0 : (int.tryParse(extra.text) ?? -1);
              if (w < 0 || e < 0 || (product.stockUnit != StockUnit.piece && e >= product.packageSize) || (w == 0 && e == 0)) { showErrorSnack(dialogContext, 'Некорректное количество'); return; }
              Navigator.pop(dialogContext, DeliveryDraftLine(product: product, bottles: w, extraMl: e));
            }, child: const Text('Добавить')),
          ],
        );
      },
    ),
  );
  whole.dispose();
  extra.dispose();
  return result;
}

IconData _operationIcon(StockOperationType type) => switch (type) {
      StockOperationType.delivery => Icons.local_shipping_outlined,
      StockOperationType.stocktake => Icons.fact_check_outlined,
      StockOperationType.writeoff => Icons.remove_circle_outline,
      StockOperationType.transfer => Icons.swap_horiz,
      StockOperationType.correction => Icons.tune,
    };

String _operationTotal(StockOperation operation) {
  if (operation.type == StockOperationType.transfer) return '${operation.lines.length} поз.';
  final delta = operation.lines.fold<int>(0, (sum, line) => sum + line.changeTotalMl);
  return '${delta >= 0 ? '+' : '−'}${delta.abs()}';
}

class _WriteOffResult {
  const _WriteOffResult(this.employee, this.reason, this.lines, this.locationId, this.comment);
  final String employee;
  final String reason;
  final List<DeliveryDraftLine> lines;
  final String locationId;
  final String? comment;
}

class _TransferResult {
  const _TransferResult(this.employee, this.sourceId, this.targetId, this.lines, this.comment);
  final String employee;
  final String sourceId;
  final String targetId;
  final List<DeliveryDraftLine> lines;
  final String? comment;
}

extension _FirstOrNullControl<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
