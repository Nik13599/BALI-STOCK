import 'package:bali_stock/models.dart';
import 'package:bali_stock/services/invoice_recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

Product product({
  required int id,
  required String name,
  required String category,
  required int packageSize,
  StockUnit unit = StockUnit.ml,
}) =>
    Product(
      id: id,
      name: name,
      categoryId: id,
      categoryName: category,
      bottleMl: packageSize,
      wholeBottles: 0,
      extraMl: 0,
      minimumMl: 0,
      stockUnit: unit,
      stockInitialized: true,
      active: true,
    );

void main() {
  final recognizer = InvoiceRecognitionService();
  final products = <Product>[
    product(id: 1, name: 'Jameson', category: 'Виски', packageSize: 1000),
    product(id: 2, name: 'Сябры', category: 'Водка', packageSize: 500),
    product(id: 3, name: 'Мята', category: 'Зелень', packageSize: 100, unit: StockUnit.gram),
    product(id: 4, name: 'Апельсин', category: 'Фрукты', packageSize: 1, unit: StockUnit.piece),
  ];

  test('recognizes bottles from English invoice line', () {
    final result = recognizer.parseText(
      'Jameson 6 бут. 85,00\nИтого 510,00',
      products: products,
    );
    expect(result.lines, hasLength(1));
    expect(result.lines.single.product.name, 'Jameson');
    expect(result.lines.single.packages, 6);
    expect(result.lines.single.quantityBase, 6000);
  });

  test('recognizes Cyrillic product and bottle count', () {
    final result = recognizer.parseText(
      'Сябры водка 12 бутылок 18,50',
      products: products,
    );
    expect(result.lines, hasLength(1));
    expect(result.lines.single.product.name, 'Сябры');
    expect(result.lines.single.packages, 12);
    expect(result.lines.single.quantityBase, 6000);
  });

  test('recognizes weight package count', () {
    final result = recognizer.parseText(
      'Мята 4 уп.\n100 г в упаковке',
      products: products,
    );
    expect(result.lines, hasLength(1));
    expect(result.lines.single.product.name, 'Мята');
    expect(result.lines.single.quantityBase, 400);
  });

  test('recognizes piece count', () {
    final result = recognizer.parseText(
      'Апельсин количество 24 шт.',
      products: products,
    );
    expect(result.lines, hasLength(1));
    expect(result.lines.single.product.name, 'Апельсин');
    expect(result.lines.single.quantityBase, 24);
  });

  test('does not invent quantity when invoice row has only product name', () {
    final result = recognizer.parseText('Jameson', products: products);
    expect(result.lines, isEmpty);
  });
}
