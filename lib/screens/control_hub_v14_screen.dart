import 'package:flutter/material.dart';

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
            subtitle: 'Поставки, полные и точечные переучёты, списания, перемещения, корректировки и PDF по операциям.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryOverviewScreen(controller: controller))),
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

String _date(DateTime value) {
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
}
