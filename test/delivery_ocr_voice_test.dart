import 'dart:io';

import 'package:bali_stock/models.dart';
import 'package:bali_stock/services/invoice_recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final product = Product(
    id: 1,
    name: 'Jim Beam',
    categoryId: 1,
    categoryName: 'Виски',
    bottleMl: 700,
    wholeBottles: 2,
    extraMl: 0,
    minimumMl: 700,
    stockUnit: StockUnit.ml,
    stockInitialized: true,
    active: true,
    barcode: '4600000000001',
  );

  test('invoice OCR parses product, quantity, price, supplier and document number', () {
    final service = InvoiceRecognitionService();
    const supplier = StockSupplier(id: 'supplier-1', name: 'ООО Алкотрейд');

    final result = service.parseText(
      '''
Товарно-транспортная накладная № TTN-7788
Поставщик ООО Алкотрейд
Наименование Количество Цена
Jim Beam 4 бут 35,50
Итого 142,00
''',
      products: [product],
      suppliers: const [supplier],
    );

    expect(result.documentNumber, 'TTN-7788');
    expect(result.supplierId, 'supplier-1');
    expect(result.supplierName, 'ООО Алкотрейд');
    expect(result.lines, hasLength(1));
    expect(result.lines.single.product.name, 'Jim Beam');
    expect(result.lines.single.packages, 4);
    expect(result.lines.single.quantityBase, 2800);
    expect(result.lines.single.unitCost, 35.50);
    expect(result.lines.single.confidence, greaterThan(.8));
  });

  test('native delivery exposes camera, gallery, file OCR and speech controls', () {
    final source = File('lib/screens/delivery_screen.dart').readAsStringSync();
    expect(source.contains('ImageSource.camera'), isTrue);
    expect(source.contains('ImageSource.gallery'), isTrue);
    expect(source.contains('openFile(acceptedTypeGroups:'), isTrue);
    expect(source.contains('VoiceInputButton'), isTrue);
    expect(source.contains('Найти товар голосом'), isTrue);
    expect(source.contains('Продиктовать ФИО'), isTrue);
    expect(source.contains('Продиктовать номер накладной'), isTrue);
    expect(source.contains('Продиктовать комментарий'), isTrue);
    expect(source.contains('result.documentNumber'), isTrue);
    expect(source.contains('result.supplierId'), isTrue);
    expect(source.contains('Сфотографировать накладную'), isTrue);
    expect(source.contains('Выбрать фото'), isTrue);
    expect(source.contains('Подгрузить скан / файл'), isTrue);
  });

  test('speech service is reusable and prefers Russian recognition locale', () {
    final source = File('lib/services/voice_input_service.dart').readAsStringSync();
    expect(source.contains('SpeechToText'), isTrue);
    expect(source.contains("id == 'ru_ru'"), isTrue);
    expect(source.contains("id == 'ru-ru'"), isTrue);
    expect(source.contains('Future<String?> dictate'), isTrue);
  });

  test('release builds request microphone and speech permissions', () {
    final workflow = File('.github/workflows/build.yml').readAsStringSync();
    expect(workflow.contains('android.permission.RECORD_AUDIO'), isTrue);
    expect(workflow.contains('android.speech.RecognitionService'), isTrue);
    expect(workflow.contains('NSMicrophoneUsageDescription'), isTrue);
    expect(workflow.contains('NSSpeechRecognitionUsageDescription'), isTrue);
  });

  test('iPhone runtime has automatic OCR selection and Web Speech fallback', () {
    final runtime = File('supabase/functions/bali-stock-ios-runtime/index.ts').readAsStringSync();
    expect(runtime.contains('__BALI_V14_VOICE_INPUT__'), isTrue);
    expect(runtime.contains('window.SpeechRecognition||window.webkitSpeechRecognition'), isTrue);
    expect(runtime.contains("recognition.lang='ru-RU'"), isTrue);
    expect(runtime.contains('__BALI_V14_INVOICE_AUTO__'), isTrue);
    expect(runtime.contains('Сфотографировать накладную'), isTrue);
    expect(runtime.contains('Выбрать фото / скан'), isTrue);
    expect(runtime.contains('setTimeout(function(){runOcr()},40)'), isTrue);
    expect(runtime.contains('applyInvoiceMetadata'), isTrue);
  });
}
