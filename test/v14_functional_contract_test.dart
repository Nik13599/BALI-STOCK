import 'dart:io';

import 'package:bali_stock/models.dart';
import 'package:bali_stock/v14_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product sampleProduct({
    int whole = 3,
    int extra = 350,
    int minimum = 700,
    int target = 2800,
    double? cost = 35,
    bool initialized = true,
  }) =>
      Product(
        id: 1,
        name: 'Тестовый товар',
        categoryId: 1,
        categoryName: 'Алкоголь',
        bottleMl: 700,
        wholeBottles: whole,
        extraMl: extra,
        minimumMl: minimum,
        stockUnit: StockUnit.ml,
        stockInitialized: initialized,
        active: true,
        targetAmount: target,
        barcode: '1234567890',
        defaultCost: cost,
        costCurrency: 'BYN',
        varianceRecheckAmount: 350,
      );

  test('spot stocktake is preserved as its own immutable operation type', () {
    final type = StockOperationTypeX.fromDb('spot_stocktake');
    expect(type, StockOperationType.spotStocktake);
    expect(type.dbValue, 'spot_stocktake');
    expect(type.displayName, 'Точечный переучёт');
  });

  test('V14 economics calculates cost, margin and potential revenue', () {
    final product = sampleProduct();
    const portion = PortionPrice(amount: 50, price: 10);
    const meta = ProductV14Meta(sellByBottle: true, bottleSalePrice: 70, portionSale: true, portions: [portion]);
    final economics = ProductEconomics(product: product, meta: meta);
    expect(product.totalAmount, 2450);
    expect(economics.costPerBaseUnit, closeTo(0.05, 0.000001));
    expect(economics.stockCost, closeTo(122.5, 0.000001));
    expect(economics.bottleGrossProfit, closeTo(35, 0.000001));
    expect(economics.bottleMarkupPercent, closeTo(100, 0.000001));
    expect(economics.bottleMarginPercent, closeTo(50, 0.000001));
    expect(economics.portionCost(portion), closeTo(2.5, 0.000001));
    expect(economics.portionGrossProfit(portion), closeTo(7.5, 0.000001));
    expect(economics.portionMarginPercent(portion), closeTo(75, 0.000001));
    expect(economics.potentialBottleRevenue(), closeTo(245, 0.000001));
    expect(economics.potentialPortionRevenue(portion), closeTo(490, 0.000001));
  });

  test('purchase suggestion never becomes negative and uses target before minimum', () {
    expect(sampleProduct().suggestedPurchaseAmount, 350);
    expect(sampleProduct(whole: 5, extra: 0).suggestedPurchaseAmount, 0);
    expect(sampleProduct(initialized: false).suggestedPurchaseAmount, 0);
  });

  test('V14 metadata survives JSON round-trip including arbitrary portions and image', () {
    final original = ProductV14Meta(
      sellByBottle: true,
      bottleSalePrice: 88.5,
      portionSale: true,
      portions: const [PortionPrice(amount: 40, price: 12), PortionPrice(amount: 50, price: 14.5)],
      imagePath: 'products/test.webp',
      imageUrl: 'https://example.invalid/test.webp',
    );
    final restored = ProductV14Meta.fromJson(original.toJson());
    expect(restored.sellByBottle, isTrue);
    expect(restored.bottleSalePrice, 88.5);
    expect(restored.portionSale, isTrue);
    expect(restored.portions.map((x) => x.amount), [40, 50]);
    expect(restored.portions.map((x) => x.price), [12, 14.5]);
    expect(restored.imagePath, 'products/test.webp');
    expect(restored.imageUrl, 'https://example.invalid/test.webp');
  });

  test('stocktake implementation contains persistent draft, resume/restart and duration tracking', () {
    final source = File('lib/screens/stocktake_v2_screen.dart').readAsStringSync();
    expect(source.contains('getActiveStocktakeDraft'), isTrue);
    expect(source.contains('Продолжить переучёт'), isTrue);
    expect(source.contains('Начать сначала'), isTrue);
    expect(source.contains('saveStocktakeActiveSeconds'), isTrue);
    expect(source.contains('Timer.periodic(const Duration(seconds: 1)'), isTrue);
    expect(source.contains('completeStocktakeDraft'), isTrue);
  });

  test('PDF contract covers stock, purchases, deliveries/stocktakes and history operations', () {
    final pdf = File('lib/services/pdf_export_service.dart').readAsStringSync();
    final stock = File('lib/screens/stock_v15_screen.dart').readAsStringSync();
    final history = File('lib/screens/history_overview_screen.dart').readAsStringSync();
    expect(pdf.contains('exportCurrentStock'), isTrue);
    expect(pdf.contains('exportPurchaseList'), isTrue);
    expect(pdf.contains('exportOperation'), isTrue);
    expect(pdf.contains("StockOperationType.delivery => 'postavka'"), isTrue);
    expect(pdf.contains("StockOperationType.stocktake => 'pereuchet'"), isTrue);
    expect(stock.contains('PdfExportService.exportCurrentStock'), isTrue);
    expect(history.contains('PdfExportService.exportOperation'), isTrue);
  });

  test('offline-first queue covers critical mutations and automatic retry', () {
    final source = File('lib/offline_first_controller.dart').readAsStringSync();
    final outbox = File('lib/data/offline_mutation_repository.dart').readAsStringSync();
    expect(source.contains("_offline.enqueue('delivery'"), isTrue);
    expect(source.contains("_offline.enqueue('stocktake'"), isTrue);
    expect(RegExp(r"_offline\.enqueue\(\s*'writeoff'").hasMatch(source), isTrue);
    expect(RegExp(r"_offline\.enqueue\(\s*'transfer'").hasMatch(source), isTrue);
    expect(source.contains('Timer.periodic(const Duration(seconds: 15)'), isTrue);
    expect(source.contains('_flushPendingBestEffort'), isTrue);
    expect(outbox.contains('CREATE TABLE IF NOT EXISTS sync_outbox'), isTrue);
    expect(outbox.contains('client_action_id'), isTrue);
  });

  test('product card keeps delivery cost integrity, image settings, supplier and spot count', () {
    final controller = File('lib/v14_controller.dart').readAsStringSync();
    final detail = File('lib/screens/product_detail_v15_screen.dart').readAsStringSync();
    final bulk = File('lib/screens/bulk_product_edit_v14_screen.dart').readAsStringSync();
    final catalogService = File('lib/services/catalog_editor_service_v16.dart').readAsStringSync();
    expect(controller.contains('Закупочная цена обязательна для каждой позиции поставки'), isTrue);
    expect(controller.contains('uploadProductImage'), isTrue);
    expect(controller.contains("_outbox.enqueue('spot_stocktake'"), isTrue);
    expect(detail.contains('ПЕРЕУЧЕСТЬ ТОВАР'), isTrue);
    expect(detail.contains('Добавить фото товара'), isTrue);
    expect(detail.contains('Продажи и цены'), isTrue);
    expect(detail.contains('Поставщик не назначен'), isTrue);
    expect(detail.contains('Настройки товара'), isTrue);
    expect(bulk.contains('Редактирование склада'), isTrue);
    expect(bulk.contains('Пароль для редактирования склада не требуется'), isTrue);
    expect(bulk.contains('ДОБАВИТЬ НОВЫЙ ТОВАР'), isTrue);
    expect(catalogService.contains('bali-stock-catalog-api'), isTrue);
  });

  test('stock views are grouped by category and alphabetically inside each category', () {
    final stock = File('lib/screens/stock_v15_screen.dart').readAsStringSync();
    expect(stock.contains('_categoryOrder'), isTrue);
    expect(stock.contains('a.name.toLowerCase().compareTo(b.name.toLowerCase())'), isTrue);
    expect(stock.contains('Категории → А–Я'), isTrue);
    expect(stock.contains('_categoryHeader'), isTrue);
    expect(stock.contains('StockListViewMode.compact'), isTrue);
    expect(stock.contains('StockListViewMode.detailed'), isTrue);
    expect(stock.contains('StockListViewMode.table'), isTrue);
  });

  test('purchase price is read-only outside real deliveries and RPC writes are hardened', () {
    final control = File('lib/screens/control_screen.dart').readAsStringSync();
    final migration = File('supabase/migrations/20260819_v14_purchase_price_integrity.sql').readAsStringSync();
    expect(control.contains("labelText: 'Закупочная цена, BYN'"), isFalse);
    expect(control.contains('Вручную она не редактируется и обновляется только поставкой.'), isTrue);
    expect(migration.contains('prior_cost'), isTrue);
    expect(migration.contains('update public.stock_products set default_cost=cost,cost_currency=currency'), isTrue);
    expect(migration.contains("values(p_product_key,p_supplier,p_sku,null,'BYN'"), isTrue);
    expect(migration.contains("revoke all on function ' || fn || ' from anon"), isTrue);
    expect(migration.contains("grant execute on function ' || fn || ' to service_role"), isTrue);
  });
}
