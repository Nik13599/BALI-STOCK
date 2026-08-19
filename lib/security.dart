const _automaticOperationSession = 'automatic';

String get operationSessionCredential => _automaticOperationSession;

/// Passwords and PIN codes are not used by BALI STOCK.
bool verifyOperationPin(String _) => true;

/// Backwards-compatible value for controller methods that still accept the old
/// operation-session parameter. The server no longer treats it as a password.
String? get lastVerifiedOperationPin => _automaticOperationSession;

void clearRememberedOperationPin() {}
