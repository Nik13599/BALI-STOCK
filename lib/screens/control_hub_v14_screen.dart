import 'package:flutter/material.dart';

import '../models.dart';
import '../v14_controller.dart';
import 'control_screen.dart';
import 'history_overview_screen.dart';

class ControlHubV14Screen extends StatelessWidget {
  const ControlHubV14Screen({super.key, required this.controller});
  final V14WarehouseController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Контроль')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
        children: [
          _ControlCard(
            icon: Icons.history_toggle_off,
            title: 'История всех операций',
            subtitle: 'Поставки, полные переучёты, списания, перемещения, корректировки и PDF по операциям.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryOverviewScreen(controller: controller))),
          ),
          _ControlCard(
            icon: Icons.center_focus_strong,
            title: 'Точечные переучёты',
            subtitle: '${controller.spotStocktakeHistory.length} операций • было → разница → стало • причина, ФИО и устройство.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SpotStocktakeHistoryScreen(controller: controller))),
          ),
          _ControlCard(
            icon: Icons.tune,
            title: 'Управление складом',
            subtitle: 'Движения, поставщики, места хранения, параметры товаров, закупки и аналитика расхождений.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ControlScreen(controller: controller))),
          ),
          _ControlCard(
            icon: Icons.price_change_outlined,
            title: 'История карточек и цен',
            subtitle: 'Изменения продажных цен и параметров SKU сохраняются в аудите и не удаляют предыдущие значения.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CatalogAuditScreen(controller: controller))),
          ),
          _ControlCard(
            icon: controller.sharedOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            title: 'Синхронизация',
            subtitle: controller.pendingSyncCount > 0
                ? 'Ожидает отправки: ${controller.pendingSyncCount}. Данные будут отправлены автоматически.'
                : controller.sharedOnline
                    ? 'Общая база синхронизирована.'
                    : 'Офлайн. Используется локальная копия склада.',
            onTap: controller.refresh,
          ),
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.all(18),
          leading: CircleAvatar(radius: 25, child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _SpotStocktakeHistoryScreen extends StatelessWidget {
  const _SpotStocktakeHistoryScreen({required this.controller});
  final V14WarehouseController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Точечные переучёты')),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final items = controller.spotStocktakeHistory;
            if (items.isEmpty) {
              return const Center(child: Text('Точечных переучётов пока нет.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final operation = items[i];
                final lines = operation['lines'] is List ? (operation['lines'] as List).whereType<Map>().toList(growable: false) : const <Map>[];
                final line = lines.isEmpty ? null : lines.first;
                final meta = operation['metadata'] is Map ? operation['metadata'] as Map : const {};
                final created = DateTime.tryParse('${operation['created_at'] ?? ''}')?.toLocal();
                final before = _int(line?['before_quantity']);
                final after = _int(line?['after_quantity']);
                final diff = _int(line?['change_quantity']);
                final unit = StockUnitX.fromDb(line?['stock_unit'] as String?);
                final packageSize = _int(line?['package_size'], fallback: 1);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    leading: const CircleAvatar(child: Icon(Icons.center_focus_strong)),
                    title: Text('${line?['product_name'] ?? 'Товар'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${created == null ? '—' : formatDateTime(created)}${operation['employee_name'] == null ? '' : ' • ${operation['employee_name']}'}'),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    children: [
                      _HistoryValue('Было', formatStockParts(before, packageSize, unit)),
                      _HistoryValue('Фактически', formatStockParts(after, packageSize, unit)),
                      _HistoryValue('Разница', '${diff >= 0 ? '+' : '−'}${formatTotalAmount(diff.abs(), unit)}', strong: true),
                      _HistoryValue('Причина', '${meta['reason'] ?? line?['metadata']?['reason'] ?? '—'}'),
                      _HistoryValue('Устройство', '${meta['device'] ?? line?['metadata']?['device'] ?? '—'}'),
                      _HistoryValue('Комментарий', '${operation['comment'] ?? '—'}'),
                      const _HistoryValue('Статус синхронизации', 'Синхронизировано'),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}

class _HistoryValue extends StatelessWidget {
  const _HistoryValue(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700))),
          ],
        ),
      );
}

class _CatalogAuditScreen extends StatelessWidget {
  const _CatalogAuditScreen({required this.controller});
  final V14WarehouseController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('История карточек и цен')),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.catalogAudit.isEmpty) {
              return const Center(child: Text('Изменений карточек пока нет.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: controller.catalogAudit.length,
              itemBuilder: (_, i) {
                final entry = controller.catalogAudit[i];
                final oldPrice = entry.beforeData?['bottle_sale_price'];
                final newPrice = entry.afterData?['bottle_sale_price'];
                final name = entry.afterData?['name'] ?? entry.beforeData?['name'] ?? entry.productKey ?? 'SKU';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text('$name', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${_date(entry.createdAt)}${entry.actor == null ? '' : ' • ${entry.actor}'}'),
                    trailing: oldPrice != newPrice ? Text('${oldPrice ?? '—'} → ${newPrice ?? '—'} BYN', style: const TextStyle(fontWeight: FontWeight.w900)) : const Text('Карточка'),
                  ),
                );
              },
            );
          },
        ),
      );
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String _date(DateTime value) {
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
}
