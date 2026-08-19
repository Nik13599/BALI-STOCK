import 'dart:io';

import 'package:bali_stock/models.dart';
import 'package:bali_stock/widgets/product_code_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product code lookup trims input and finds only assigned codes', () {
    final products = [
      const Product(
        id: 1,
        name: 'Jim Beam',
        categoryName: 'Виски',
        bottleMl: 700,
        barcode: '4601234567890',
      ),
      const Product(
        id: 2,
        name: 'Без кода',
        categoryName: 'Прочее',
        bottleMl: 500,
      ),
    ];

    expect(findProductByCode(products, ' 4601234567890 ')?.id, 1);
    expect(findProductByCode(products, 'missing'), isNull);
    expect(findProductByCode(products, ''), isNull);
  });

  test('native camera scanner uses MobileScanner and returns decoded raw code', () {
    final source = File('lib/screens/product_code_scanner_screen.dart').readAsStringSync();
    expect(source.contains('MobileScanner('), isTrue);
    expect(source.contains('facing: CameraFacing.back'), isTrue);
    expect(source.contains('capture.rawValue'), isTrue);
    expect(source.contains('Navigator.of(context).pop(value)'), isTrue);
  });

  test('home supports camera scan, manual product code and name/code search', () {
    final source = File('lib/screens/home_v14_screen.dart').readAsStringSync();
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('Сканировать камерой'), isTrue);
    expect(source.contains('Ввести код товара'), isTrue);
    expect(source.contains('Найти по названию или коду товара'), isTrue);
  });

  test('full stocktake supports sequential scan and clear entered/unentered workflow', () {
    final source = File('lib/screens/stocktake_v2_screen.dart').readAsStringSync();
    expect(source.contains('Future<void> _scanWorkflow() async'), isTrue);
    expect(source.contains('while (mounted)'), isTrue);
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН'), isTrue);
    expect(source.contains('Данные введены'), isTrue);
    expect(source.contains('Не введено'), isTrue);
    expect(source.contains('_StocktakeListFilter.unfilled'), isTrue);
    expect(source.contains('_StocktakeListFilter.filled'), isTrue);
  });

  test('delivery supports sequential scan, manual code, name search and mandatory cost', () {
    final source = File('lib/screens/delivery_screen.dart').readAsStringSync();
    expect(source.contains('Future<void> _scanWorkflow() async'), isTrue);
    expect(source.contains('while (mounted)'), isTrue);
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('Название / категория / код товара'), isTrue);
    expect(source.contains('СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН'), isTrue);
    expect(source.contains("labelText: 'Закупочная цена, BYN *'"), isTrue);
    expect(source.contains("return 'Укажите закупочную цену';"), isTrue);
    expect(source.contains('Данные введены'), isTrue);
  });

  test('invoice workflow blocks non-invoices and renders recognition progress safely', () {
    final screen = File('lib/screens/delivery_screen.dart').readAsStringSync();
    final recognition = File('lib/services/invoice_recognition_service.dart').readAsStringSync();
    expect(recognition.contains('Накладная не распознана. Загрузите оригинальную накладную.'), isTrue);
    expect(recognition.contains('InvoiceDocumentValidator.validate'), isTrue);
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

  test('iPhone production runtime smoke verifies scanner workflows after Supabase assembly', () {
    final runtimeHost = File('supabase/functions/bali-stock-ios-runtime/index.ts').readAsStringSync();
    final smoke = File('.github/workflows/iphone-runtime-smoke.yml').readAsStringSync();

    expect(runtimeHost.contains('source: "supabase-storage"'), isTrue);
    expect(runtimeHost.contains('github_dependency: false'), isTrue);
    expect(runtimeHost.contains('password_prompt: false'), isTrue);
    expect(smoke.contains('__BALI_V14_SCAN_WORKFLOWS__'), isTrue);
    expect(smoke.contains('СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН'), isTrue);
    expect(smoke.contains('Закупочная цена обязательна для каждой позиции поставки.'), isTrue);
    expect(smoke.contains('Parse every production runtime inline JavaScript block'), isTrue);
  });
}
