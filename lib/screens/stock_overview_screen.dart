import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import 'stock_screen.dart' show showAddProductDialog, showEditProductDialog;

class StockOverviewScreen extends StatefulWidget {
  const StockOverviewScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<StockOverviewScreen> createState() => _StockOverviewScreenState();
}

class _StockOverviewScreenState extends State<StockOverviewScreen> {
  bool _editMode = false;
  bool _exportingPdf = false;

  Future<void> _toggleEditMode() async {
    if (_editMode) {
      setState(() => _editMode = false);
      return;
    }
    final allowed = await showOperationPinDialog(context);
    if (!mounted || !allowed) return;
    setState(() => _editMode = true);
  }

  Future<void> _exportPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      await PdfExportService.exportCurrentStock(
        categories: widget.controller.categories,
        products: widget.controller.products,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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
            IconButton(
              tooltip: 'Сохранить текущие остатки в PDF',
              onPressed: controller.loading || _exportingPdf ? null : _exportPdf,
              icon: _exportingPdf
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
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
    const categoryGreen = Color(0xFF39FF6A);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        iconColor: categoryGreen,
        collapsedIconColor: categoryGreen,
        title: Row(
          children: [
            Expanded(
              child: Text(
                category.name.toUpperCase(),
                style: const TextStyle(
                  color: categoryGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .35,
                ),
              ),
            ),
            Text(
              '${products.length} поз.',
              style: const TextStyle(color: categoryGreen, fontWeight: FontWeight.w800),
            ),
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
        : formatStockParts(product.totalAmount, product.packageSize, product.stockUnit);
    final sizeText = product.stockUnit == StockUnit.piece ? 'штучный учёт' : formatPackageSize(product.packageSize, product.stockUnit);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Row(
        children: [
          Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(sizeText, style: Theme.of(context).textTheme.bodySmall),
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
              unknown
                  ? 'Минимальный остаток: ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}'
                  : 'Всего ${formatTotalAmount(product.totalAmount, product.stockUnit)} • минимум ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}',
              style: TextStyle(color: danger ? colors.error : null),
            ),
          ],
        ),
      ),
      trailing: editMode ? IconButton(tooltip: 'Редактировать позицию', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)) : null,
    );
  }
}
