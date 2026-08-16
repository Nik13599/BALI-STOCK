import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

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
    for (final value in _bottles.values) {
      value.dispose();
    }
    for (final value in _extra.values) {
      value.dispose();
    }
    super.dispose();
  }

  bool _filled(Product product) {
    final bottlesText = _bottles[product.id]!.text;
    final extraText = _extra[product.id]!.text;
    if (bottlesText.isEmpty || extraText.isEmpty) return false;
    final bottles = int.tryParse(bottlesText);
    final extra = int.tryParse(extraText);
    return bottles != null && bottles >= 0 && extra != null && extra >= 0 && extra < product.bottleMl;
  }

  int get _filledCount => _products.where(_filled).length;
  bool get _complete => _products.isNotEmpty && _filledCount == _products.length;

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
      return Scaffold(
        appBar: AppBar(title: const Text('Переучёт')),
        body: const EmptyState(icon: Icons.fact_check_outlined, title: 'Нет позиций для переучёта', message: 'Сначала добавьте товары в склад.'),
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
                const InfoBanner(
                  icon: Icons.fact_check_outlined,
                  text: 'Нужно пересчитать абсолютно все категории и все позиции. Пустое поле не считается нулём: если товара нет, введите 0 бутылок и 0 мл.',
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(10),
                        value: _filledCount / _products.length,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text('$_filledCount / ${_products.length}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                  _CategoryStocktakeCard(
                    title: entry.key,
                    products: entry.value,
                    bottles: _bottles,
                    extra: _extra,
                    isFilled: _filled,
                    enabled: !_saving,
                    onChanged: () => setState(() {}),
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
                        'Не заполнено: ${_products.length - _filledCount} позиций',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _complete && !_saving ? _submit : null,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ПРОВЕСТИ ПЕРЕУЧЁТ')),
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

class _CategoryStocktakeCard extends StatelessWidget {
  const _CategoryStocktakeCard({
    required this.title,
    required this.products,
    required this.bottles,
    required this.extra,
    required this.isFilled,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final List<Product> products;
  final Map<int, TextEditingController> bottles;
  final Map<int, TextEditingController> extra;
  final bool Function(Product) isFilled;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final done = products.where(isFilled).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('$done / ${products.length}'),
            const SizedBox(width: 8),
            Icon(done == products.length ? Icons.check_circle : Icons.pending_outlined, color: done == products.length ? Theme.of(context).colorScheme.primary : null),
          ],
        ),
        children: [
          for (var i = 0; i < products.length; i++) ...[
            _ProductStocktakeRow(
              product: products[i],
              bottlesController: bottles[products[i].id]!,
              extraController: extra[products[i].id]!,
              filled: isFilled(products[i]),
              enabled: enabled,
              onChanged: onChanged,
            ),
            if (i != products.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProductStocktakeRow extends StatelessWidget {
  const _ProductStocktakeRow({
    required this.product,
    required this.bottlesController,
    required this.extraController,
    required this.filled,
    required this.enabled,
    required this.onChanged,
  });

  final Product product;
  final TextEditingController bottlesController;
  final TextEditingController extraController;
  final bool filled;
  final bool enabled;
  final VoidCallback onChanged;

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
          if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), fields]);
          return Row(children: [Expanded(flex: 4, child: title), const SizedBox(width: 20), Expanded(flex: 3, child: fields)]);
        },
      ),
    );
  }
}
