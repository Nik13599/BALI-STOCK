import 'package:bali_stock/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock formatter keeps package size and residue', () {
    expect(formatStockParts(2750, 500), '5 бут. × 0,5 л + 250 мл');
    expect(formatStockParts(3050, 700), '4 бут. × 0,7 л + 250 мл');
  });

  test('piece stock does not render package residue', () {
    expect(formatStockParts(12, 1, StockUnit.piece), '12 шт.');
  });
}
