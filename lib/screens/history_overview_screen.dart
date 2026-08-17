import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import 'history_screen.dart' show operationIcon, showOperationDetails;

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
          actions: [
            Chip(
              avatar: Icon(controller.sharedOnline ? Icons.cloud_done : Icons.cloud_off, size: 17),
              label: Text(controller.sharedOnline ? 'Общая база' : 'Офлайн-кэш'),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Обновить', onPressed: controller.refresh, icon: const Icon(Icons.refresh)),
          ],
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
        message: 'Здесь без пароля видны всем пользователям поставки, переучёты, списания, перемещения, корректировки и незавершённые черновики.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InfoBanner(
          icon: Icons.verified_user_outlined,
          text: 'Проведённые операции не удаляются и не переписываются. Если в документе допущена ошибка, создаётся отдельная корректирующая операция — исходная запись остаётся в истории.',
        ),
        const SizedBox(height: 18),
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
              onOpen: () => showOperationDetails(context, operation, controller: controller),
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
  const _OperationCard({required this.operation, required this.onPdf, required this.onOpen});

  final StockOperation operation;
  final VoidCallback onPdf;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      formatDateTime(operation.createdAt),
      if (operation.employeeName?.isNotEmpty == true) operation.employeeName!,
      '${operation.lines.length} поз.',
      if (operation.supplierName?.isNotEmpty == true) operation.supplierName!,
      if (operation.documentNumber?.isNotEmpty == true) '№ ${operation.documentNumber}',
      if (operation.type == StockOperationType.stocktake) formatDurationSeconds(operation.activeSeconds),
      if (operation.sourceLocationName?.isNotEmpty == true && operation.targetLocationName?.isNotEmpty == true)
        '${operation.sourceLocationName} → ${operation.targetLocationName}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                leading: CircleAvatar(child: Icon(operationIcon(operation.type))),
                title: Row(
                  children: [
                    Expanded(child: Text('${operation.type.displayName} №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w900))),
                    if (operation.type == StockOperationType.stocktake) const Chip(label: Text('Завершён')),
                    if (operation.type == StockOperationType.correction) const Chip(label: Text('Коррекция')),
                  ],
                ),
                subtitle: Text(details.join(' • ')),
                onTap: onOpen,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Сохранить эту операцию в PDF',
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(tooltip: 'Открыть подробности', onPressed: onOpen, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}
