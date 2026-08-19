import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product card keeps the primary information compact and responsive', () {
    final card = File('lib/screens/product_detail_compact_v14_screen.dart').readAsStringSync();

    expect(card.contains('BoxConstraints(maxWidth: 880)'), isTrue);
    expect(card.contains('constraints.maxWidth < 520'), isTrue);
    expect(card.contains('constraints.maxWidth < 680'), isTrue);
    expect(card.contains("Text('ПЕРЕУЧЕСТЬ ТОВАР'"), isTrue);
    expect(card.contains("title: 'Склад'"), isTrue);
    expect(card.contains("title: 'Закупка'"), isTrue);
    expect(card.contains("Text('Продажа'"), isTrue);
    expect(card.contains("title: const Text('Экономика'"), isTrue);
    expect(card.contains("title: const Text('История карточки'"), isTrue);
    expect(card.contains("_StockStatus('НОРМА'"), isTrue);
    expect(card.contains("_StockStatus('МАЛО'"), isTrue);
    expect(card.contains("_StockStatus('КРИТИЧНО'"), isTrue);
    expect(card.contains("_StockStatus('НЕТ В НАЛИЧИИ'"), isTrue);
    expect(card.contains("_RowData('Последний переучёт'"), isTrue);
    expect(card.contains("_RowData('Последнее движение'"), isTrue);
  });

  test('iPhone launcher overrides the legacy long product card with the compact card', () {
    final launcher = File('ios-web/launch-v14-3.html').readAsStringSync();

    expect(launcher.contains('__BALI_V14_COMPACT_PRODUCT_CARD__'), isTrue);
    expect(launcher.contains('window.v14ShowProduct=compact'), isTrue);
    expect(launcher.contains('@media(max-width:520px)'), isTrue);
    expect(launcher.contains('ПЕРЕУЧЕСТЬ ТОВАР'), isTrue);
    expect(launcher.contains('<summary>Экономика</summary>'), isTrue);
    expect(launcher.contains('<summary>История карточки</summary>'), isTrue);
  });
}
