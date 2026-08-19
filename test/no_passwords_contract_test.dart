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

    expect(security.contains('_encodedOperationCredential'), isTrue);
    expect(security.contains('lastVerifiedOperationPin => operationSessionCredential'), isTrue);
    expect(security.contains('void clearRememberedOperationPin() {}'), isTrue);
  });

  test('iPhone launcher strips every reachable runtime password prompt', () {
    final launcher = File('ios-web/launch-v16.html').readAsStringSync();

    expect(launcher.contains("const AUTH=ROOT+'lib/security.dart'"), isTrue);
    expect(launcher.contains('const baseAuth='), isTrue);
    expect(launcher.contains('const autoAuth='), isTrue);
    expect(launcher.contains('const baseEnsure='), isTrue);
    expect(launcher.contains('const autoEnsure='), isTrue);
    expect(launcher.contains("H=H.replace(baseAuth,autoAuth)"), isTrue);
    expect(launcher.contains("H=H.replace(baseEnsure,autoEnsure)"), isTrue);
    expect(launcher.contains("H.includes('Введите пароль доступа')"), isTrue);
    expect(launcher.contains('пользовательский запрос пароля'), isTrue);
  });

  test('password removal is an update of the production baseline', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('version: 1.0.1+101'), isTrue);
  });
}
