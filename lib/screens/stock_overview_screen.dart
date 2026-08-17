import 'dart:io';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';
import 'product_code_scanner_screen.dart';
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

  bool get _cameraScannerAvailable => Platform.isAndroid || Platform.isIOS;

  Future<void> _toggleEditMode() async {
    if (_editMode) {
      setState(() => _editMode = false);
      return;
    }
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return;
    await widget.controller.setOperationSessionPin(pin);
    if (!mounted) return;
    if (!widget.controller.sharedOnline) {
      showErrorSnack(context, StateError(widget.controller.syncWarning ?? 'Редактирование требует связи с общей базой.'));
      return;
    }
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

  String _normalizeCode(String value) => value.trim().toLowerCase();

  Product? _findProductByCode(String code) {
    final wanted = _normalizeCode(code);
    for (final product in widget.controller.products) {
      final saved = product.barcode?.trim();
      if (saved != null && saved.isNotEmpty && _normalizeCode(saved) == wanted) return product;
    }
    return null;
  }

  Future<void> _scanProductCode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ProductCodeScannerScreen()),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleProductCode(code.trim());
  }

  Future<void> _enterProductCode() async {
    final code = await showTextValueDialog(context, 'Найти товар по коду', 'Штрихкод или QR-код');
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleProductCode(code.trim());
  }

  Future<void> _handleProductCode(String code) async {
    final product = _findProductByCode(code);
    if (product != null) {
      await _showProductResult(product, code);
      return;
    }

    final bind = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Код не найден'),
        content: SelectableText('Код «$code» пока не привязан ни к одному товару. Можно сразу привязать его к существующей позиции.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Закрыть')),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.link),
            label: const Text('Привязать к товару'),
          ),
        ],
      ),
    );
    if (!mounted || bind != true) return;
    await _bindCodeToProduct(code);
  }

  Future<bool> _ensureProtectedSession() async {
    if (widget.controller.hasOperationSession && widget.controller.sharedOnline) return true;
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return false;
    await widget.controller.setOperationSessionPin(pin);
    if (!mounted) return false;
    if (!widget.controller.sharedOnline) {
      showErrorSnack(context, StateError(widget.controller.syncWarning ?? 'Для привязки кода нужна связь с общей базой.'));
      return false;
    }
    return true;
  }

  Future<Product?> _chooseProductForCode() async {
    var query = '';
    return showDialog<Product>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setInnerState) {
          final normalized = query.trim().toLowerCase();
          final products = widget.controller.products.where((product) {
            if (normalized.isEmpty) return true;
            return '${product.name} ${product.categoryName}'.toLowerCase().contains(normalized);
          }).toList(growable: false);
          return AlertDialog(
            title: const Text('К какому товару привязать код?'),
            content: SizedBox(
              width: 560,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Поиск по названию'),
                    onChanged: (value) => setInnerState(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ListTile(
                          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(product.categoryName),
                          trailing: (product.barcode ?? '').trim().isEmpty
                              ? null
                              : const Icon(Icons.qr_code_2, size: 20),
                          onTap: () => Navigator.of(dialogContext).pop(product),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bindCodeToProduct(String code) async {
    if (!await _ensureProtectedSession()) return;
    if (!mounted) return;
    final product = await _chooseProductForCode();
    if (!mounted || product == null) return;

    final current = product.barcode?.trim();
    if (current != null && current.isNotEmpty && _normalizeCode(current) != _normalizeCode(code)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Заменить код товара?'),
          content: Text('${product.name} уже имеет код «$current». Заменить его на «$code»?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Нет')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Заменить')),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }

    final employee = await showTextValueDialog(context, 'Кто привязывает код?', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;

    try {
      await widget.controller.updateProductControl(
        product: product,
        employee: employee.trim(),
        minimumAmount: product.minimumAmount,
        targetAmount: product.targetAmount,
        varianceRecheckAmount: product.varianceRecheckAmount,
        barcode: code,
        defaultCost: product.defaultCost,
        costCurrency: product.costCurrency,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Код привязан к «${product.name}»')));
      final updated = _findProductByCode(code);
      if (updated != null) await _showProductResult(updated, code);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _showProductResult(Product product, String code) async {
    final unknown = !product.stockInitialized;
    final amount = unknown
        ? 'Остаток ещё не введён'
        : formatStockParts(product.totalAmount, product.packageSize, product.stockUnit);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(product.name)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.categoryName, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              Text(amount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Минимальный остаток: ${formatMinimumAmount(product.minimumAmount, product.stockUnit)}'),
              if (product.targetAmount > 0) Text('Целевой остаток: ${formatTotalAmount(product.targetAmount, product.stockUnit)}'),
              const SizedBox(height: 12),
              SelectableText('Код: $code'),
            ],
          ),
        ),
        actions: [
          if (_editMode)
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                showEditProductDialog(context, widget.controller, product);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Редактировать'),
            ),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Готово')),
        ],
      ),
    );
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
            if (_cameraScannerAvailable)
              IconButton(
                tooltip: 'Сканировать QR / штрихкод',
                onPressed: controller.loading ? null : _scanProductCode,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            IconButton(
              tooltip: 'Найти по коду вручную',
              onPressed: controller.loading ? null : _enterProductCode,
              icon: const Icon(Icons.numbers),
            ),
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
    final code = product.barcode?.trim();

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
            if (code != null && code.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('Код: $code', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      trailing: editMode ? IconButton(tooltip: 'Редактировать позицию', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)) : null,
    );
  }
}
