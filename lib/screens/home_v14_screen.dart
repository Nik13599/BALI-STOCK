import 'package:flutter/material.dart';

import '../models.dart';
import '../v14_controller.dart';
import '../widgets/bali_nav_icon.dart';
import '../widgets/common.dart';
import '../widgets/product_code_actions.dart';
import 'product_detail_v14_screen.dart';

class HomeV14Screen extends StatefulWidget {
  const HomeV14Screen({super.key, required this.controller});
  final V14WarehouseController controller;

  @override
  State<HomeV14Screen> createState() => _HomeV14ScreenState();
}

class _HomeV14ScreenState extends State<HomeV14Screen> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _open(Product product) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailV14Screen(controller: widget.controller, product: product)));
  }

  Future<void> _manualCode() async {
    final code = await enterProductCode(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleCode(code);
  }

  Future<void> _scan() async {
    final code = await scanProductCode(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _handleCode(code);
  }

  Future<void> _handleCode(String code) async {
    final product = await resolveProductCode(
      context,
      controller: widget.controller,
      rawCode: code,
    );
    if (mounted && product != null) _open(product);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final q = query.trim().toLowerCase();
        final results = q.isEmpty
            ? <Product>[]
            : widget.controller.products
                .where((p) => '${p.name} ${p.categoryName} ${p.barcode ?? ''}'.toLowerCase().contains(q))
                .take(30)
                .toList(growable: false);
        final low = widget.controller.products.where((x) => x.isLow).length;
        final stockValue = widget.controller.products.fold<double>(0, (sum, p) {
          if (!p.stockInitialized || p.defaultCost == null || p.packageSize <= 0) return sum;
          return sum + p.totalAmount / p.packageSize * p.defaultCost!;
        });

        return Scaffold(
          appBar: AppBar(title: const Text('BALI STOCK')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
            children: [
              Text('Главная', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Выберите товар: скан кода, ручной ввод кода или поиск по названию.', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scan,
                  icon: const BaliNavIcon(kind: BaliNavIconKind.scan, active: true, size: 22),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(productCodeScanActionLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                autofocus: false,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Найти по названию или коду товара'),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(onPressed: _manualCode, icon: const Icon(Icons.pin_outlined), label: const Text('Ввести код товара')),
                  OutlinedButton.icon(
                    onPressed: widget.controller.refresh,
                    icon: const BaliNavIcon(kind: BaliNavIconKind.sync, size: 20),
                    label: const Text('Синхронизировать'),
                  ),
                ],
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Результаты • ${results.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (results.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Совпадений нет.')))
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < results.length; i++) ...[
                          _SearchResult(product: results[i], controller: widget.controller, onTap: () => _open(results[i])),
                          if (i != results.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    MetricCard(label: 'Позиций', value: '${widget.controller.products.length}', icon: Icons.inventory_2),
                    MetricCard(label: 'Критический остаток', value: '$low', icon: Icons.warning_amber_rounded, danger: low > 0),
                    MetricCard(label: 'Стоимость склада', value: '${stockValue.toStringAsFixed(2).replaceAll('.', ',')} BYN', icon: Icons.payments_outlined),
                    MetricCard(label: 'Ожидает синхронизации', value: '${widget.controller.pendingSyncCount}', icon: Icons.cloud_upload_outlined, danger: widget.controller.pendingSyncCount > 0),
                  ],
                ),
                const SizedBox(height: 22),
                const InfoBanner(
                  icon: Icons.offline_bolt_outlined,
                  text: 'Поиск и карточки работают по последней синхронизированной базе. Складские операции сохраняются локально и отправляются в общую базу при появлении интернета.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({required this.product, required this.controller, required this.onTap});
  final Product product;
  final V14WarehouseController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = controller.metaFor(product);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: meta.imageUrl == null ? const Icon(Icons.inventory_2_outlined) : Image.network(meta.imageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
      ),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(product.categoryName, style: const TextStyle(color: Color(0xFF39FF6A), fontWeight: FontWeight.w700)),
      trailing: Text(
        product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'Не введён',
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
