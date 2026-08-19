import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary navigation order remains exact', () {
    final app = File('lib/app.dart').readAsStringSync();
    final labels = RegExp("label: '([^']+)'")
        .allMatches(app)
        .map((match) => match.group(1)!)
        .take(6)
        .toList(growable: false);

    expect(labels, const ['Главная', 'Склад', 'Переучёт', 'Закупки', 'Поставка', 'Настройки']);
    expect(app.contains("label: 'История'"), isFalse);
    expect(app.contains('BaliNavIconKind.home'), isTrue);
    expect(app.contains('BaliNavIconKind.settings'), isTrue);
  });

  test('home exposes camera scan, name/code search and manual product code', () {
    final home = File('lib/screens/home_v14_screen.dart').readAsStringSync();
    expect(home.contains('scanProductCode(context)'), isTrue);
    expect(home.contains('enterProductCode(context)'), isTrue);
    expect(home.contains('Сканировать камерой'), isTrue);
    expect(home.contains("labelText: 'Найти по названию или коду товара'"), isTrue);
    expect(home.contains('Ввести код товара'), isTrue);
    expect(home.contains("p.barcode ?? ''"), isTrue);
  });

  test('history lives under settings instead of the primary navigation', () {
    final settings = File('lib/screens/control_hub_v14_screen.dart').readAsStringSync();
    expect(settings.contains("AppBar(title: const Text('Настройки'))"), isTrue);
    expect(settings.contains("title: 'История всех операций'"), isTrue);
  });

  test('catalog editing is no-pin and supports creating a new product', () {
    final editor = File('lib/screens/bulk_product_edit_v14_screen.dart').readAsStringSync();
    final service = File('lib/services/catalog_editor_service_v16.dart').readAsStringSync();
    expect(editor.contains('showOperationPinValueDialog'), isFalse);
    expect(editor.contains('Пароль для редактирования склада не требуется'), isTrue);
    expect(editor.contains('ДОБАВИТЬ НОВЫЙ ТОВАР'), isTrue);
    expect(editor.contains("'old_product_key': null"), isTrue);
    expect(editor.contains("labelText: 'Категория *'"), isTrue);
    expect(service.contains('bali-stock-catalog-api'), isTrue);
    expect(service.contains("'action': 'catalog_product_batch'"), isTrue);
  });

  test('history can delete drafts but completed operations have no delete control', () {
    final history = File('lib/screens/history_overview_screen.dart').readAsStringSync();
    expect(history.contains('Удалить черновик'), isTrue);
    expect(history.contains('controller.deleteStocktakeDraft'), isTrue);
    expect(history.contains('Проведённые операции не удаляются'), isTrue);
    expect(history.contains('final VoidCallback onDelete'), isTrue);
    expect(history.contains('operation, required this.onPdf, required this.onOpen, required this.onDelete'), isFalse);
  });

  test('iPhone profile uses V16 launcher on top of the stabilized runtime', () {
    final generator = File('tool/generate_mobileconfig.py').readAsStringSync();
    final launcher = File('ios-web/launch-v16.html').readAsStringSync();
    final catalog = File('ios-web/v16-catalog-history.js').readAsStringSync();
    final ui = File('ios-web/v15-ui.js').readAsStringSync();
    final delivery = File('ios-web/v15-delivery-link.js').readAsStringSync();

    expect(generator.contains('launch-v16.html'), isTrue);
    expect(generator.contains('BALI STOCK V16'), isTrue);
    expect(launcher.contains('bali-stock-ios-runtime'), isTrue);
    expect(launcher.contains('v16-catalog-history.js'), isTrue);
    expect(launcher.contains('return,[A-Za-z_\$][A-Za-z0-9_\$]*='), isTrue);
    expect(launcher.contains('async function snapshot'), isTrue);
    expect(catalog.contains('__BALI_STOCK_V16_CATALOG_HISTORY__'), isTrue);
    expect(catalog.contains('Пароль не требуется'), isTrue);
    expect(catalog.contains('ДОБАВИТЬ НОВЫЙ ТОВАР'), isTrue);
    expect(catalog.contains("api('draft_delete'"), isTrue);
    expect(ui.contains('__BALI_STOCK_V15_UI__'), isTrue);
    expect(delivery.contains('purchase_request_id'), isTrue);
  });
}
