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

  test('home supports platform-correct scan, manual product code and name/code search', () {
    final source = File('lib/screens/home_v14_screen.dart').readAsStringSync();
    final actions = File('lib/widgets/product_code_actions.dart').readAsStringSync();
    expect(source.contains('scanProductCode(context)'), isTrue);
    expect(source.contains('enterProductCode(context)'), isTrue);
    expect(source.contains('productCodeScanActionLabel'), isTrue);
    expect(actions.contains("Platform.isAndroid || Platform.isIOS ? 'Сканировать камерой' : 'Сканировать сканером'"), isTrue);
    expect(actions.contains('USB/Bluetooth-сканером'), isTrue);
    expect(source.contains('Ввести код товара'), isTrue);
    expect(source.contains('Найти по названию или коду товара'), isTrue);
    expect(source.contains("p.barcode ?? ''"), isTrue);
    expect(actions.contains('Назначить код товару'), isTrue);
    expect(actions.contains('Найти товар вручную'), isTrue);
    expect(actions.contains('controller.updateProductControl'), isTrue);
    expect(source.contains('resolveProductCode('), isTrue);
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
    expect(source.contains('resolveProductCode('), isTrue);
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
    expect(screen.contains('resolveProductCode('), isTrue);
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

  test('iPhone production runtime smoke verifies scanner workflows after Supabase assembly', () {
    final runtimeHost = File('supabase/functions/bali-stock-ios-runtime/index.ts').readAsStringSync();
    final smoke = File('.github/workflows/iphone-runtime-smoke.yml').readAsStringSync();
    final scannerCompat = File('ios-web/ios-scanner-compat.js').readAsStringSync();
    final builder = File('tool/build_ios_production_runtime.py').readAsStringSync();
    final offline = File('ios-web/v12-offline.js').readAsStringSync();
    final productionFlows = File('ios-web/v14-scan-workflows.js').readAsStringSync();

    expect(runtimeHost.contains('LEGACY_LAUNCHER'), isTrue);
    expect(runtimeHost.contains('__BALI_STOCK_VISUAL_CONTRACT__'), isTrue);
    expect(runtimeHost.contains('interface_guard: true'), isTrue);
    expect(runtimeHost.contains('password_prompt: false'), isTrue);
    expect(scannerCompat.contains('__BALI_STOCK_IOS_SCANNER_COMPAT__'), isTrue);
    expect(scannerCompat.contains('__BALI_STOCK_IOS_LIVE_SCANNER__'), isTrue);
    expect(scannerCompat.contains("input.setAttribute('capture', 'environment')"), isFalse);
    expect(scannerCompat.contains('scanner.scanFile(file, true)'), isFalse);
    expect(scannerCompat.contains('config.fps = Math.max(15'), isTrue);
    expect(scannerCompat.contains('formats.EAN_13'), isTrue);
    expect(scannerCompat.contains("focusMode: 'continuous'"), isTrue);
    expect(scannerCompat.contains('data-bali-scanner-for'), isFalse);
    expect(scannerCompat.contains('navigator.mediaDevices.getUserMedia'), isTrue);
    expect(builder.contains('SCANNER_LIBRARY_SHA256'), isTrue);
    expect(builder.contains('inline_scanner_library(html)'), isTrue);
    expect(builder.contains('visual_shell(html) != original_visual_shell'), isTrue);
    expect(smoke.contains('__BALI_V14_SCAN_WORKFLOWS__'), isTrue);
    expect(smoke.contains('__BALI_STOCK_IOS_SCANNER_COMPAT__'), isTrue);
    expect(smoke.contains('__BALI_STOCK_IOS_LIVE_SCANNER__'), isTrue);
    expect(smoke.contains('СОХРАНИТЬ → СЛЕДУЮЩИЙ СКАН'), isTrue);
    expect(smoke.contains('Закупочная цена обязательна для каждой позиции поставки.'), isTrue);
    expect(smoke.contains('Parse every production runtime inline JavaScript block'), isTrue);
    expect(offline.contains('Назначить код товару'), isTrue);
    expect(offline.contains('Найти товар вручную'), isTrue);
    expect(offline.contains('__v12ChooseUnknownCodeAction'), isTrue);
    expect(productionFlows.contains("__BALI_V14_SCAN_WORKFLOWS__='v14.5'"), isTrue);
    expect(productionFlows.contains('Назначить код товару'), isTrue);
    expect(productionFlows.contains('Найти товар вручную'), isTrue);
    expect(productionFlows.contains('window.__baliResolveProductCode'), isTrue);
    expect(productionFlows.contains("await api('product_meta'"), isTrue);
    expect(productionFlows.contains('default_cost:'), isFalse);
    final iphoneOperations = File('ios-web/v13/part-02.js').readAsStringSync();
    expect(iphoneOperations.contains('__v12ResolveProductCode(code)'), isTrue);
    expect(iphoneOperations.contains('Товар с таким кодом не найден'), isFalse);
  });
}
