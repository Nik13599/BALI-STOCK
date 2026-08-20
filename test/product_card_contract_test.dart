import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product card stays compact and moves admin actions behind the settings gear', () {
    final card = File('lib/screens/product_detail_v15_screen.dart').readAsStringSync();

    expect(card.contains('BoxConstraints(maxWidth: 880)'), isTrue);
    expect(card.contains('constraints.maxWidth < 520'), isTrue);
    expect(card.contains("Text('ПЕРЕУЧЕСТЬ ТОВАР'"), isTrue);
    expect(card.contains("title: 'Склад'"), isTrue);
    expect(card.contains("title: 'Закупка'"), isTrue);
    expect(card.contains("Text('Продажа'"), isTrue);
    expect(card.contains("title: const Text('Экономика'"), isTrue);
    expect(card.contains("title: const Text('История карточки'"), isTrue);
    expect(card.contains("_Status('НОРМА'"), isTrue);
    expect(card.contains("_Status('МАЛО'"), isTrue);
    expect(card.contains("_Status('КРИТИЧНО'"), isTrue);
    expect(card.contains("_Status('НЕТ В НАЛИЧИИ'"), isTrue);
    expect(card.contains("_RowData('Последний переучёт'"), isTrue);
    expect(card.contains("_RowData('Последнее движение'"), isTrue);
    expect(card.contains("_RowData('Поставщик'"), isTrue);
    expect(card.contains('Поставщик не назначен'), isTrue);
    expect(card.contains("tooltip: 'Настройки товара'"), isTrue);
    expect(card.contains("title: 'Поставщик'"), isTrue);
    expect(card.contains("title: 'Продажи и цены'"), isTrue);
    expect(card.contains('Добавить фото товара'), isTrue);
    expect(card.contains('Заменить фото товара'), isTrue);
    expect(card.contains('Ввести нового поставщика вручную'), isTrue);
  });

  test('iPhone production bundle embeds the same compact card and settings gear', () {
    final builder = File('tool/build_ios_production_runtime.py').readAsStringSync();
    final ui = File('ios-web/v15-ui.js').readAsStringSync();

    expect(builder.contains('"bali-v15-ui": ROOT / "ios-web" / "v15-ui.js"'), isTrue);
    expect(builder.contains('"__BALI_STOCK_V15_UI__"'), isTrue);
    expect(ui.contains('__BALI_STOCK_V15_UI__'), isTrue);
    expect(ui.contains('v15Gear'), isTrue);
    expect(ui.contains('Настройки товара'), isTrue);
    expect(ui.contains('Поставщик не назначен'), isTrue);
    expect(ui.contains('Продажи и цены'), isTrue);
    expect(ui.contains('Ввести нового поставщика'), isTrue);
    expect(ui.contains('ПЕРЕУЧЕСТЬ ТОВАР'), isTrue);
  });
}
