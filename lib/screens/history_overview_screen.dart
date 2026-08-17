import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import 'history_screen.dart' show showOperationDetails;

class HistoryOverviewScreen extends StatelessWidget {
  const HistoryOverviewScreen({super.key, required this.controller});

  final WarehouseController controller;

  Future<void> _exportOperation(BuildContext context, StockOperation operation) async {
    try {
      await PdfExportService.exportOperation(operation);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('История операций'),
          actions: [IconButton(tooltip: 'Обновить', onPressed: controller.refresh, icon: const Icon(Icons.refresh))],
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
          Row(
            children: [
              Expanded(child: Text('Завершённые операции', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              const Icon(Icons.picture_as_pdf_outlined, size: 20),
              const SizedBox(width: 6),
              const Text('PDF по каждой операции'),
            ],
          ),
          const SizedBox(height: 10),
          for (final operation in controller.operations) ...[
            _OperationCard(
              operation: operation,
              onPdf: () => _exportOperation(context, operation),
            ),
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
            const Text('Черновик не входит в итоговые результаты и не формирует итоговый PDF, пока сотрудник не завершит переучёт.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation, required this.onPdf});

  final StockOperation operation;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final delivery = operation.type == StockOperationType.delivery;
    final subtitle = delivery
        ? '${formatDateTime(operation.createdAt)} • ${operation.lines.length} позиций'
        : '${operation.employeeName ?? 'Сотрудник не указан'} • ${formatDurationSeconds(operation.activeSeconds)} • ${operation.lines.length} позиций';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                leading: CircleAvatar(child: Icon(delivery ? Icons.local_shipping_outlined : Icons.fact_check_outlined)),
                title: Row(
                  children: [
                    Expanded(child: Text(delivery ? 'Поставка №${operation.id}' : 'Переучёт №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    if (!delivery) const Chip(label: Text('Завершён')),
                  ],
                ),
                subtitle: Text(subtitle),
                onTap: () => showOperationDetails(context, operation),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Сохранить эту операцию в PDF',
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Открыть подробности',
              onPressed: () => showOperationDetails(context, operation),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
