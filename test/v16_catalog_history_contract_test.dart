import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog editor does not prompt for PIN and can create a new SKU', () {
    final editor = File('lib/screens/bulk_product_edit_v14_screen.dart').readAsStringSync();
    expect(editor.contains('showOperationPinValueDialog'), isFalse);
    expect(editor.contains('Пароль для редактирования склада не требуется'), isTrue);
    expect(editor.contains('ДОБАВИТЬ НОВЫЙ ТОВАР'), isTrue);
    expect(editor.contains("'old_product_key': null"), isTrue);
    expect(editor.contains("labelText: 'Категория *'"), isTrue);
    expect(editor.contains('Закупочная цена вручную не задаётся'), isTrue);
  });

  test('dedicated catalog API is no-pin, app-key protected and strips purchase price fields', () {
    final source = File('supabase/functions/bali-stock-catalog-api/index.ts').readAsStringSync();
    final client = File('lib/services/catalog_editor_service_v16.dart').readAsStringSync();
    expect(source.contains('requirePin'), isFalse);
    expect(source.contains('INVALID_PIN'), isFalse);
    expect(source.contains('function requireClient(req: Request)'), isTrue);
    expect(source.contains('CLIENT_KEY_REQUIRED'), isTrue);
    expect(source.contains('CLIENT_KEY_INVALID'), isTrue);
    expect(client.contains('..._remote.readHeaders'), isTrue);
    expect(source.contains('delete item.default_cost'), isTrue);
    expect(source.contains('delete item.cost_currency'), isTrue);
    expect(source.contains('stock_catalog_products_batch_v14'), isTrue);
  });

  test('history exposes deletion only for stocktake drafts', () {
    final source = File('lib/screens/history_overview_screen.dart').readAsStringSync();
    expect(source.contains('Удалить черновик'), isTrue);
    expect(source.contains('deleteStocktakeDraft'), isTrue);
    expect(source.contains('Проведённые операции не удаляются'), isTrue);
    expect(source.contains('final VoidCallback onDelete;'), isTrue);
    expect(RegExp(r'class _OperationCard[\s\S]*final VoidCallback onDelete;').hasMatch(source), isFalse);
  });

  test('iPhone V16 has no-pin catalog edit and draft-only delete controls', () {
    final source = File('ios-web/v16-catalog-history.js').readAsStringSync();
    expect(source.contains('__BALI_STOCK_V16_CATALOG_HISTORY__'), isTrue);
    expect(source.contains('Пароль не требуется'), isTrue);
    expect(source.contains('ДОБАВИТЬ НОВЫЙ ТОВАР'), isTrue);
    expect(source.contains('bali-stock-catalog-api'), isTrue);
    expect(source.contains("api('draft_delete'"), isTrue);
    expect(source.contains('Проведённые операции не удаляются'), isTrue);
  });
}
