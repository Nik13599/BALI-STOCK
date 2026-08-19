import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter purchase catalog keeps all active products before initial stocktake', () {
    final source = File('lib/screens/purchase_screen_v15.dart').readAsStringSync();
    expect(source.contains('if (!product.active) return false;'), isTrue);
    expect(source.contains('if (_tab == _PurchaseTab.needed && !product.stockInitialized) return false;'), isTrue);
    expect(source.contains('Рекомендация — после первичного переучёта'), isTrue);
    expect(source.contains('Полный ассортимент уже доступен во вкладке «Все товары»'), isTrue);
    expect(source.contains("product.stockInitialized ? formatStockParts(product.totalAmount, product.packageSize, product.stockUnit) : 'остаток не введён'"), isTrue);
  });

  test('iPhone purchase catalog keeps all active products before initial stocktake', () {
    final source = File('ios-web/v15-ui.js').readAsStringSync();
    expect(source.contains("if(state.purchaseTab!=='all'&&!init(p))return false"), isTrue);
    expect(source.contains('Рекомендация — после первичного переучёта'), isTrue);
    expect(source.contains('Полный ассортимент уже доступен во вкладке «Все товары»'), isTrue);
    expect(source.contains("function requestOpen(r){return ['confirmed','sent','partial'].indexOf(r.status)>=0;}"), isTrue);
  });
}
