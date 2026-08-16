import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../widgets/common.dart';

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
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (controller.loading) return const Center(child: CircularProgressIndicator());
    if (controller.error != null) {
      return EmptyState(icon: Icons.error_outline, title: 'Не удалось загрузить историю', message: controller.error!);
    }
    if (controller.operations.isEmpty && controller.activeStocktakeDrafts.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'История пока пуста',
        message: 'Здесь без пароля видны всем пользователям проведённые поставки, переучёты и незавершённые черновики.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (controller.activeStocktakeDrafts.isNotEmpty) ...[
          Text('Незавершённые переучёты', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final draft in controller.activeStocktakeDrafts) ...[
            _DraftCard(draft: draft),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
        ],
        if (controller.operations.isNotEmpty) ...[
          Text('Завершённые операции', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final operation in controller.operations) ...[
            _OperationCard(operation: operation),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft});

  final StocktakeDraft draft;

  @override
  Widget build(BuildContext context) {
    final inProgress = draft.status == StocktakeDraftStatus.inProgress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(inProgress ? Icons.play_arrow : Icons.save_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Переучёт', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      Text(draft.employeeName),
                    ],
                  ),
                ),
                Chip(label: Text(draft.status.displayName)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text('Начат: ${formatDateTime(draft.startedAt)}'),
                Text('Заполнено: ${draft.filledCount} из ${draft.totalCount}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Активное время: ${formatDurationSeconds(draft.activeSeconds)}'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: draft.totalCount == 0 ? 0 : draft.filledCount / draft.totalCount),
            const SizedBox(height: 8),
            const Text('Черновик не входит в итоговые результаты, пока сотрудник не завершит переучёт.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation});

  final StockOperation operation;

  @override
  Widget build(BuildContext context) {
    final delivery = operation.type == StockOperationType.delivery;
    final subtitle = delivery
        ? '${formatDateTime(operation.createdAt)} • ${operation.lines.length} позиций'
        : '${operation.employeeName ?? 'Сотрудник не указан'} • ${formatDurationSeconds(operation.activeSeconds)} • ${operation.lines.length} позиций';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: CircleAvatar(child: Icon(delivery ? Icons.local_shipping_outlined : Icons.fact_check_outlined)),
        title: Row(
          children: [
            Expanded(child: Text(delivery ? 'Поставка №${operation.id}' : 'Переучёт №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (!delivery) const Chip(label: Text('Завершён')),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showOperationDetails(context, operation),
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
            if (delivery)
              Text(formatDateTime(operation.createdAt), style: Theme.of(context).textTheme.titleMedium)
            else
              _StocktakeReportHeader(operation: operation),
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

class _StocktakeReportHeader extends StatelessWidget {
  const _StocktakeReportHeader({required this.operation});

  final StockOperation operation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined),
                SizedBox(width: 8),
                Text('Завершён', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                if (operation.employeeName != null) Text('Сотрудник: ${operation.employeeName}'),
                if (operation.startedAt != null) Text('Начало: ${formatDateTime(operation.startedAt!)}'),
                if (operation.completedAt != null) Text('Завершение: ${formatDateTime(operation.completedAt!)}'),
                Text('Активное время: ${formatDurationSeconds(operation.activeSeconds)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('Общий период: ${formatDurationSeconds(operation.totalSeconds)}'),
                Text('Позиций пересчитано: ${operation.lines.length} из ${operation.lines.length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.line, required this.delivery});

  final StockOperationLine line;
  final bool delivery;

  @override
  Widget build(BuildContext context) {
    final initialBalance = !line.beforeInitialized && !delivery;
    final diff = line.changeTotalMl;
    final diffText = '${diff >= 0 ? '+' : '−'}${formatTotalAmount(diff.abs(), line.stockUnit)}';
    final diffColor = diff < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    final descriptor = switch (line.stockUnit) {
      StockUnit.ml => 'бутылка ${formatPackageSize(line.bottleMl, line.stockUnit)}',
      StockUnit.gram => 'упаковка ${formatPackageSize(line.bottleMl, line.stockUnit)}',
      StockUnit.piece => 'штучный учёт',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('${line.categoryName} • $descriptor'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text(initialBalance ? 'Было: остаток не был задан' : 'Было: ${formatStockParts(line.beforeTotalMl, line.bottleMl, line.stockUnit)}'),
              if (initialBalance)
                Text(
                  'Первичный остаток: ${formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
                )
              else
                Text(delivery ? 'Принято: $diffText' : 'Расхождение: $diffText', style: TextStyle(color: diffColor, fontWeight: FontWeight.w700)),
              Text('Стало: ${formatStockParts(line.afterTotalMl, line.bottleMl, line.stockUnit)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
