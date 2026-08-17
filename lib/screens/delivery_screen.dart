import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../services/invoice_scan_service.dart';
import '../widgets/common.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final Map<int, DeliveryDraftLine> _lines = {};
  final InvoiceScanService _scanner = InvoiceScanService();
  bool _saving = false;
  bool _scanning = false;

  Future<void> _addLine() async {
    final line = await showDeliveryLineDialog(context, widget.controller.products);
    if (line == null) return;
    setState(() => _lines[line.product.id] = line);
  }

  Future<void> _scanInvoice() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Распознать накладную', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                subtitle: Text('Распознанные данные всегда можно проверить и исправить вручную перед проведением поставки.'),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Сфотографировать накладную'),
                onTap: () => Navigator.of(sheetContext).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Выбрать фото из галереи'),
                onTap: () => Navigator.of(sheetContext).pop('gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_outlined),
                title: const Text('Ввести поставку вручную'),
                onTap: () => Navigator.of(sheetContext).pop('manual'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'manual') {
      await _addLine();
      return;
    }

    setState(() => _scanning = true);
    try {
      final result = source == 'camera'
          ? await _scanner.scanFromCamera(widget.controller.products)
          : await _scanner.scanFromGallery(widget.controller.products);
      if (!mounted || result == null) return;
      final reviewed = await showInvoiceReviewDialog(context, result, widget.controller.products);
      if (!mounted || reviewed == null) return;
      setState(() {
        for (final line in reviewed) {
          _lines[line.product.id] = line;
        }
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.controller.receiveDelivery(_lines.values.toList(growable: false));
      if (!mounted) return;
      setState(_lines.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Поставка принята. Остатки склада обновлены у всех устройств.')));
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
      builder: (context, _) {
        final products = widget.controller.products;
        final notInitialized = products.where((p) => !p.stockInitialized).length;
        return Scaffold(
          appBar: AppBar(title: const Text('Принять поставку')),
          body: products.isEmpty
              ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Нет складских позиций', message: 'Сначала добавьте позиции в разделе «Склад».')
              : notInitialized > 0
                  ? EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'Сначала проведите первичный переучёт',
                      message: 'У $notInitialized позиций ещё не введён фактический остаток. Поставка станет доступна после полного первичного пересчёта всего склада.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const InfoBanner(
                          icon: Icons.document_scanner_outlined,
                          text: 'Накладную можно распознать камерой или ввести поставку вручную. OCR формирует только черновик: перед проведением обязательно проверьте позиции и количество.',
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving || _scanning ? null : _scanInvoice,
                              icon: _scanning
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.document_scanner_outlined),
                              label: Text(_scanning ? 'Распознавание…' : 'Сканировать накладную'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _saving || _scanning ? null : _addLine,
                              icon: const Icon(Icons.keyboard_outlined),
                              label: const Text('Ввести вручную'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(child: Text('Позиции поставки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                            Text('${_lines.length} поз.', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_lines.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
                            child: const Text('Сфотографируйте накладную либо добавьте товары вручную.', textAlign: TextAlign.center),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (var i = 0; i < _lines.values.length; i++) ...[
                                  Builder(
                                    builder: (context) {
                                      final line = _lines.values.elementAt(i);
                                      final added = line.bottles * line.product.packageSize + line.extraMl;
                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                        title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                        subtitle: Text('${line.product.categoryName} • ${_productUnitLabel(line.product)}'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('+${formatStockParts(added, line.product.packageSize, line.product.stockUnit)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                            IconButton(
                                              tooltip: 'Изменить вручную',
                                              onPressed: _saving
                                                  ? null
                                                  : () async {
                                                      final edited = await showDeliveryLineDialog(context, widget.controller.products, initial: line);
                                                      if (edited != null && mounted) {
                                                        setState(() {
                                                          _lines.remove(line.product.id);
                                                          _lines[edited.product.id] = edited;
                                                        });
                                                      }
                                                    },
                                              icon: const Icon(Icons.edit_outlined),
                                            ),
                                            IconButton(onPressed: _saving ? null : () => setState(() => _lines.remove(line.product.id)), icon: const Icon(Icons.delete_outline)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  if (i != _lines.length - 1) const Divider(height: 1),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _lines.isEmpty || _saving || _scanning ? null : _submit,
                          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                          label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ПРОВЕСТИ ПОСТАВКУ')),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}

String _productUnitLabel(Product product) {
  return switch (product.stockUnit) {
    StockUnit.ml => 'бутылка ${formatPackageSize(product.packageSize, product.stockUnit)}',
    StockUnit.gram => 'упаковка ${formatPackageSize(product.packageSize, product.stockUnit)}',
    StockUnit.piece => 'штучный учёт',
  };
}

Future<List<DeliveryDraftLine>?> showInvoiceReviewDialog(
  BuildContext context,
  InvoiceScanResult scan,
  List<Product> products,
) async {
  final rows = scan.lines
      .map((line) => _InvoiceReviewRow(
            sourceText: line.sourceText,
            productId: line.product?.id,
            quantity: line.quantity > 0 ? line.quantity : 1,
            confidence: line.confidence,
          ))
      .toList();

  return showDialog<List<DeliveryDraftLine>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        void addManualRow() => setState(() => rows.add(_InvoiceReviewRow(sourceText: 'Добавлено вручную', productId: null, quantity: 1, confidence: 0)));

        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(onPressed: () => Navigator.of(dialogContext).pop(), icon: const Icon(Icons.close)),
              title: const Text('Проверка накладной'),
              actions: [TextButton.icon(onPressed: addManualRow, icon: const Icon(Icons.add), label: const Text('Добавить строку'))],
            ),
            body: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const InfoBanner(
                  icon: Icons.verified_user_outlined,
                  text: 'Проверьте распознанные данные. Ничего не будет добавлено на склад, пока вы не подтвердите этот список и затем не проведёте поставку.',
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  EmptyState(
                    icon: Icons.manage_search,
                    title: 'Позиции автоматически не найдены',
                    message: 'Добавьте строки вручную — фотография всё равно останется основанием для проверки поставки.',
                    action: FilledButton.icon(onPressed: addManualRow, icon: const Icon(Icons.add), label: const Text('Добавить позицию')),
                  )
                else
                  for (var i = 0; i < rows.length; i++) ...[
                    _InvoiceReviewCard(
                      row: rows[i],
                      products: products,
                      onChanged: (value) => setState(() => rows[i] = value),
                      onDelete: () => setState(() => rows.removeAt(i)),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () {
                          final valid = rows.where((r) => r.productId != null && r.quantity > 0).toList();
                          if (valid.length != rows.length) {
                            showErrorSnack(dialogContext, 'Укажите товар и количество для каждой строки либо удалите ненужные строки.');
                            return;
                          }
                          final result = <DeliveryDraftLine>[];
                          for (final row in valid) {
                            final product = products.firstWhere((p) => p.id == row.productId);
                            result.add(DeliveryDraftLine(product: product, bottles: row.quantity, extraMl: 0));
                          }
                          Navigator.of(dialogContext).pop(result);
                        },
                  icon: const Icon(Icons.check),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('ПРИНЯТЬ РАСПОЗНАННЫЙ СПИСОК')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _InvoiceReviewRow {
  const _InvoiceReviewRow({required this.sourceText, required this.productId, required this.quantity, required this.confidence});

  final String sourceText;
  final int? productId;
  final int quantity;
  final double confidence;

  _InvoiceReviewRow copyWith({int? productId, bool clearProduct = false, int? quantity}) => _InvoiceReviewRow(
        sourceText: sourceText,
        productId: clearProduct ? null : (productId ?? this.productId),
        quantity: quantity ?? this.quantity,
        confidence: confidence,
      );
}

class _InvoiceReviewCard extends StatelessWidget {
  const _InvoiceReviewCard({required this.row, required this.products, required this.onChanged, required this.onDelete});

  final _InvoiceReviewRow row;
  final List<Product> products;
  final ValueChanged<_InvoiceReviewRow> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final confident = row.productId != null && row.confidence >= .78;
    final color = row.productId == null
        ? Theme.of(context).colorScheme.error
        : confident
            ? const Color(0xFF39FF6A)
            : Colors.amber;
    final label = row.productId == null
        ? 'Не найдено'
        : confident
            ? 'Уверенное совпадение'
            : 'Проверьте совпадение';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(row.sourceText, style: const TextStyle(fontWeight: FontWeight.w800))),
                Chip(label: Text(label, style: TextStyle(color: color))),
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: row.productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Позиция склада'),
              items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name}'))).toList(growable: false),
              onChanged: (value) => onChanged(row.copyWith(productId: value, clearProduct: value == null)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: '${row.quantity}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Количество по накладной'),
              onChanged: (value) => onChanged(row.copyWith(quantity: int.tryParse(value) ?? 0)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<DeliveryDraftLine?> showDeliveryLineDialog(BuildContext context, List<Product> products, {DeliveryDraftLine? initial}) async {
  if (products.isEmpty) return null;
  var productId = initial?.product.id ?? products.first.id;
  final whole = TextEditingController(text: '${initial?.bottles ?? 0}');
  final extra = TextEditingController(text: '${initial?.extraMl ?? 0}');
  final key = GlobalKey<FormState>();

  final result = await showDialog<DeliveryDraftLine>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final product = products.firstWhere((p) => p.id == productId);
        final wholeLabel = switch (product.stockUnit) {
          StockUnit.ml => 'Бутылок принято',
          StockUnit.gram => 'Упаковок принято',
          StockUnit.piece => 'Количество, шт.',
        };
        final extraLabel = product.stockUnit == StockUnit.ml ? 'Доп. объём, мл' : 'Доп. остаток, г';

        return AlertDialog(
          title: Text(initial == null ? 'Позиция поставки' : 'Редактировать позицию'),
          content: SizedBox(
            width: 540,
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Позиция'),
                    items: products
                        .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.categoryName} — ${p.name} (${_productUnitLabel(p)})')))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          productId = value;
                          if (initial == null) {
                            whole.text = '0';
                            extra.text = '0';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (product.stockUnit == StockUnit.piece)
                    IntegerField(controller: whole, label: wholeLabel, min: 0)
                  else
                    TwoFields(
                      first: IntegerField(controller: whole, label: wholeLabel, min: 0),
                      second: IntegerField(
                        controller: extra,
                        label: extraLabel,
                        min: 0,
                        validator: (value) {
                          final base = integerValidator(value, min: 0);
                          if (base != null) return base;
                          final parsed = int.tryParse(value ?? '');
                          if (parsed != null && parsed >= product.packageSize) return 'Меньше ${product.packageSize} ${product.stockUnit.symbol}';
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
                if (!(key.currentState?.validate() ?? false)) return;
                final wholeCount = int.parse(whole.text);
                final extraAmount = product.stockUnit == StockUnit.piece ? 0 : int.parse(extra.text);
                if (wholeCount == 0 && extraAmount == 0) {
                  showErrorSnack(dialogContext, 'Количество поставки не может быть нулевым');
                  return;
                }
                Navigator.of(dialogContext).pop(DeliveryDraftLine(product: product, bottles: wholeCount, extraMl: extraAmount));
              },
              child: Text(initial == null ? 'Добавить' : 'Сохранить'),
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
