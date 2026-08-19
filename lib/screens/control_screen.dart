import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';
import '../widgets/product_code_actions.dart';
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
    if (widget.controller.hasOperationSession) return true;
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return false;
    try {
      await widget.controller.setOperationSessionPin(pin);
      return widget.controller.hasOperationSession;
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Списание сохранено.')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Перемещение сохранено.')));
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
            title: const Text('Управление складом'),
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
    final supplierNames = {for (final supplier in controller.suppliers) supplier.id: supplier.name};
    final grouped = <String, List<PurchaseSuggestion>>{};
    for (final item in items) {
      final group = item.preferredSupplier == null ? 'Поставщик не назначен' : (supplierNames[item.preferredSupplier] ?? 'Неизвестный поставщик');
      grouped.putIfAbsent(group, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InfoBanner(icon: Icons.auto_awesome, text: 'Список рассчитывается автоматически от текущего остатка до целевого остатка. Если цель не задана — до минимума.'),
        const SizedBox(height: 16),
        for (final entry in grouped.entries) ...[
          Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF39FF6A))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < entry.value.length; index++) ...[
                  _PurchaseRow(item: entry.value[index]),
                  if (index != entry.value.length - 1) const Divider(height: 1),
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

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.item});
  final PurchaseSuggestion item;

  @override
  Widget build(BuildContext context) {
    final packages = item.stockUnit == StockUnit.piece ? item.suggestedQuantity : (item.suggestedQuantity / item.packageSize).ceil();
    final estimated = item.lastPrice == null ? null : item.lastPrice! * packages;
    return ListTile(
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${item.categoryName} • сейчас ${formatStockParts(item.currentQuantity, item.packageSize, item.stockUnit)} • минимум ${formatMinimumAmount(item.minimumAmount, item.stockUnit)}${item.targetAmount > 0 ? ' • цель ${formatMinimumAmount(item.targetAmount, item.stockUnit)}' : ''}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Заказать: $packages ${item.stockUnit.packageLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
          if (estimated != null) Text('≈ ${formatMoney(estimated, item.currency)}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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
              for (var index = 0; index < controller.locations.length; index++) ...[
                ListTile(
                  leading: Icon(controller.locations[index].isPrimary ? Icons.warehouse : Icons.inventory_2_outlined),
                  title: Text(controller.locations[index].name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(controller.locations[index].isPrimary ? 'Основное место хранения' : 'Дополнительное место хранения'),
                  trailing: controller.locations[index].isPrimary ? const Chip(label: Text('Основной')) : null,
                ),
                if (index != controller.locations.length - 1) const Divider(height: 1),
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
                subtitle: Text(_supplierContacts(supplier)),
                trailing: Text('${controller.productSuppliers.where((link) => link.supplierId == supplier.id && link.active).length} поз.'),
              ),
            ),
      ],
    );
  }

  String _supplierContacts(StockSupplier supplier) {
    final values = <String>[
      if (supplier.contactPerson?.isNotEmpty == true) supplier.contactPerson!,
      if (supplier.phone?.isNotEmpty == true) supplier.phone!,
      if (supplier.email?.isNotEmpty == true) supplier.email!,
    ];
    return values.isEmpty ? 'Контакты не указаны' : values.join(' • ');
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
    final products = widget.controller.products.where((product) {
      if (q.isEmpty) return true;
      return '${product.name} ${product.categoryName} ${product.barcode ?? ''}'.toLowerCase().contains(q);
    }).toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(controller: widget.search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Название / категория / код товара')),
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
    final initialized = controller.products.where((product) => product.stockInitialized);
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
                for (var index = 0; index < data.largestVariances.length; index++) ...[
                  ListTile(
                    title: Text('${data.largestVariances[index]['product_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: Text('${data.largestVariances[index]['variance'] ?? 0}', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.error)),
                  ),
                  if (index != data.largestVariances.length - 1) const Divider(height: 1),
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
                      subtitle: Text('Было: ${formatStockParts(row.line.beforeTotalMl, row.line.bottleMl, row.line.stockUnit)}\nИзменение: ${row.line.changeTotalMl >= 0 ? '+' : '−'}${formatTotalAmount(row.line.changeTotalMl.abs(), row.line.stockUnit)} • стало: ${formatStockParts(row.line.afterTotalMl, row.line.bottleMl, row.line.stockUnit)}'),
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
  final employee = TextEditingController();
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final linked = controller.productSuppliers.where((link) => link.productKey == _productKey(product) && link.active).toList(growable: false);
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
                  IntegerField(controller: recheck, label: 'Повторный пересчёт при расхождении от, ${product.stockUnit.symbol}', min: 0),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Код товара / штрихкод / QR'))),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Сканировать код товара',
                        onPressed: () async {
                          final value = await scanProductCode(dialogContext);
                          if (value != null) barcode.text = value;
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoBanner(
                    icon: Icons.payments_outlined,
                    text: product.defaultCost == null
                        ? 'Закупочная цена пока не определена. Она заполняется автоматически только после фактической поставки.'
                        : 'Последняя закупочная цена: ${formatMoney(product.defaultCost, product.costCurrency)}. Вручную она не редактируется и обновляется только поставкой.',
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
                        title: Text(_supplierName(controller, link.supplierId)),
                        subtitle: Text('${link.isPrimary ? 'Основной • ' : ''}${link.supplierSku == null ? '' : 'арт. ${link.supplierSku} • '}последняя фактическая цена ${formatMoney(link.lastPrice, link.currency)}'),
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
                      if (minValue == null || targetValue == null || recheckValue == null || minValue < 0 || targetValue < 0 || recheckValue < 0) {
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
  employee.dispose();
}

Future<void> showLinkSupplierDialog(BuildContext context, WarehouseController controller, Product product) async {
  if (controller.suppliers.isEmpty) {
    showErrorSnack(context, 'Сначала добавьте поставщика');
    return;
  }
  String supplierId = controller.suppliers.first.id;
  final sku = TextEditingController();
  var primary = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final existing = controller.supplierLink(product, supplierId);
        return AlertDialog(
          title: const Text('Привязать поставщика'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supplierId,
                  decoration: const InputDecoration(labelText: 'Поставщик'),
                  items: controller.suppliers.where((supplier) => supplier.active).map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => supplierId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: sku, decoration: const InputDecoration(labelText: 'Артикул у поставщика')),
                const SizedBox(height: 12),
                InfoBanner(
                  icon: Icons.payments_outlined,
                  text: existing?.lastPrice == null
                      ? 'Цена поставщика появится после фактической поставки.'
                      : 'Последняя фактическая цена: ${formatMoney(existing!.lastPrice, existing.currency)}. Ручное изменение отключено.',
                ),
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
                    lastPrice: existing?.lastPrice,
                    currency: existing?.currency ?? product.costCurrency,
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
        );
      },
    ),
  );
  sku.dispose();
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
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Причина *'),
                  items: reasons.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => reason = value);
                  },
                ),
                const SizedBox(height: 10),
                if (controller.locations.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: locationId,
                    decoration: const InputDecoration(labelText: 'Откуда списать'),
                    items: controller.locations.where((location) => location.active).map((location) => DropdownMenuItem(value: location.id, child: Text(location.name))).toList(growable: false),
                    onChanged: (value) => setState(() => locationId = value),
                  ),
                if (controller.locations.isNotEmpty) const SizedBox(height: 10),
                TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий')),
                const SizedBox(height: 16),
                _MovementLinesEditor(
                  dialogContext: dialogContext,
                  controller: controller,
                  lines: lines,
                  setDialogState: setState,
                  pickerTitle: 'Что списать',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (employee.text.trim().isEmpty || lines.isEmpty || locationId == null) {
                showErrorSnack(dialogContext, 'Заполните ФИО и добавьте позиции');
                return;
              }
              Navigator.pop(dialogContext, _WriteOffResult(employee.text.trim(), reason, lines.values.toList(growable: false), locationId!, _nullable(comment.text)));
            },
            child: const Text('Провести списание'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    employee.dispose();
    comment.dispose();
  });
}

Future<_TransferResult?> showTransferDialog(BuildContext context, WarehouseController controller) async {
  if (controller.locations.length < 2) return null;
  final employee = TextEditingController();
  final comment = TextEditingController();
  var source = controller.primaryLocation?.id ?? controller.locations.first.id;
  var target = controller.locations.firstWhere((location) => location.id != source).id;
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
                  first: DropdownButtonFormField<String>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'Откуда'),
                    items: controller.locations.where((location) => location.active).map((location) => DropdownMenuItem(value: location.id, child: Text(location.name))).toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        source = value;
                        if (target == source) target = controller.locations.firstWhere((location) => location.id != source).id;
                      });
                    },
                  ),
                  second: DropdownButtonFormField<String>(
                    initialValue: target,
                    decoration: const InputDecoration(labelText: 'Куда'),
                    items: controller.locations.where((location) => location.active && location.id != source).map((location) => DropdownMenuItem(value: location.id, child: Text(location.name))).toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => target = value);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий')),
                const SizedBox(height: 16),
                _MovementLinesEditor(
                  dialogContext: dialogContext,
                  controller: controller,
                  lines: lines,
                  setDialogState: setState,
                  pickerTitle: 'Что переместить',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (employee.text.trim().isEmpty || lines.isEmpty || source == target) {
                showErrorSnack(dialogContext, 'Проверьте ФИО, склады и позиции');
                return;
              }
              Navigator.pop(dialogContext, _TransferResult(employee.text.trim(), source, target, lines.values.toList(growable: false), _nullable(comment.text)));
            },
            child: const Text('Переместить'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    employee.dispose();
    comment.dispose();
  });
}

class _MovementLinesEditor extends StatelessWidget {
  const _MovementLinesEditor({
    required this.dialogContext,
    required this.controller,
    required this.lines,
    required this.setDialogState,
    required this.pickerTitle,
  });

  final BuildContext dialogContext;
  final WarehouseController controller;
  final Map<int, DeliveryDraftLine> lines;
  final StateSetter setDialogState;
  final String pickerTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: () async {
              final line = await _quantityLineDialog(dialogContext, controller.products, title: pickerTitle);
              if (line != null) setDialogState(() => lines[line.product.id] = line);
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить позицию'),
          ),
        ),
        for (final line in lines.values)
          ListTile(
            title: Text(line.product.name),
            subtitle: Text(formatStockParts(line.addedMl, line.product.packageSize, line.product.stockUnit)),
            trailing: IconButton(
              onPressed: () => setDialogState(() => lines.remove(line.product.id)),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }
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
        final product = products.firstWhere((item) => item.id == productId);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Позиция'),
                  items: products.map((item) => DropdownMenuItem(value: item.id, child: Text('${item.categoryName} — ${item.name}'))).toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      productId = value;
                      whole.text = '0';
                      extra.text = '0';
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (product.stockUnit == StockUnit.piece)
                  IntegerField(controller: whole, label: 'Количество, шт.', min: 0)
                else
                  TwoFields(
                    first: IntegerField(controller: whole, label: product.stockUnit == StockUnit.ml ? 'Бутылок' : 'Упаковок', min: 0),
                    second: IntegerField(controller: extra, label: 'Доп. ${product.stockUnit.symbol}', min: 0),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final wholeValue = int.tryParse(whole.text) ?? -1;
                final extraValue = product.stockUnit == StockUnit.piece ? 0 : (int.tryParse(extra.text) ?? -1);
                if (wholeValue < 0 || extraValue < 0 || (product.stockUnit != StockUnit.piece && extraValue >= product.packageSize) || (wholeValue == 0 && extraValue == 0)) {
                  showErrorSnack(dialogContext, 'Некорректное количество');
                  return;
                }
                Navigator.pop(dialogContext, DeliveryDraftLine(product: product, bottles: wholeValue, extraMl: extraValue));
              },
              child: const Text('Добавить'),
            ),
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
      StockOperationType.spotStocktake => Icons.center_focus_strong_outlined,
      StockOperationType.writeoff => Icons.remove_circle_outline,
      StockOperationType.transfer => Icons.swap_horiz,
      StockOperationType.correction => Icons.tune,
    };

String _operationTotal(StockOperation operation) {
  if (operation.type == StockOperationType.transfer) return '${operation.lines.length} поз.';
  final delta = operation.lines.fold<int>(0, (sum, line) => sum + line.changeTotalMl);
  return '${delta >= 0 ? '+' : '−'}${delta.abs()}';
}

String _productKey(Product product) => '${product.name.trim().toLowerCase()}|${product.stockUnit.dbValue}|${product.packageSize}';

String _supplierName(WarehouseController controller, String supplierId) {
  for (final supplier in controller.suppliers) {
    if (supplier.id == supplierId) return supplier.name;
  }
  return 'Поставщик';
}

String? _nullable(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
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
