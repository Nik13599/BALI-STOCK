import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passwordless client API rejects arbitrary app keys', () {
    final server = File('supabase/functions/bali-stock-client-api/index.ts').readAsStringSync();
    final client = File('lib/data/remote_stock_service.dart').readAsStringSync();

    expect(server.contains('if (!key) throw new Error("CLIENT_KEY_REQUIRED");'), isTrue);
    expect(server.contains('if (key !== CLIENT_KEY) throw new Error("CLIENT_KEY_INVALID");'), isTrue);
    expect(server.contains('unauthorized ? 401 : 400'), isTrue);

    final serverKey = RegExp(r'const CLIENT_KEY = "([^"]+)";').firstMatch(server)?.group(1);
    final clientKey = RegExp(r"static const _publishableKey = '([^']+)';").firstMatch(client)?.group(1);
    expect(serverKey, isNotNull);
    expect(serverKey, clientKey);

    expect(client.contains('bali-stock-client-api'), isTrue);
    expect(client.contains('x-bali-stock-pin'), isFalse);
  });

  test('queued offline sync requires the same BALI STOCK client key before service-role work', () {
    final server = File('supabase/functions/bali-stock-sync-api/index.ts').readAsStringSync();
    final queuedClient = File('lib/data/remote_stock_sync_extension.dart').readAsStringSync();
    final primaryClient = File('lib/data/remote_stock_service.dart').readAsStringSync();

    expect(server.contains('function hasValidClientKey(req: Request)'), isTrue);
    expect(server.contains('if (!hasValidClientKey(req)) return json({ error: "CLIENT_KEY_REQUIRED" }, 401);'), isTrue);
    expect(server.contains('x-bali-stock-pin'), isFalse);
    expect(queuedClient.contains('...readHeaders'), isTrue);

    final syncKey = RegExp(r'const CLIENT_KEY = "([^"]+)";').firstMatch(server)?.group(1);
    final clientKey = RegExp(r"static const _publishableKey = '([^']+)';").firstMatch(primaryClient)?.group(1);
    expect(syncKey, isNotNull);
    expect(syncKey, clientKey);
  });
}
