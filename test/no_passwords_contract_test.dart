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

  test('production updates authenticate to Supabase with GitHub OIDC', () {
    final workflow = File('.github/workflows/production-release.yml').readAsStringSync();
    final runtimeBuilder = File('tool/build_ios_production_runtime.py').readAsStringSync();

    expect(workflow.contains('id-token: write'), isTrue);
    expect(workflow.contains('bali-stock-signing-broker'), isTrue);
    expect(workflow.contains('audience=bali-stock-android-signing'), isTrue);
    expect(workflow.contains('bali-stock-runtime-publisher'), isTrue);
    expect(workflow.contains('audience=bali-stock-runtime-publish'), isTrue);
    expect(workflow.contains('95345c6b0eacfbae8e102f1b056e626edffcc41a2c84655c6ac86ba725bc274f'), isTrue);
    expect(workflow.contains('openssl rand'), isFalse);
    expect(runtimeBuilder.contains('raw.githack.com'), isTrue); // forbidden-content check only
    expect(runtimeBuilder.contains('raw.githubusercontent.com/Nik13599/BALI-STOCK'), isTrue); // forbidden-content check only
    expect(runtimeBuilder.contains('RUNTIME_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios-runtime"'), isTrue);
  });

  test('obsolete GitHub Pages application channel is retired', () {
    final pages = File('.github/workflows/pages-v12-fixed.yml').readAsStringSync();
    expect(pages.contains('workflow_dispatch'), isTrue);
    expect(pages.contains('push:'), isFalse);
    expect(pages.contains('actions/deploy-pages'), isFalse);
    expect(pages.contains('intentionally retired'), isTrue);
  });

  test('password removal remains an update of the production baseline', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);

    final major = int.parse(match!.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    final build = int.parse(match.group(4)!);
    final versionIsAtLeast101 = major > 1 ||
        (major == 1 && (minor > 0 || (minor == 0 && patch >= 1)));

    expect(versionIsAtLeast101, isTrue);
    expect(build, greaterThanOrEqualTo(101));
  });

  test('legacy iPhone launchers never load BALI STOCK application code from GitHub', () {
    const paths = [
      'ios-web/index.html',
      'ios-web/launch-v14-3.html',
      'ios-web/launch-v15.html',
      'ios-web/launch-v16.html',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source.contains('raw.githack.com/Nik13599/BALI-STOCK'), isFalse, reason: path);
      expect(source.contains('raw.githubusercontent.com/Nik13599/BALI-STOCK'), isFalse, reason: path);
      expect(source.contains('cdn.jsdelivr.net/gh/Nik13599/BALI-STOCK'), isFalse, reason: path);
    }
  });
}
