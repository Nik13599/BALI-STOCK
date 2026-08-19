import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native operational authorization never renders a password dialog', () {
    final dialog = File('lib/widgets/pin_value_dialog.dart').readAsStringSync();
    final security = File('lib/security.dart').readAsStringSync();

    expect(dialog.contains('showDialog'), isFalse);
    expect(dialog.contains('TextField'), isFalse);
    expect(dialog.contains('obscureText'), isFalse);
    expect(dialog.contains('Введите пароль'), isFalse);
    expect(dialog.contains('lastVerifiedOperationPin'), isTrue);

    expect(security.contains('_encodedOperationCredential'), isFalse);
    expect(security.contains('_operationPinHash'), isFalse);
    expect(security.contains('bool verifyOperationPin(String _) => true;'), isTrue);
    expect(security.contains('void clearRememberedOperationPin() {}'), isTrue);
  });

  test('native network layer uses passwordless client API and never sends PIN header', () {
    final remote = File('lib/data/remote_stock_service.dart').readAsStringSync();

    expect(remote.contains('/functions/v1/bali-stock-client-api'), isTrue);
    expect(remote.contains('/functions/v1/bali-stock-api\''), isFalse);
    expect(remote.contains('x-bali-stock-pin'), isFalse);
    expect(remote.contains("headers: {...readHeaders, 'Content-Type': 'application/json'}"), isTrue);
  });

  test('iPhone installation profile is independent from GitHub', () {
    final generator = File('tool/generate_mobileconfig.py').readAsStringSync();
    final smoke = File('.github/workflows/iphone-runtime-smoke.yml').readAsStringSync();

    expect(generator.contains('/functions/v1/bali-stock-ios-runtime'), isTrue);
    expect(generator.contains('raw.githack.com'), isFalse);
    expect(generator.contains('raw.githubusercontent.com'), isFalse);
    expect(smoke.contains("assert 'github' not in clip['URL'].lower()"), isTrue);
    expect(smoke.contains("assert data['github_dependency'] is False"), isTrue);
    expect(smoke.contains("assert data['password_prompt'] is False"), isTrue);
  });

  test('password removal is an update of the production baseline', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('version: 1.0.1+101'), isTrue);
  });
}
