import 'package:bali_stock/models.dart';
import 'package:bali_stock/purchase_models.dart';
import 'package:bali_stock/services/invoice_recognition_service_v15.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product product(String name) => Product(
        id: name.hashCode,
        name: name,
        categoryId: 1,
        categoryName: 'Тест',
        bottleMl: 700,
        wholeBottles: 2,
        extraMl: 0,
        minimumMl: 700,
        stockUnit: StockUnit.ml,
        stockInitialized: true,
        active: true,
      );

  test('random photograph text is rejected as a non-invoice', () {
    final service = InvoiceRecognitionServiceV15();
    final products = [product('Jim Beam'), product('Martini Bianco')];
    const randomPhotoText = '''
      BALI NIGHT CLUB
      Friday Party 23:00
      DJ MUSIC DANCE
      Minsk Kirova 13
      Jim Beam cocktail special
    ''';

    expect(service.looksLikeInvoiceText(randomPhotoText, products: products), isFalse);
  });

  test('realistic TTN structure passes document validation', () {
    final service = InvoiceRecognitionServiceV15();
    final products = [product('Jim Beam'), product('Martini Bianco')];
    const invoiceText = '''
      ТОВАРНО-ТРАНСПОРТНАЯ НАКЛАДНАЯ ТТН № 004512 от 19.08.2026
      Поставщик: ООО Поставщик
      Получатель: ООО Магиштык
      УНП 193000000
      Наименование товара   Ед. изм.   Количество   Цена   Сумма
      Jim Beam 0.7          бут.       6            42,50  255,00
      Martini Bianco        бут.       4            31,20  124,80
      Итого 379,80 BYN
      НДС 20%
    ''';

    expect(service.looksLikeInvoiceText(invoiceText, products: products), isTrue);
    expect(service.invoiceTextConfidence(invoiceText, products: products), greaterThanOrEqualTo(.55));
  });

  test('purchase request line tracks outstanding quantity after partial delivery', () {
    const line = StockPurchaseRequestLine(
      productKey: 'jim beam|ml|700',
      suggestedQuantity: 2800,
      requestedQuantity: 4200,
      receivedQuantity: 3500,
      unitCost: 42.5,
    );
    expect(line.outstandingQuantity, 700);
  });

  test('purchase request exposes V15 workflow labels and receive eligibility', () {
    final request = StockPurchaseRequest(
      id: '12345678-0000-0000-0000-000000000000',
      supplierId: 'supplier',
      status: 'partial',
      createdAt: DateTime(2026, 8, 19),
      updatedAt: DateTime(2026, 8, 19),
      lines: const [],
    );
    expect(request.statusLabel, 'Частично поставлена');
    expect(request.isOpen, isTrue);
    expect(request.canReceive, isTrue);
    expect(request.shortNumber, startsWith('ЗАК-2026-0819-'));
  });
}
