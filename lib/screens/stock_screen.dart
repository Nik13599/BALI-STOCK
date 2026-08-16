import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  bool _editMode = false;

  Future<void> _toggleEditMode() async {
    if (_editMode) {
      setState(() => _editMode = false);
      return;
    }
    final allowed = await showOperationPinDialog(context);
    if (!mounted || !allowed) return;
    setState(() => _editMode = true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Склад'),
          actions: [
            TextButton.icon(
              onPressed: _toggleEditMode,
              icon: Icon(_editMode ? Icons.lock_open : Icons.edit_outlined),
              label: Text(_editMode ? 'Завершить' : 'Редактировать'),
            ),
            IconButton(tooltip: 'Обновить', onPressed: controller.refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: _editMode
            ? FloatingActionButton.extended(
                onPressed: () => showAddProductDialog(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('Добавить позицию'),
              )
            : null,
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = widget.controller;
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
        message: _editMode ? 'Добавьте первую складскую позицию.' : 'Для добавления позиций включите режим редактирования.',
        action: _editMode
            ? FilledButton.icon(
                onPressed: () => showAddProductDialog(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('Добавить первую позицию'),
              )
            : null,
      );
    }

    final low = controller.products.where((p) => p.isLow).length;
    final notCounted = controller.products.where((p) => !p.stockInitialized).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        if (_editMode) ...[
          const InfoBanner(
            icon: Icons.edit_note,
            text: 'Режим редактирования открыт. Можно менять карточки и добавлять позиции. Фактические остатки здесь не редактируются — только через поставку или переучёт.',
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(label: 'Позиций', value: '${controller.products.length}', icon: Icons.inventory_2),
            MetricCard(label: 'Не пересчитано', value: '$notCounted', icon: Icons.pending_actions),
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
              editMode: _editMode,
              onEdit: (product) => showEditProductDialog(context, controller, product),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.products, required this.editMode, required this.onEdit});

  final Category category;
  final List<Product> products;
  final bool editMode;
  final ValueChanged<Product> onEdit;

  @override
  Widget build(BuildContext context) {
    final low = products.where((p) => p.isLow).length;
    final notCounted = products.where((p) => !p.stockInitialized).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${products.length} поз.'),
            if (notCounted > 0) ...[
              const SizedBox(width: 10),
              Badge(label: Text('$notCounted'), child: const Icon(Icons.pending_actions)),
            ],
            if (low > 0) ...[
              const SizedBox(width: 10),
              Badge(label: Text('$low'), child: const Icon(Icons.warning_amber_rounded)),
            ],
          ],
        ),
        children: [
          for (var i = 0; i < products.length; i++) ...[
            _ProductTile(product: products[i], editMode: editMode, onEdit: () => onEdit(products[i])),
            if (i != products.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.editMode, required this.onEdit});

  final Product product;
  final bool editMode;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final danger = product.isLow;
    final unknown = !product.stockInitialized;
    final amountText = unknown
        ? 'Остаток не введён — заполнится при первом переучёте'
        : '${product.wholeBottles} бут. × ${formatBottleVolume(product.bottleMl)} + ${product.extraMl} мл';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Row(
        children: [
          Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(formatBottleVolume(product.bottleMl), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amountText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: unknown ? colors.tertiary : (danger ? colors.error : colors.onSurface),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              unknown ? 'Минимальный остаток: ${product.minimumMl} мл' : 'Всего ${formatLiters(product.totalMl)} • минимум ${product.minimumMl} мл',
              style: TextStyle(color: danger ? colors.error : null),
            ),
          ],
        ),
      ),
      trailing: editMode ? IconButton(tooltip: 'Редактировать позицию', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)) : null,
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
                            initialValue: categoryId,
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

Future<void> showEditProductDialog(BuildContext context, WarehouseController controller, Product product) async {
  final key = GlobalKey<FormState>();
  final name = TextEditingController(text: product.name);
  final bottleMl = TextEditingController(text: '${product.bottleMl}');
  final minimum = TextEditingController(text: '${product.minimumMl}');
  var categoryId = product.categoryId;
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> save() async {
          if (!(key.currentState?.validate() ?? false)) return;
          setState(() => saving = true);
          try {
            await controller.updateProduct(
              productId: product.id,
              name: name.text,
              categoryId: categoryId,
              bottleMl: int.parse(bottleMl.text),
              minimumMl: int.parse(minimum.text),
            );
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          } catch (e) {
            if (dialogContext.mounted) showErrorSnack(dialogContext, e);
            setState(() => saving = false);
          }
        }

        return AlertDialog(
          title: Text('Редактировать: ${product.name}'),
          content: SizedBox(
            width: 540,
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Название позиции'), validator: requiredText),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: controller.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(growable: false),
                    onChanged: saving ? null : (value) {
                      if (value != null) setState(() => categoryId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TwoFields(
                    first: IntegerField(controller: bottleMl, label: 'Мл в одной бутылке', min: 1),
                    second: IntegerField(controller: minimum, label: 'Минимальный остаток, мл', min: 0),
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Текущий фактический остаток здесь изменить нельзя. Он меняется только поставкой или переучётом.'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('Сохранить'),
            ),
          ],
        );
      },
    ),
  );

  name.dispose();
  bottleMl.dispose();
  minimum.dispose();
}
