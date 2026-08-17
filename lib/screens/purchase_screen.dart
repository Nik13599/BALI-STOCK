import 'package:flutter/material.dart';

import '../controller.dart';
import '../data/remote_stock_service.dart';
import '../models.dart';
import '../purchase_models.dart';
import '../services/pdf_export_service.dart';
import '../widgets/common.dart';
import '../widgets/pin_value_dialog.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, required this.controller});

  final WarehouseController controller;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final RemoteStockService _remote = RemoteStockService();
  List<StockPurchaseRequest> _requests = const [];
  bool _loadingRequests = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadRequests());
  }

  Future<void> _reloadRequests() async {
    if (_loadingRequests) return;
    setState(() => _loadingRequests = true);
    try {
      final snapshot = await _remote.fetchSnapshot();
      final raw = snapshot['purchase_requests'];
      final requests = raw is List
          ? raw.whereType<Map>().map(StockPurchaseRequest.fromJson).toList(growable: false)
          : <StockPurchaseRequest>[];
      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<String?> _authorize() async {
    final pin = await showOperationPinValueDialog(context);
    if (!mounted || pin == null) return null;
    try {
      await _remote.authorize(pin);
      await widget.controller.setOperationSessionPin(pin);
      return pin;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return null;
    }
  }

  Future<void> _exportPdf() async {
    try {
      await PdfExportService.exportPurchaseList(
        items: widget.controller.purchaseSuggestions,
        suppliers: widget.controller.suppliers,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _createRequests() async {
    final items = widget.controller.purchaseSuggestions;
    if (items.isEmpty) return;
    final pin = await _authorize();
    if (!mounted || pin == null) return;
    final employee = await showTextValueDialog(context, 'Создать заявки на закупку', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;

    final grouped = <String?, List<PurchaseSuggestion>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.preferredSupplier, () => []).add(item);
    }
    try {
      var created = 0;
      for (final entry in grouped.entries) {
        await _remote.createPurchaseRequest(
          pin: pin,
          employee: employee.trim(),
          items: entry.value,
          supplierId: entry.key,
          comment: entry.key == null ? 'Поставщик не назначен — требуется ручной выбор.' : 'Автоматически сформировано по минимальным/целевым остаткам.',
        );
        created++;
      }
      await widget.controller.refresh();
      await _reloadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Создано заявок: $created. Они сохранены в общей базе.')));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _changeStatus(StockPurchaseRequest request, String status) async {
    final pin = await _authorize();
    if (!mounted || pin == null) return;
    final employee = await showTextValueDialog(context, 'Изменить статус заявки', 'ФИО сотрудника');
    if (!mounted || employee == null || employee.trim().isEmpty) return;
    try {
      await _remote.setPurchaseRequestStatus(pin: pin, id: request.id, status: status, employee: employee.trim());
      await widget.controller.refresh();
      await _reloadRequests();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Закупки'),
          actions: [
            IconButton(onPressed: _reloadRequests, tooltip: 'Обновить заявки', icon: const Icon(Icons.refresh)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Row(
              children: [
                Expanded(child: Text('Автоматическая заявка', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                OutlinedButton.icon(onPressed: widget.controller.purchaseSuggestions.isEmpty ? null : _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: widget.controller.purchaseSuggestions.isEmpty ? null : _createRequests, icon: const Icon(Icons.playlist_add_check), label: const Text('Создать заявки')),
              ],
            ),
            const SizedBox(height: 10),
            const InfoBanner(
              icon: Icons.auto_awesome,
              text: 'Позиции ниже минимума автоматически доводятся в рекомендации до целевого остатка. Товар может иметь несколько поставщиков; для заявки используется основной. Если основной не назначен — создаётся отдельная заявка без поставщика.',
            ),
            const SizedBox(height: 14),
            _suggestions(context),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(child: Text('Журнал заявок', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                if (_loadingRequests) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 10),
            if (_requests.isEmpty && !_loadingRequests)
              const EmptyState(icon: Icons.shopping_cart_outlined, title: 'Заявок пока нет', message: 'Созданные заявки будут видны всем устройствам и останутся в общем журнале.')
            else
              for (final request in _requests) ...[
                _RequestCard(
                  request: request,
                  supplierName: _supplierName(request.supplierId),
                  productName: _productName,
                  onStatus: (status) => _changeStatus(request, status),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _suggestions(BuildContext context) {
    final items = widget.controller.purchaseSuggestions;
    if (items.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Все инициализированные позиции выше минимального остатка.')));
    }
    final grouped = <String, List<PurchaseSuggestion>>{};
    for (final item in items) {
      final supplier = _supplierName(item.preferredSupplier) ?? 'Поставщик не назначен';
      grouped.putIfAbsent(supplier, () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in grouped.entries) ...[
          Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF39FF6A))),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  Builder(builder: (context) {
                    final item = entry.value[i];
                    final packages = item.stockUnit == StockUnit.piece
                        ? item.suggestedQuantity
                        : (item.suggestedQuantity / item.packageSize).ceil();
                    return ListTile(
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${item.categoryName} • сейчас ${formatStockParts(item.currentQuantity, item.packageSize, item.stockUnit)} • минимум ${formatMinimumAmount(item.minimumAmount, item.stockUnit)}${item.targetAmount > 0 ? ' • цель ${formatMinimumAmount(item.targetAmount, item.stockUnit)}' : ''}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Заказать: $packages ${item.stockUnit.packageLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          if (item.lastPrice != null) Text('≈ ${formatMoney(item.lastPrice! * packages, item.currency)}'),
                        ],
                      ),
                    );
                  }),
                  if (i != entry.value.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  String? _supplierName(String? id) {
    if (id == null) return null;
    for (final supplier in widget.controller.suppliers) {
      if (supplier.id == id) return supplier.name;
    }
    return null;
  }

  String _productName(String key) {
    for (final product in widget.controller.products) {
      final productKey = '${product.name.trim().toLowerCase()}|${product.stockUnit.dbValue}|${product.packageSize}';
      if (productKey == key) return product.name;
    }
    return key.split('|').first;
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.supplierName,
    required this.productName,
    required this.onStatus,
  });

  final StockPurchaseRequest request;
  final String? supplierName;
  final String Function(String) productName;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.shopping_cart_checkout)),
        title: Text('${supplierName ?? 'Без поставщика'} • ${request.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${formatDateTime(request.createdAt)} • ${request.lines.length} поз.${request.createdBy == null ? '' : ' • ${request.createdBy}'}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Изменить статус',
          onSelected: onStatus,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'draft', child: Text('Черновик')),
            PopupMenuItem(value: 'sent', child: Text('Отправлена')),
            PopupMenuItem(value: 'received', child: Text('Получена')),
            PopupMenuItem(value: 'cancelled', child: Text('Отменена')),
          ],
        ),
        children: [
          if (request.comment?.isNotEmpty == true)
            Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 8), child: Align(alignment: Alignment.centerLeft, child: Text(request.comment!))),
          for (final line in request.lines)
            ListTile(
              dense: true,
              title: Text(productName(line.productKey)),
              trailing: Text('${line.requestedQuantity} баз. ед.', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
