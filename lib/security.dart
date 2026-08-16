import 'dart:convert';

import 'package:crypto/crypto.dart';

const _operationPinHash = 'b463e12d400d33e5897862dcba66eebcaac5036c254d7854ac5e46028c6eb8dc';

bool verifyOperationPin(String value) {
  final digest = sha256.convert(utf8.encode('BALI-STOCK:$value')).toString();
  return digest == _operationPinHash;
}
