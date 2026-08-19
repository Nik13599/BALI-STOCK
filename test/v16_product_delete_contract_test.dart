import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warehouse editor exposes explicit product deletion with confirmation', () {
    final screen = File('lib/screens/bulk_product_edit_v14_screen.dart').readAsStringSync();
    expect(screen.contains("label: const Text('Удалить')"), isTrue);
    expect(screen.contains("title: const Text('Удалить товар?')"), isTrue);
    expect(screen.contains('_catalog.deleteProduct('), isTrue);
    expect(screen.contains('product.stockInitialized && product.totalAmount != 0'), isTrue);
    expect(screen.contains('Проведённая история операций сохранится'), isTrue);
    expect(screen.contains('Кто удаляет товар?'), isTrue);
  });

  test('catalog delete service is password-free and uses dedicated action', () {
    final service = File('lib/services/catalog_editor_service_v16.dart').readAsStringSync();
    expect(service.contains("'action': 'product_delete'"), isTrue);
    expect(service.contains("'product_key': key"), isTrue);
    expect(service.contains('x-bali-stock-pin'), isFalse);
  });

  test('server deletion preserves immutable history and guards stock integrity', () {
    final migration = File('supabase/migrations/20260819_v16_1_product_delete.sql').readAsStringSync();
    expect(migration.contains('stock_catalog_product_delete_v17'), isTrue);
    expect(migration.contains('v_balance'), isTrue);
    expect(migration.contains('v_balance, 0) <> 0'), isTrue);
    expect(migration.contains('stock_draft_mirrors'), isTrue);
    expect(migration.contains("r.status in ('draft', 'confirmed', 'sent', 'partial')"), isTrue);
    expect(migration.contains("'catalog_product_delete'"), isTrue);
    expect(migration.contains('set active = false'), isTrue);
    expect(migration.contains('delete from public.stock_operation_lines'), isFalse);
    expect(migration.contains('delete from public.stock_operations'), isFalse);
    expect(migration.contains('revoke all on function public.stock_catalog_product_delete_v17'), isTrue);
    expect(migration.contains('grant execute on function public.stock_catalog_product_delete_v17'), isTrue);
  });

  test('catalog edge function exposes product delete through service role RPC only', () {
    final api = File('supabase/functions/bali-stock-catalog-api/index.ts').readAsStringSync();
    expect(api.contains('action === "product_delete"'), isTrue);
    expect(api.contains('stock_catalog_product_delete_v17'), isTrue);
    expect(api.contains('p_product_key: productKey'), isTrue);
  });

  test('iPhone warehouse editor can delete products while retaining operation history', () {
    final ios = File('ios-web/v16-catalog-history.js').readAsStringSync();
    expect(ios.contains("action:'product_delete'"), isTrue);
    expect(ios.contains('v16DeleteProduct'), isTrue);
    expect(ios.contains('Удалить товар?'), isTrue);
    expect(ios.contains('qty(product) !== 0'), isTrue);
    expect(ios.contains('Проведённая история операций сохранится'), isTrue);
  });
}
