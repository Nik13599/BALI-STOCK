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

    final tickStart = source.indexOf('Future<void> _backgroundTick() async');
    final rememberStart = source.indexOf('Future<void> _rememberRemoteVersionBestEffort() async');
    expect(tickStart, greaterThanOrEqualTo(0));
    expect(rememberStart, greaterThan(tickStart));

    final tick = source.substring(tickStart, rememberStart);
    expect(tick.contains('if (_syncing || _polling) return;'), isTrue);
    expect(tick.contains('_polling = true;'), isTrue);
    expect(tick.contains('_polling = false;'), isTrue);
    expect(tick.indexOf('_remoteSync.fetchVersion()'), lessThan(tick.indexOf('super.onAppResumed()')));
    expect(tick.contains('await super.onAppResumed();\n      _offlineOnline = super.sharedOnline;'), isTrue);
  });

  test('base remote service exposes a lightweight version endpoint with shorter timeout', () {
    final source = File('lib/data/remote_stock_service.dart').readAsStringSync();
    expect(source.contains("endpoint?action=version"), isTrue);
    expect(source.contains('Duration(seconds: 10)'), isTrue);
  });
}
