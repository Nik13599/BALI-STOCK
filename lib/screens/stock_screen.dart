import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

class StockScreen extends StatelessWidget {
  const StockScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Склад'),
          actions: [IconButton(tooltip: 'Обновить', onPressed: controller.refresh, icon: const Icon(Icons.refresh))],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showAddProductDialog(context, controller),
          icon: const Icon(Icons.add),
          label: const Text('Добавить позицию'),
        ),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (controller.loading) return const Center(child: CircularProgressIndicator());
    if (controller.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Не удалось загрузить склад',
        message: controller.error!,
        action: FilledButton.icon(onPressed: controller.refresh, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
      );
    }
    if (controller.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Склад пока пуст',
        message: 'Добавьте первую позицию и сразу укажите фактический текущий остаток.',
        action: FilledButton.icon(
          onPressed: () => showAddProductDialog(context, controller),
          icon: const Icon(Icons.add),
          label: const Text('Добавить первую позицию'),
        ),
      );
    }

    final low = controller.products.where((p) => p.isLow).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(label: 'Позиций', value: '${controller.products.length}', icon: Icons.inventory_2),
            MetricCard(label: 'Критический остаток', value: '$low', icon: Icons.warning_amber_rounded, danger: low > 0),
            MetricCard(label: 'Категорий', value: '${controller.categories.length}', icon: Icons.category_outlined),
          ],
        ),
        const SizedBox(height: 24),
        for (final category in controller.categories)
          if (controller.products.any((p) => p.categoryId == category.id)) ...[
            _CategoryCard(
              category: category,
              products: controller.products.where((p) => p.categoryId == category.id).toList(growable: false),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.products});

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
            _ProductTile(product: products[i]),
            if (i != products.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

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
          'Всего ${formatLiters(product.totalMl)} • минимум ${product.minimumMl} мл',
          style: TextStyle(color: danger ? colors.error : null),
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          '${product.wholeBottles} бут. × ${formatBottleVolume(product.bottleMl)} + ${product.extraMl} мл',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: danger ? colors.error : colors.onSurface),
        ),
      ),
    );
  }
}

Future<void> showAddProductDialog(BuildContext context, WarehouseController controller) async {
  final key = GlobalKey<FormState>();
  final name = TextEditingController();
  final bottles = TextEditingController(text: '0');
  final bottleMl = TextEditingController(text: '500');
  final extra = TextEditingController(text: '0');
  final minimum = TextEditingController(text: '0');
  int? categoryId = controller.categories.isNotEmpty ? controller.categories.first.id : null;
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> addCategory() async {
          final value = await showTextValueDialog(dialogContext, 'Новая категория', 'Название категории');
          if (value == null || value.trim().isEmpty) return;
          try {
            final id = await controller.addCategory(value);
            setState(() => categoryId = id);
          } catch (e) {
            if (dialogContext.mounted) showErrorSnack(dialogContext, e);
          }
        }

        Future<void> save() async {
          if (!(key.currentState?.validate() ?? false) || categoryId == null) return;
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
            width: 560,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Название позиции'), validator: requiredText),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: categoryId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Категория'),
                            items: controller.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(growable: false),
                            onChanged: saving ? null : (value) => setState(() => categoryId = value),
                            validator: (value) => value == null ? 'Выберите категорию' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(onPressed: saving ? null : addCategory, tooltip: 'Добавить категорию', icon: const Icon(Icons.add)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TwoFields(
                      first: IntegerField(controller: bottles, label: 'Количество бутылок', min: 0),
                      second: IntegerField(controller: bottleMl, label: 'Мл в одной бутылке', min: 1),
                    ),
                    const SizedBox(height: 12),
                    TwoFields(
                      first: IntegerField(
                        controller: extra,
                        label: 'Доп. остаток, мл',
                        min: 0,
                        validator: (value) {
                          final base = integerValidator(value, min: 0);
                          if (base != null) return base;
                          final bottle = int.tryParse(bottleMl.text);
                          final residue = int.tryParse(value ?? '');
                          if (bottle != null && residue != null && residue >= bottle) return 'Должен быть меньше объёма бутылки';
                          return null;
                        },
                      ),
                      second: IntegerField(controller: minimum, label: 'Минимальный остаток, мл', min: 0),
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
