import 'package:bali_stock/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock formatter keeps whole bottles and residue', () {
    expect(formatStockParts(2750, 500), '5 бут. + 250 мл');
    expect(formatStockParts(3050, 700), '4 бут. + 250 мл');
  });
}
