import 'dart:io';

import 'package:bali_stock/models.dart';
import 'package:bali_stock/widgets/product_code_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product product({String? barcode}) => Product(
        id: 1,
        name: 'Jim Beam',
        categoryId: 1,
        categoryName: 'Виски',
        bottleMl: 700,
        wholeBottles: 1,
        extraMl: 0,
        minimumMl: 0,
        stockUnit: StockUnit.ml,
        stockInitialized: true,
        active: true,
        barcode: barcode,
      );

  test('product code lookup trims input and finds only assigned codes', () {
    final item = product(barcode: ' 4601234567890 ');
    expect(findProductByCode([item], '4601234567890'), same(item));
    expect(findProductByCode([item], ' 4601234567890 '), same(item));
    expect(findProductByCode([item], 'unknown'), isNull);
    expect(findProductByCode([product()], ''), isNull);
  });

  test('native camera scanner uses MobileScanner and returns decoded raw code', () {
    final source = File('lib/screens/product_code_scanner_screen.dart').readAsStringSync();
    expect(source.contains('MobileScanner('), isTrue);
    expect(source.contains('onDetect:'), isTrue);
    expect(source.contains('rawValue'), isTrue);
    expect(source.contains('Navigator.of(context).pop(value)'), isTrue);
  });

  test('home supports camera scan, manual product code and name/code search', () {
    final source = File('lib/screens/home_v14_screen.dart').readAsStringSync();
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('Сканировать камерой'), isTrue);
    expect(source.contains('Ввести код товара'), isTrue);
    expect(source.contains('Найти по названию или коду товара'), isTrue);
    expect(source.contains("p.barcode ?? ''"), isTrue);
  });

  test('full stocktake supports sequential scan and clear entered/unentered workflow', () {
    final source = File('lib/screens/stocktake_v2_screen.dart').readAsStringSync();
    expect(source.contains('Future<void> _scanWorkflow()'), isTrue);
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('_QuickCountResult.savedAndScanNext'), isTrue);
    expect(source.contains('Сохранить → следующий скан'), isTrue);
    expect(source.contains('ДАННЫЕ ВВЕДЕНЫ'), isTrue);
    expect(source.contains('НЕ ВВЕДЕНО'), isTrue);
    expect(source.contains('_StocktakeListFilter.unfilled'), isTrue);
    expect(source.contains('_StocktakeListFilter.filled'), isTrue);
    expect(source.contains('Название / категория / код товара'), isTrue);
    expect(source.contains("final barcode = _productFor(line)?.barcode ?? ''"), isTrue);
  });

  test('delivery supports sequential scan, manual code, name search and mandatory cost', () {
    final screen = File('lib/screens/delivery_screen_v15.dart').readAsStringSync();
    final editor = File('lib/screens/delivery_screen.dart').readAsStringSync();
    expect(screen.contains('Future<void> _scanProductWorkflow()'), isTrue);
    expect(screen.contains('scanProductCode(context)'), isTrue);
    expect(screen.contains('enterProductCode(context)'), isTrue);
    expect(screen.contains('scanWorkflow: true'), isTrue);
    expect(screen.contains('Найти по названию или коду'), isTrue);
    expect(screen.contains("p.barcode ?? ''"), isTrue);
    expect(screen.contains('unitCost == null'), isTrue);
    expect(screen.contains('ФИО принимающего *'), isTrue);
    expect(screen.contains('Выберите поставщика'), isTrue);
    expect(screen.contains("labelText: 'Склад *'"), isTrue);
    expect(editor.contains('Сохранить → следующий скан'), isTrue);
    expect(editor.contains('Закупочная цена обязательна'), isTrue);
    expect(editor.contains('final productLocked = initial != null || preselectedProduct != null;'), isTrue);
  });

  test('invoice workflow blocks non-invoices and renders recognition progress safely', () {
    final service = File('lib/services/invoice_recognition_service_v15.dart').readAsStringSync();
    final screen = File('lib/screens/delivery_screen_v15.dart').readAsStringSync();
    expect(service.contains('Накладная не распознана. Загрузите оригинальную накладную.'), isTrue);
    expect(service.contains('_validateInvoice'), isTrue);
    expect(service.contains('structurallyInvoice'), isTrue);
    expect(screen.contains('Распознаю накладную…'), isTrue);
    expect(screen.contains('maxWidth: 1800'), isTrue);
    expect(screen.contains('_visibleLineLimit'), isTrue);
    expect(screen.contains('Показать ещё'), isTrue);
  });

  test('navigation icons are semantic warehouse pictograms', () {
    final source = File('lib/widgets/bali_nav_icon.dart').readAsStringSync();
    expect(source.contains('void _warehouse('), isTrue);
    expect(source.contains('void _deliveryTruck('), isTrue);
    expect(source.contains('void _stocktake('), isTrue);
    expect(source.contains('void _settingsHex('), isTrue);
    expect(source.contains('BaliNavIconKind.home'), isTrue);
    expect(source.contains('BaliNavIconKind.delivery'), isTrue);
    expect(source.contains('BaliNavIconKind.settings'), isTrue);
  });

  test('iPhone runtime contains production scanner workflows for count and delivery', () {
    final source = File('supabase/functions/bali-stock-ios-runtime/index.ts').readAsStringSync();
    expect(source.contains('__BALI_V14_SCAN_WORKFLOWS__'), isTrue);
    expect(source.contains('async function scanCodeFor(onCode)'), isTrue);
    expect(source.contains("facingMode:'environment'"), isTrue);
    expect(source.contains('function countScanFlow()'), isTrue);
    expect(source.contains('function deliveryScanFlow()'), isTrue);
    expect(source.contains('ДАННЫЕ ВВЕДЕНЫ'), isTrue);
    expect(source.contains('НЕ ВВЕДЕНО'), isTrue);
    expect(source.contains('Закупочная цена обязательна для каждой позиции поставки.'), isTrue);
  });
}
