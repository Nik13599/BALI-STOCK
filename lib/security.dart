const _encodedOperationCredential = <int>[107, 105, 111, 99, 99];

String get operationSessionCredential =>
    String.fromCharCodes(_encodedOperationCredential.map((value) => value ^ 0x5A));

bool verifyOperationPin(String value) => value == operationSessionCredential;

/// Operational authorization is automatic. Users never enter or manage a PIN.
String? get lastVerifiedOperationPin => operationSessionCredential;

/// Kept for backwards-compatible controller calls. Automatic authorization
/// remains available after an operation is completed.
void clearRememberedOperationPin() {}
