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
    if (controller.operations.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'История пока пуста',
        message: 'Здесь без пароля видны всем пользователям все проведённые поставки и переучёты.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: controller.operations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final operation = controller.operations[index];
        final delivery = operation.type == StockOperationType.delivery;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            leading: CircleAvatar(child: Icon(delivery ? Icons.local_shipping_outlined : Icons.fact_check_outlined)),
            title: Text(delivery ? 'Поставка №${operation.id}' : 'Переучёт №${operation.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${formatDateTime(operation.createdAt)} • ${operation.lines.length} позиций'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showOperationDetails(context, operation),
          ),
        );
      },
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
            Text(formatDateTime(operation.createdAt), style: Theme.of(context).textTheme.titleMedium),
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

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.line, required this.delivery});

  final StockOperationLine line;
  final bool delivery;

  @override
  Widget build(BuildContext context) {
    final diff = line.changeTotalMl;
    final diffText = '${diff >= 0 ? '+' : '−'}${formatLiters(diff.abs())}';
    final diffColor = diff < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('${line.categoryName} • тара ${formatBottleVolume(line.bottleMl)}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text('Было: ${formatStockParts(line.beforeTotalMl, line.bottleMl)}'),
              Text(delivery ? 'Принято: $diffText' : 'Расхождение: $diffText', style: TextStyle(color: diffColor, fontWeight: FontWeight.w700)),
              Text('Стало: ${formatStockParts(line.afterTotalMl, line.bottleMl)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}
