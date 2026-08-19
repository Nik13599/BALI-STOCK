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

  test('iPhone launcher still provides the compact product card runtime layer', () {
    final launcher = File('ios-web/launch-v14-3.html').readAsStringSync();
    expect(launcher.contains('__BALI_V14_COMPACT_PRODUCT_CARD__'), isTrue);
    expect(launcher.contains('window.v14ShowProduct=compact'), isTrue);
    expect(launcher.contains('@media(max-width:520px)'), isTrue);
    expect(launcher.contains('ПЕРЕУЧЕСТЬ ТОВАР'), isTrue);
  });
}
