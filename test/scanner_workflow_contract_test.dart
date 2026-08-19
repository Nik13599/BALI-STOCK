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
    expect(source.contains("Navigator.of(context).pop(value)"), isTrue);
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

  test('delivery supports sequential camera scan, manual code, search and mandatory cost', () {
    final source = File('lib/screens/delivery_screen.dart').readAsStringSync();
    expect(source.contains('Future<void> _scanProductWorkflow()'), isTrue);
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('scanWorkflow: true'), isTrue);
    expect(source.contains('Сохранить → следующий скан'), isTrue);
    expect(source.contains('Найти товар по названию или коду'), isTrue);
    expect(source.contains("p.barcode ?? ''"), isTrue);
    expect(source.contains('Закупочная цена обязательна'), isTrue);
    expect(source.contains('unitCost == null'), isTrue);
    expect(source.contains('ДАННЫЕ ВВЕДЕНЫ'), isTrue);
    expect(source.contains('final productLocked = initial != null || preselectedProduct != null;'), isTrue);
    expect(source.contains('Позиция зафиксирована выбранным/отсканированным кодом.'), isTrue);
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
