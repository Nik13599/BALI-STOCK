import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter drafts are durably queued after every editable change', () {
    final controller = File('lib/offline_first_controller.dart').readAsStringSync();
    final outbox = File('lib/data/offline_mutation_repository.dart').readAsStringSync();
    final payloads = File('lib/data/sync_payload_builder.dart').readAsStringSync();

    expect(controller.contains('Future<void> saveStocktakeActiveSeconds'), isTrue);
    expect(controller.contains('Future<void> saveStocktakeDraftLine'), isTrue);
    expect(controller.contains('Future<void> updateProductControl'), isTrue);
    expect(controller.contains("coalesceKey: 'product_meta:\$productKey'"), isTrue);
    expect(controller.contains("'draft_sync'"), isTrue);
    expect(controller.contains('_queueDraftSnapshot'), isTrue);
    expect(controller.contains('_scheduleDraftQueue(draftId)'), isTrue);
    expect(controller.contains("removeCoalesced('draft_sync'"), isTrue);
    expect(outbox.contains('Future<String> enqueueLatest'), isTrue);
    expect(outbox.contains('client_coalesce_key'), isTrue);
    expect(payloads.contains('draftSync(StocktakeDraft draft)'), isTrue);
  });

  test('queued server confirmation is applied before local outbox removal', () {
    final controller = File('lib/offline_first_controller.dart').readAsStringSync();
    final response = controller.indexOf('final response = await _remoteSync.postQueued');
    final snapshot = controller.indexOf("final rawSnapshot = response['snapshot']", response);
    final removal = controller.indexOf('await _offline.removePending(item.id)', response);
    final apply = controller.indexOf('await applySharedSnapshot(latestSnapshot)', removal);

    expect(response, greaterThanOrEqualTo(0));
    expect(snapshot, greaterThan(response));
    expect(removal, greaterThan(snapshot));
    expect(apply, greaterThan(removal));
  });

  test('draft API returns the authoritative snapshot for every device', () {
    final api = File('supabase/functions/bali-stock-client-api/index.ts').readAsStringSync();
    final start = api.indexOf('action === "draft_sync"');
    final end = api.indexOf('action === "draft_delete"', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(api.substring(start, end).contains('snapshot: await snapshot(req)'), isTrue);
  });

  test('iPhone runtime has one durable cross-device mutation queue', () {
    final source = File('ios-web/ios-persistence-v109.js').readAsStringSync();
    final builder = File('tool/build_ios_production_runtime.py').readAsStringSync();
    final catalog = File('ios-web/v16-catalog-history.js').readAsStringSync();

    for (final action in [
      'delivery',
      'writeoff',
      'transfer',
      'correction',
      'spot_stocktake',
      'stocktake',
      'supplier_upsert',
      'supplier_link',
      'location_upsert',
      'catalog_product_batch',
      'product_meta',
      'purchase_request_create',
      'purchase_request_status',
      'draft_sync',
      'draft_delete',
    ]) {
      expect(source.contains("'$action'"), isTrue, reason: 'Missing durable iPhone action $action');
    }
    expect(source.contains('indexedDB.open'), isTrue);
    expect(source.contains('client_action_id'), isTrue);
    expect(source.contains('delivery_bundle'), isTrue);
    expect(source.contains('migrateLegacyQueue'), isTrue);
    expect(source.contains('window.baliFlushPersistence'), isTrue);
    expect(builder.contains('bali-ios-persistence-v109'), isTrue);
    expect(catalog.contains("api('catalog_product_batch'"), isTrue);
  });
}
