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

  test('iPhone profile uses V15 launcher on top of the stabilized runtime', () {
    final generator = File('tool/generate_mobileconfig.py').readAsStringSync();
    final launcher = File('ios-web/launch-v15.html').readAsStringSync();
    final ui = File('ios-web/v15-ui.js').readAsStringSync();
    final delivery = File('ios-web/v15-delivery-link.js').readAsStringSync();

    expect(generator.contains('launch-v15.html'), isTrue);
    expect(generator.contains('BALI STOCK V15'), isTrue);
    expect(launcher.contains('bali-stock-ios-runtime'), isTrue);
    expect(launcher.contains('v15-ui.js'), isTrue);
    expect(launcher.contains('v15-delivery-link.js'), isTrue);
    expect(launcher.contains('return,[A-Za-z_\$][A-Za-z0-9_\$]*='), isTrue);
    expect(launcher.contains('async function snapshot'), isTrue);
    expect(ui.contains('__BALI_STOCK_V15_UI__'), isTrue);
    expect(delivery.contains('purchase_request_id'), isTrue);
  });
}
