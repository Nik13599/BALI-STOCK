import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'models.dart';

const _operationPin = '13599';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WarehouseController();
  await controller.initialize();
  runApp(BaliStockApp(controller: controller));
}

class BaliStockApp extends StatelessWidget {
  const BaliStockApp({super.key, required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BALI STOCK',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF78D64B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0F10),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: BaliStockShell(controller: controller),
    );
  }
}

class BaliStockShell extends StatefulWidget {
  const BaliStockShell({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<BaliStockShell> createState() => _BaliStockShellState();
}

class _BaliStockShellState extends State<BaliStockShell> {
  int _selectedIndex = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Склад'),
    NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Поставка'),
    NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Переучёт'),
    NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: 'История'),
  ];

  Future<void> _select(int index) async {
    if (index == _selectedIndex) return;
    if (index == 1 || index == 2) {
      final allowed = await showOperationPinDialog(context);
      if (!mounted || !allowed) return;
    }
    setState(() => _selectedIndex = index);
  }

  Widget _page() {
    return switch (_selectedIndex) {
      0 => StockScreen(controller: widget.controller),
      1 => DeliveryScreen(controller: widget.controller),
      2 => StocktakeScreen(
          controller: widget.controller,
          onCompleted: () => setState(() => _selectedIndex = 0),
        ),
      3 => HistoryScreen(controller: widget.controller),
      _ => StockScreen(controller: widget.controller),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    minWidth: 88,
                    extended: constraints.maxWidth >= 1180,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _select,
                    leading: const Padding(
                      padding: EdgeInsets.fromLTRB(12, 16, 12, 28),
                      child: _BrandMark(),
                    ),
                    destinations: const [
                      NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: Text('Склад')),
                      NavigationRailDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: Text('Поставка')),
                      NavigationRailDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: Text('Переучёт')),
                      NavigationRailDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: Text('История')),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _page()),
              ],
            ),
          );
        }

        return Scaffold(
          body: _page(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            destinations: _destinations,
          ),
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('B', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        const Text('BALI STOCK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
      ],
    );
  }
}

Future<bool> showOperationPinDialog(BuildContext context) async {
  final pinController = TextEditingController();
  var invalid = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Введите пароль доступа'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) {
              if (pinController.text == _operationPin) {
                Navigator.of(context).pop(true);
              } else {
                setState(() => invalid = true);
              }
            },
            decoration: InputDecoration(
              labelText: 'Пароль',
              errorText: invalid ? 'Неверный пароль' : null,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (pinController.text == _operationPin) {
                Navigator.of(context).pop(true);
              } else {
                setState(() => invalid = true);
              }
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ),
  );
  pinController.dispose();
  return result ?? false;
}

class StockScreen extends StatelessWidget {
  const StockScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Склад'),
            actions: [
              IconButton(
                tooltip: 'Обновить',
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showAddProductDialog(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('Добавить позицию'),
          ),
          body: _ControllerBody(
            controller: controller,
            child: controller.products.isEmpty
                ? _EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Склад пока пуст',
                    message: 'Добавьте первую позицию и сразу укажите её текущий фактический остаток.',
                    action: FilledButton.icon(
                      onPressed: () => showAddProductDialog(context, controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить первую позицию'),
                    ),
                  )
                : _StockList(controller: controller),
          ),
        );
      },
    );
  }
}

class _StockList extends StatelessWidget {
  const _StockList({required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    final low = controller.products.where((p) => p.isLow).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: 'Позиций', value: '${controller.products.length}', icon: Icons.inventory_2),
            _MetricCard(label: 'Критический остаток', value: '$low', icon: Icons.warning_amber_rounded, danger: low > 0),
            _MetricCard(label: 'Категорий', value: '${controller.categories.length}', icon: Icons.category_outlined),
          ],
        ),
        const SizedBox(height: 24),
        for (final category in controller.categories)
          if (controller.products.any((p) => p.categoryId == category.id)) ...[
            _CategoryStockCard(
              category: category,
              products: controller.products.where((p) => p.categoryId == category.id).toList(growable: false),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, this.danger = false});

  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger ? colors.errorContainer.withValues(alpha: .45) : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: danger ? colors.error : colors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryStockCard extends StatelessWidget {
  const _CategoryStockCard({required this.category, required this.products});

  final Category category;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final low = products.where((p) => p.isLow).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${products.length} поз.'),
            if (low > 0) ...[
              const SizedBox(width: 10),
              Badge(label: Text('$low'), child: const Icon(Icons.warning_amber_rounded)),
            ],
          ],
        ),
        children: [
          for (var i = 0; i < products.length; i++) ...[
            _ProductStockTile(product: products[i]),
            if (i != products.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProductStockTile extends StatelessWidget {
  const _ProductStockTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final danger = product.isLow;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Row(
        children: [
          Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(formatBottleVolume(product.bottleMl), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          'Всего ${formatLiters(product.totalMl)}  •  минимум ${product.minimumMl} мл',
          style: TextStyle(color: danger ? colors.error : null),
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
        child: Text(
          '${product.wholeBottles} бут. × ${formatBottleVolume(product.bottleMl)} + ${product.extraMl} мл',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: danger ? colors.error : colors.onSurface,
              ),
        ),
      ),
    );
  }
}

Future<void> showAddProductDialog(BuildContext context, WarehouseController controller) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final bottles = TextEditingController(text: '0');
  final bottleMl = TextEditingController(text: '500');
  final extra = TextEditingController(text: '0');
  final minimum = TextEditingController(text: '0');
  var categoryId = controller.categories.isNotEmpty ? controller.categories.first.id : null;
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> addCategory() async {
          final newName = await showTextValueDialog(dialogContext, 'Новая категория', 'Название категории');
          if (newName == null || newName.trim().isEmpty) return;
          try {
            final id = await controller.addCategory(newName);
            setState(() => categoryId = id);
          } catch (e) {
            if (dialogContext.mounted) showErrorSnack(dialogContext, e);
          }
        }

        Future<void> save() async {
          if (!(formKey.currentState?.validate() ?? false) || categoryId == null) return;
          setState(() => saving = true);
          try {
            await controller.addProduct(
              name: name.text,
              categoryId: categoryId!,
              bottleMl: int.parse(bottleMl.text),
              wholeBottles: int.parse(bottles.text),
              extraMl: int.parse(extra.text),
              minimumMl: int.parse(minimum.text),
            );
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          } catch (e) {
            if (dialogContext.mounted) showErrorSnack(dialogContext, e);
            setState(() => saving = false);
          }
        }

        return AlertDialog(
          title: const Text('Добавить позицию'),
          content: SizedBox(
            width: 540,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Название позиции'),
                      validator: _requiredText,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: categoryId,
                            decoration: const InputDecoration(labelText: 'Категория'),
                            items: controller.categories
                                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                                .toList(growable: false),
                            onChanged: saving ? null : (value) => setState(() => categoryId = value),
                            validator: (value) => value == null ? 'Выберите категорию' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Добавить категорию',
                          onPressed: saving ? null : addCategory,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TwoFields(
                      first: _IntegerField(controller: bottles, label: 'Количество бутылок', min: 0),
                      second: _IntegerField(controller: bottleMl, label: 'Мл в одной бутылке', min: 1),
                    ),
                    const SizedBox(height: 12),
                    _TwoFields(
                      first: _IntegerField(
                        controller: extra,
                        label: 'Доп. остаток, мл',
                        min: 0,
                        validator: (value) {
                          final base = _integerValidator(value, min: 0);
                          if (base != null) return base;
                          final bottleValue = int.tryParse(bottleMl.text);
                          final extraValue = int.tryParse(value ?? '');
                          if (bottleValue != null && extraValue != null && extraValue >= bottleValue) {
                            return 'Должен быть меньше объёма бутылки';
                          }
                          return null;
                        },
                      ),
                      second: _IntegerField(controller: minimum, label: 'Минимальный остаток, мл', min: 0),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Если дополнительного остатка нет — укажите 0. Минимальный остаток может быть меньше одной бутылки.'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
              label: const Text('Добавить на склад'),
            ),
          ],
        );
      },
    ),
  );

  name.dispose();
  bottles.dispose();
  bottleMl.dispose();
  extra.dispose();
  minimum.dispose();
}

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final Map<int, DeliveryDraftLine> _lines = {};
  bool _saving = false;

  Future<void> _addLine() async {
    final line = await showDeliveryLineDialog(context, widget.controller.products);
    if (line == null) return;
    setState(() => _lines[line.product.id] = line);
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.controller.receiveDelivery(_lines.values.toList(growable: false));
      if (!mounted) return;
      setState(() => _lines.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Поставка принята. Остатки склада обновлены.')));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Принять поставку')),
        body: widget.controller.products.isEmpty
            ? const _EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'Нет складских позиций',
                message: 'Сначала добавьте позиции в разделе «Склад».',
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _InfoBanner(
                    icon: Icons.lock_outline,
                    text: 'Доступ к приёмке уже подтверждён паролем. После проведения количество автоматически прибавится к складу.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text('Позиции поставки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      FilledButton.icon(onPressed: _saving ? null : _addLine, icon: const Icon(Icons.add), label: const Text('Добавить позицию')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_lines.isEmpty)
                    const _EmptyInline(message: 'Добавьте товары, которые фактически пришли в этой поставке.')
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < _lines.values.length; i++) ...[
                            _DeliveryLineTile(
                              line: _lines.values.elementAt(i),
                              onDelete: _saving ? null : () => setState(() => _lines.remove(_lines.values.elementAt(i).product.id)),
                            ),
                            if (i != _lines.length - 1) const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _lines.isEmpty || _saving ? null : _submit,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('ПРОВЕСТИ ПОСТАВКУ'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DeliveryLineTile extends StatelessWidget {
  const _DeliveryLineTile({required this.line, required this.onDelete});

  final DeliveryDraftLine line;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${line.product.categoryName} • бутылка ${formatBottleVolume(line.product.bottleMl)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+${line.bottles} бут. + ${line.extraMl} мл', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
    );
  }
}

Future<DeliveryDraftLine?> showDeliveryLineDialog(BuildContext context, List<Product> products) async {
  if (products.isEmpty) return null;
  var productId = products.first.id;
  final bottles = TextEditingController(text: '0');
  final extra = TextEditingController(text: '0');
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        return AlertDialog(
          title: const Text('Позиция поставки'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Позиция'),
                    items: products
                        .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name} (${formatBottleVolume(p.bottleMl)})')))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => productId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _TwoFields(
                    first: _IntegerField(controller: bottles, label: 'Бутылок принято', min: 0),
                    second: _IntegerField(
                      controller: extra,
                      label: 'Доп. объём, мл',
                      min: 0,
                      validator: (value) {
                        final base = _integerValidator(value, min: 0);
                        if (base != null) return base;
                        final parsed = int.tryParse(value ?? '');
                        if (parsed != null && parsed >= product.bottleMl) return 'Меньше ${product.bottleMl} мл';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final bottleCount = int.parse(bottles.text);
                final extraMl = int.parse(extra.text);
                if (bottleCount == 0 && extraMl == 0) {
                  showErrorSnack(dialogContext, 'Количество поставки не может быть нулевым');
                  return;
                }
                Navigator.of(dialogContext).pop(DeliveryDraftLine(product: product, bottles: bottleCount, extraMl: extraMl));
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    ),
  );

  bottles.dispose();
  extra.dispose();
  return result;
}

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key, required this.controller, required this.onCompleted});

  final WarehouseController controller;
  final VoidCallback onCompleted;

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  late final List<Product> _products;
  final Map<int, TextEditingController> _bottles = {};
  final Map<int, TextEditingController> _extra = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _products = List<Product>.from(widget.controller.products);
    for (final product in _products) {
      _bottles[product.id] = TextEditingController();
      _extra[product.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _bottles.values) {
      controller.dispose();
    }
    for (final controller in _extra.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isProductFilled(Product product) {
    final bottlesText = _bottles[product.id]!.text;
    final extraText = _extra[product.id]!.text;
    if (bottlesText.isEmpty || extraText.isEmpty) return false;
    final bottles = int.tryParse(bottlesText);
    final extra = int.tryParse(extraText);
    return bottles != null && bottles >= 0 && extra != null && extra >= 0 && extra < product.bottleMl;
  }

  int get _filled => _products.where(_isProductFilled).length;
  bool get _complete => _products.isNotEmpty && _filled == _products.length;

  Future<void> _submit() async {
    if (!_complete) return;
    final values = <int, StocktakeDraftLine>{};
    for (final product in _products) {
      values[product.id] = StocktakeDraftLine(
        bottles: int.parse(_bottles[product.id]!.text),
        extraMl: int.parse(_extra[product.id]!.text),
      );
    }

    setState(() => _saving = true);
    try {
      await widget.controller.conductStocktake(values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Переучёт проведён. Фактические остатки сохранены.')));
      widget.onCompleted();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_products.isEmpty) {
      return const Scaffold(
        appBar: AppBar(title: Text('Переучёт')),
        body: _EmptyState(icon: Icons.fact_check_outlined, title: 'Нет позиций для переучёта', message: 'Сначала добавьте товары в склад.'),
      );
    }

    final grouped = <String, List<Product>>{};
    for (final product in _products) {
      grouped.putIfAbsent(product.categoryName, () => []).add(product);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Полный переучёт')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoBanner(
                  icon: Icons.fact_check_outlined,
                  text: 'Необходимо пересчитать абсолютно все категории и все позиции. Пустое поле не равно нулю: если товара нет, введите 0 бутылок и 0 мл.',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(10),
                        value: _products.isEmpty ? 0 : _filled / _products.length,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text('$_filled / ${_products.length}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                for (final entry in grouped.entries) ...[
                  _StocktakeCategoryCard(
                    title: entry.key,
                    products: entry.value,
                    bottlesControllers: _bottles,
                    extraControllers: _extra,
                    onChanged: () => setState(() {}),
                    isFilled: _isProductFilled,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_complete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Не заполнено: ${_products.length - _filled} позиций',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _complete && !_saving ? _submit : null,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('ПРОВЕСТИ ПЕРЕУЧЁТ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StocktakeCategoryCard extends StatelessWidget {
  const _StocktakeCategoryCard({
    required this.title,
    required this.products,
    required this.bottlesControllers,
    required this.extraControllers,
    required this.onChanged,
    required this.isFilled,
    required this.enabled,
  });

  final String title;
  final List<Product> products;
  final Map<int, TextEditingController> bottlesControllers;
  final Map<int, TextEditingController> extraControllers;
  final VoidCallback onChanged;
  final bool Function(Product product) isFilled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final filled = products.where(isFilled).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('$filled / ${products.length}'),
            const SizedBox(width: 8),
            Icon(filled == products.length ? Icons.check_circle : Icons.pending_outlined, color: filled == products.length ? Theme.of(context).colorScheme.primary : null),
          ],
        ),
        children: [
          for (var i = 0; i < products.length; i++) ...[
            _StocktakeProductRow(
              product: products[i],
              bottlesController: bottlesControllers[products[i].id]!,
              extraController: extraControllers[products[i].id]!,
              onChanged: onChanged,
              filled: isFilled(products[i]),
              enabled: enabled,
            ),
            if (i != products.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _StocktakeProductRow extends StatelessWidget {
  const _StocktakeProductRow({
    required this.product,
    required this.bottlesController,
    required this.extraController,
    required this.onChanged,
    required this.filled,
    required this.enabled,
  });

  final Product product;
  final TextEditingController bottlesController;
  final TextEditingController extraController;
  final VoidCallback onChanged;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Icon(filled ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: filled ? Theme.of(context).colorScheme.primary : null),
                ],
              ),
              const SizedBox(height: 3),
              Text('Тара ${formatBottleVolume(product.bottleMl)} • до переучёта: ${product.wholeBottles} бут. + ${product.extraMl} мл', style: Theme.of(context).textTheme.bodySmall),
            ],
          );
          final fields = Row(
            children: [
              Expanded(
                child: TextField(
                  controller: bottlesController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Целых бутылок', hintText: '0'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: extraController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(labelText: 'Остаток, мл', hintText: '0', helperText: '< ${product.bottleMl} мл'),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), fields]);
          }
          return Row(children: [Expanded(flex: 4, child: title), const SizedBox(width: 20), Expanded(flex: 3, child: fields)]);
        },
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('История операций'),
          actions: [IconButton(onPressed: controller.refresh, icon: const Icon(Icons.refresh))],
        ),
        body: _ControllerBody(
          controller: controller,
          child: controller.operations.isEmpty
              ? const _EmptyState(icon: Icons.history, title: 'История пока пуста', message: 'Здесь будут видны всем пользователям все поставки и переучёты.')
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: controller.operations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final operation = controller.operations[index];
                    final delivery = operation.type == StockOperationType.delivery;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        leading: CircleAvatar(child: Icon(delivery ? Icons.local_shipping_outlined : Icons.fact_check_outlined)),
                        title: Text(delivery ? 'Поставка №${operation.id}' : 'Переучёт №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${formatDateTime(operation.createdAt)} • ${operation.lines.length} позиций'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showOperationDetails(context, operation),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

Future<void> showOperationDetails(BuildContext context, StockOperation operation) async {
  final delivery = operation.type == StockOperationType.delivery;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () => Navigator.of(dialogContext).pop(), icon: const Icon(Icons.close)),
          title: Text('${delivery ? 'Поставка' : 'Переучёт'} №${operation.id}'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(formatDateTime(operation.createdAt), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            for (var i = 0; i < operation.lines.length; i++) ...[
              _HistoryLine(line: operation.lines[i], delivery: delivery),
              if (i != operation.lines.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      ),
    ),
  );
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.line, required this.delivery});

  final StockOperationLine line;
  final bool delivery;

  @override
  Widget build(BuildContext context) {
    final diff = line.changeTotalMl;
    final diffText = '${diff >= 0 ? '+' : '−'}${formatLiters(diff.abs())}';
    final diffColor = diff < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('${line.categoryName} • тара ${formatBottleVolume(line.bottleMl)}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text('Было: ${formatStockParts(line.beforeTotalMl, line.bottleMl)}'),
              Text(delivery ? 'Принято: $diffText' : 'Расхождение: $diffText', style: TextStyle(color: diffColor, fontWeight: FontWeight.w700)),
              Text('Стало: ${formatStockParts(line.afterTotalMl, line.bottleMl)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControllerBody extends StatelessWidget {
  const _ControllerBody({required this.controller, required this.child});

  final WarehouseController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const Center(child: CircularProgressIndicator());
    if (controller.error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: 'Не удалось загрузить данные',
        message: controller.error!,
        action: FilledButton.icon(onPressed: controller.refresh, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
      );
    }
    return child;
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 60, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _TwoFields extends StatelessWidget {
  const _TwoFields({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: first), const SizedBox(width: 12), Expanded(child: second)]);
      },
    );
  }
}

class _IntegerField extends StatelessWidget {
  const _IntegerField({required this.controller, required this.label, required this.min, this.validator});

  final TextEditingController controller;
  final String label;
  final int min;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      validator: validator ?? (value) => _integerValidator(value, min: min),
    );
  }
}

String? _requiredText(String? value) => value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

String? _integerValidator(String? value, {required int min}) {
  if (value == null || value.isEmpty) return 'Укажите значение';
  final parsed = int.tryParse(value);
  if (parsed == null) return 'Только целое число';
  if (parsed < min) return 'Минимум $min';
  return null;
}

Future<String?> showTextValueDialog(BuildContext context, String title, String label) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Добавить')),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void showErrorSnack(BuildContext context, Object error) {
  final text = error.toString().replaceFirst('Invalid argument(s): ', '').replaceFirst('Bad state: ', '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
