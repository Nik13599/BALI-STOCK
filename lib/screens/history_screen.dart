import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

IconData operationIcon(StockOperationType type) => switch (type) {
      StockOperationType.delivery => Icons.local_shipping_outlined,
      StockOperationType.stocktake => Icons.fact_check_outlined,
      StockOperationType.spotStocktake => Icons.center_focus_strong_outlined,
      StockOperationType.writeoff => Icons.remove_circle_outline,
      StockOperationType.transfer => Icons.swap_horiz,
      StockOperationType.correction => Icons.tune,
    };

Future<void> showOperationDetails(
  BuildContext context,
  StockOperation operation, {
  WarehouseController? controller,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () => Navigator.of(dialogContext).pop(), icon: const Icon(Icons.close)),
          title: Text('${operation.type.displayName} №${operation.id}'),
          actions: [
            IconButton(
              tooltip: 'Сохранить PDF',
              onPressed: () async {
                try {
                  await PdfExportService.exportOperation(operation);
                } catch (e) {
                  if (dialogContext.mounted) showErrorSnack(dialogContext, e);
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            if (controller != null && operation.type != StockOperationType.correction)
              IconButton(
                tooltip: 'Создать корректировку',
                onPressed: () => _startCorrection(dialogContext, controller, operation),
                icon: const Icon(Icons.rule_folder_outlined),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _OperationHeader(operation: operation),
            if (operation.type == StockOperationType.stocktake) ...[
              const SizedBox(height: 16),
              _VarianceSummary(operation: operation),
            ],
            const SizedBox(height: 18),
            for (var i = 0; i < operation.lines.length; i++) ...[
              _HistoryLine(line: operation.lines[i], type: operation.type),
              if (i != operation.lines.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      ),
    ),
  );
}

class _OperationHeader extends StatelessWidget {
  const _OperationHeader({required this.operation});
  final StockOperation operation;

  @override
  Widget build(BuildContext context) {
    final values = <Widget>[
      Text('Дата: ${formatDateTime(operation.createdAt)}'),
      if (operation.employeeName?.isNotEmpty == true) Text('Сотрудник: ${operation.employeeName}'),
      if (operation.supplierName?.isNotEmpty == true) Text('Поставщик: ${operation.supplierName}'),
      if (operation.documentNumber?.isNotEmpty == true) Text('Документ: ${operation.documentNumber}'),
      if (operation.sourceLocationName?.isNotEmpty == true) Text('Откуда: ${operation.sourceLocationName}'),
      if (operation.targetLocationName?.isNotEmpty == true) Text('Куда: ${operation.targetLocationName}'),
      if (operation.totalValue != null) Text('Сумма: ${formatMoney(operation.totalValue)}', style: const TextStyle(fontWeight: FontWeight.w900)),
      if (operation.correctionOf?.isNotEmpty == true) Text('Корректирует операцию: ${operation.correctionOf}'),
      Text('Позиций: ${operation.lines.length}'),
    ];
    if (operation.type == StockOperationType.stocktake) {
      if (operation.startedAt != null) values.add(Text('Начало: ${formatDateTime(operation.startedAt!)}'));
      if (operation.completedAt != null) values.add(Text('Завершение: ${formatDateTime(operation.completedAt!)}'));
      values.add(Text('Активное время: ${formatDurationSeconds(operation.activeSeconds)}', style: const TextStyle(fontWeight: FontWeight.w900)));
      values.add(Text('Общий период: ${formatDurationSeconds(operation.totalSeconds)}'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(operationIcon(operation.type))),
                const SizedBox(width: 10),
                Expanded(child: Text(operation.type.displayName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
                const Chip(avatar: Icon(Icons.lock_outline, size: 17), label: Text('Неизменяемая запись')),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 22, runSpacing: 8, children: values),
            if (operation.comment?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text('Комментарий: ${operation.comment}'),
            ],
            const SizedBox(height: 10),
            const Text(
              'Операция остаётся в истории навсегда. Ошибки исправляются новой корректирующей записью, поэтому аудит движения товара не теряется.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _VarianceSummary extends StatelessWidget {
  const _VarianceSummary({required this.operation});
  final StockOperation operation;

  @override
  Widget build(BuildContext context) {
    final shortages = operation.lines.where((line) => line.beforeInitialized && line.changeTotalMl < 0).toList(growable: false)
      ..sort((a, b) => a.changeTotalMl.compareTo(b.changeTotalMl));
    final surplus = operation.lines.where((line) => line.beforeInitialized && line.changeTotalMl > 0).toList(growable: false)
      ..sort((a, b) => b.changeTotalMl.compareTo(a.changeTotalMl));
    final exact = operation.lines.where((line) => line.beforeInitialized && line.changeTotalMl == 0).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Анализ расхождений', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(avatar: const Icon(Icons.trending_down, size: 18), label: Text('Недостача: ${shortages.length}')),
                Chip(avatar: const Icon(Icons.trending_up, size: 18), label: Text('Излишек: ${surplus.length}')),
                Chip(avatar: const Icon(Icons.check, size: 18), label: Text('Без расхождения: $exact')),
              ],
            ),
            if (shortages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Крупнейшая недостача: ${shortages.first.productName} — ${formatTotalAmount(shortages.first.changeTotalMl.abs(), shortages.first.stockUnit)}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w800)),
            ],
            if (surplus.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('Крупнейший излишек: ${surplus.first.productName} +${formatTotalAmount(surplus.first.changeTotalMl, surplus.first.stockUnit)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.line, required this.type});
  final StockOperationLine line;
  final StockOperationType type;

  @override
  Widget build(BuildContext context) {
    final inventoryType = type == StockOperationType.stocktake || type == StockOperationType.spotStocktake;
    final initialBalance = !line.beforeInitialized && inventoryType;
    final diff = line.changeTotalMl;
    final diffText = '${diff >= 0 ? '+' : '−'}${formatTotalAmount(diff.abs(), line.stockUnit)}';
    final diffColor = diff < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    final descriptor = switch (line.stockUnit) {
      StockUnit.ml => 'бутылка ${formatPackageSize(line.bottleMl, line.stockUnit)}',
      StockUnit.gram => 'упаковка ${formatPackageSize(line.bottleMl, line.stockUnit)}',
      StockUnit.piece => 'штучный учёт',
    };
    final actionText = switch (type) {
      StockOperationType.delivery => 'Принято: $diffText',
      StockOperationType.stocktake => initialBalance ? 'Первичный остаток: ${formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit)}' : 'Расхождение: $diffText',
      StockOperationType.spotStocktake => initialBalance ? 'Первичный точечный остаток: ${formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit)}' : 'Точечное расхождение: $diffText',
      StockOperationType.writeoff => 'Списано: $diffText',
      StockOperationType.transfer => 'Перемещено между местами хранения',
      StockOperationType.correction => 'Коррекция: $diffText',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          Text('${line.categoryName} • $descriptor'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (type != StockOperationType.transfer)
                Text(initialBalance ? 'Было: остаток не был задан' : 'Было: ${formatStockParts(line.beforeTotalMl, line.bottleMl, line.stockUnit)}'),
              Text(actionText, style: TextStyle(color: diffColor, fontWeight: FontWeight.w800)),
              if (!initialBalance && type != StockOperationType.transfer)
                Text('Стало: ${formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit)}', style: const TextStyle(fontWeight: FontWeight.w900)),
              if (line.unitCost != null) Text('Цена: ${formatMoney(line.unitCost)}'),
              if (line.lineValue != null) Text('Сумма: ${formatMoney(line.lineValue)}'),
            ],
          ),
          if (line.comment?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('Комментарий: ${line.comment}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

Future<void> _startCorrection(BuildContext context, WarehouseController controller, StockOperation operation) async {
  final pin = await showOperationPinValueDialog(context);
  if (!context.mounted || pin == null) return;
  try {
    await controller.setOperationSessionPin(pin);
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return;
  }
  if (!context.mounted) return;

  final employee = TextEditingController();
  final reason = TextEditingController();
  final deltaControllers = <int, TextEditingController>{};
  final lineProducts = <Product>[];
  for (final line in operation.lines) {
    Product? product;
    for (final item in controller.products) {
      if (item.id == line.productId || item.name.toLowerCase() == line.productName.toLowerCase()) {
        product = item;
        break;
      }
    }
    if (product == null || lineProducts.any((item) => item.id == product!.id)) continue;
    lineProducts.add(product);
    deltaControllers[product.id] = TextEditingController(text: '0');
  }
  if (lineProducts.isEmpty) {
    showErrorSnack(context, 'Не удалось сопоставить позиции операции с текущим каталогом.');
    employee.dispose();
    reason.dispose();
    return;
  }

  var saving = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Корректировка операции №${operation.id}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InfoBanner(icon: Icons.info_outline, text: 'Исходная операция не изменится. Будет создана новая запись «Корректировка». Введите изменение в базовой единице товара: плюс добавляет остаток, минус уменьшает.'),
                const SizedBox(height: 12),
                TextField(controller: employee, decoration: const InputDecoration(labelText: 'Сотрудник, ФИО *')),
                const SizedBox(height: 10),
                TextField(controller: reason, decoration: const InputDecoration(labelText: 'Причина корректировки *')),
                const SizedBox(height: 16),
                for (final product in lineProducts) ...[
                  TextField(
                    controller: deltaControllers[product.id],
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                    decoration: InputDecoration(
                      labelText: '${product.name} — изменение, ${product.stockUnit.symbol}',
                      helperText: 'Например: -250 или +500',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final actor = employee.text.trim();
                    final why = reason.text.trim();
                    final deltas = <Product, int>{};
                    for (final product in lineProducts) {
                      final value = int.tryParse(deltaControllers[product.id]!.text.replaceFirst('+', '')) ?? 0;
                      if (value != 0) deltas[product] = value;
                    }
                    if (actor.isEmpty || why.isEmpty || deltas.isEmpty) {
                      showErrorSnack(dialogContext, 'Укажите ФИО, причину и хотя бы одну ненулевую корректировку.');
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      await controller.correctOperation(operation: operation, employee: actor, reason: why, deltas: deltas, locationId: controller.primaryLocation?.id);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Корректировка создана отдельной операцией.')));
                    } catch (e) {
                      if (dialogContext.mounted) showErrorSnack(dialogContext, e);
                      setState(() => saving = false);
                    }
                  },
            icon: const Icon(Icons.tune),
            label: const Text('Создать корректировку'),
          ),
        ],
      ),
    ),
  );
  employee.dispose();
  reason.dispose();
  for (final controller in deltaControllers.values) {
    controller.dispose();
  }
}
