import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline background polling checks lightweight version before full refresh', () {
    final source = File('lib/offline_first_controller.dart').readAsStringSync();
    expect(source.contains('bool _polling = false;'), isTrue);
    expect(source.contains('int? _lastSeenRemoteVersion;'), isTrue);
    expect(source.contains('final version = await _remoteSync.fetchVersion();'), isTrue);
    expect(source.contains('if (previousVersion == null || version != previousVersion)'), isTrue);
    expect(source.contains('Future<void> _rememberRemoteVersionBestEffort() async'), isTrue);
    expect(source.contains('Timer.periodic(const Duration(seconds: 15)'), isTrue);

    final tickStart = source.indexOf('Future<void> _backgroundTick() async');
    final rememberStart = source.indexOf('Future<void> _rememberRemoteVersionBestEffort() async');
    expect(tickStart, greaterThanOrEqualTo(0));
    expect(rememberStart, greaterThan(tickStart));

    final tick = source.substring(tickStart, rememberStart);
    expect(tick.contains('if (_syncing || _polling) return;'), isTrue);
    expect(tick.contains('_polling = true;'), isTrue);
    expect(tick.contains('_polling = false;'), isTrue);
    expect(tick.indexOf('_remoteSync.fetchVersion()'), lessThan(tick.indexOf('super.onAppResumed()')));
    expect(tick.contains('await super.onAppResumed();'), isTrue);
    expect(tick.contains('_offlineOnline = super.sharedOnline;'), isTrue);
  });

  test('base remote service exposes a lightweight version endpoint with shorter timeout', () {
    final source = File('lib/data/remote_stock_service.dart').readAsStringSync();
    expect(source.contains("endpoint?action=version"), isTrue);
    expect(source.contains('Duration(seconds: 10)'), isTrue);
  });

  test('iPhone runtime replaces five-second full snapshots with version polling', () {
    final builder = File('tool/build_ios_production_runtime.py').readAsStringSync();
    final module = File('ios-web/ios-runtime-performance.js').readAsStringSync();
    expect(builder.contains('harden_runtime_polling(html)'), isTrue);
    expect(builder.contains('baliPollSnapshotVersion'), isTrue);
    expect(builder.contains('},15000)'), isTrue);
    expect(module.contains('__BALI_STOCK_IOS_RUNTIME_PERFORMANCE__'), isTrue);
    expect(module.contains("API + '?action=version'"), isTrue);
    expect(module.contains('if (version && version !== lastVersion)'), isTrue);
    expect(module.contains('await snapshot();'), isTrue);
  });

  test('authorization compatibility call no longer performs a network round trip', () {
    final source = File('lib/data/remote_stock_service.dart').readAsStringSync();
    final start = source.indexOf('Future<void> authorize(String _) async');
    final next = source.indexOf('Future<Map<String, dynamic>> syncCatalog', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(next, greaterThan(start));
    final method = source.substring(start, next);
    expect(method.contains("post('', {'action': 'authorize'})"), isFalse);
    expect(method.contains('http.'), isFalse);
  });

  test('primary section navigation paints before any operation-session network work', () {
    final source = File('lib/app.dart').readAsStringSync();
    final selectStart = source.indexOf('void _select(int index)');
    final prepareStart = source.indexOf('Future<void> _prepareOperationSession() async');
    expect(selectStart, greaterThanOrEqualTo(0));
    expect(prepareStart, greaterThan(selectStart));

    final select = source.substring(selectStart, prepareStart);
    expect(select.contains('await '), isFalse);
    expect(select.contains('showOperationPinValueDialog'), isFalse);
    expect(select.contains('setOperationSessionPin'), isFalse);
    expect(select.contains('setState(() => _selectedIndex = index);'), isTrue);
    expect(select.contains('addPostFrameCallback'), isTrue);
    expect(select.contains('unawaited(_prepareOperationSession())'), isTrue);
  });

  test('operation session is primed synchronously before background preparation', () {
    final base = File('lib/controller.dart').readAsStringSync();
    final offline = File('lib/offline_first_controller.dart').readAsStringSync();
    expect(base.contains('void primeOperationSessionPin(String pin)'), isTrue);
    expect(offline.contains('super.primeOperationSessionPin(pin);'), isTrue);
    expect(offline.contains('unawaited(task.whenComplete(() => _sessionPreparation = null));'), isTrue);

    final start = offline.indexOf('Future<void> setOperationSessionPin(String pin)');
    final next = offline.indexOf('Future<void> _prepareOperationSession', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(next, greaterThan(start));
    final method = offline.substring(start, next);
    expect(method.contains('await '), isFalse);
    expect(method.contains('Future<void>.value()'), isTrue);
  });

  test('local durable mutations never wait for network flush before returning', () {
    final source = File('lib/offline_first_controller.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _afterLocalMutation() async');
    final next = source.indexOf('Future<void> _flushPendingBestEffort', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(next, greaterThan(start));
    final method = source.substring(start, next);
    expect(method.contains('unawaited(_flushPendingBestEffort(refreshAfter: true));'), isTrue);
    expect(method.contains('await _flushPendingBestEffort'), isFalse);
  });

  test('stocktake resume and pause do not wait for remote draft sync', () {
    final source = File('lib/controller.dart').readAsStringSync();
    final resumeStart = source.indexOf('Future<StocktakeDraft> resumeStocktakeDraft');
    final pauseStart = source.indexOf('Future<void> pauseStocktakeDraft', resumeStart);
    final secondsStart = source.indexOf('Future<void> saveStocktakeActiveSeconds', pauseStart);
    expect(resumeStart, greaterThanOrEqualTo(0));
    expect(pauseStart, greaterThan(resumeStart));
    expect(secondsStart, greaterThan(pauseStart));
    final resume = source.substring(resumeStart, pauseStart);
    final pause = source.substring(pauseStart, secondsStart);
    expect(resume.contains('unawaited(_syncDraftBestEffort(draftId));'), isTrue);
    expect(pause.contains('unawaited(_syncDraftBestEffort(draftId));'), isTrue);
  });

  test('V14 hot-path actions do not block on a second full snapshot', () {
    final source = File('lib/v14_controller.dart').readAsStringSync();
    expect(source.contains('_loadV14SnapshotBestEffort'), isFalse);
    expect(source.contains('void onSharedSnapshot(Map<String, dynamic> snapshot)'), isTrue);
    expect(source.contains('unawaited(refresh());'), isTrue);

    final start = source.indexOf('Future<void> setOperationSessionPin(String pin)');
    final next = source.indexOf('void clearOperationSessionPin()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(next, greaterThan(start));
    final method = source.substring(start, next);
    expect(method.contains('fetchSnapshot'), isFalse);
    expect(method.contains('_loadV14SnapshotBestEffort'), isFalse);
  });

  test('refresh keeps an already populated working screen visible', () {
    final source = File('lib/controller.dart').readAsStringSync();
    final start = source.indexOf('Future<void> refresh() async');
    final next = source.indexOf('void primeOperationSessionPin', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(next, greaterThan(start));
    final method = source.substring(start, next);
    expect(method.contains('final showBlockingLoader = products.isEmpty && categories.isEmpty && operations.isEmpty;'), isTrue);
    expect(method.contains('if (showBlockingLoader)'), isTrue);
  });

  test('sync status updates do not rebuild the active working screen', () {
    final source = File('lib/app.dart').readAsStringSync();
    final methodStart = source.indexOf('Widget _pageWithSyncStatus()');
    final buildStart = source.indexOf('@override\n  Widget build(BuildContext context)', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(buildStart, greaterThan(methodStart));

    final method = source.substring(methodStart, buildStart);
    expect(method.contains('child: _page(),'), isTrue);
    expect(method.contains('builder: (context, page)'), isTrue);
    expect(method.contains('Expanded(child: page!)'), isTrue);
    expect(method.contains('Expanded(child: _page())'), isFalse);
  });
}
