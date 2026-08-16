import 'dart:convert';

import 'package:crypto/crypto.dart';

const _operationPinHash = 'b463e12d400d33e5897862dcba66eebcaac5036c254d7854ac5e46028c6eb8dc';
String? _lastVerifiedOperationPin;

bool verifyOperationPin(String value) {
  final digest = sha256.convert(utf8.encode('BALI-STOCK:$value')).toString();
  final valid = digest == _operationPinHash;
  if (valid) _lastVerifiedOperationPin = value;
  return valid;
}

/// PIN is never persisted. This getter only lets a controller adopt a PIN that
/// was just verified by a protected UI dialog in the current process.
String? get lastVerifiedOperationPin => _lastVerifiedOperationPin;

void clearRememberedOperationPin() => _lastVerifiedOperationPin = null;
