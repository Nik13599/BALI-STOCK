import 'package:flutter/material.dart';

import '../security.dart';

/// Backwards-compatible authorization hook.
///
/// BALI STOCK no longer asks the user for passwords or PIN codes. Existing
/// screens may still call this helper, but authorization is supplied
/// automatically and no dialog is rendered.
Future<String?> showOperationPinValueDialog(BuildContext _) async => lastVerifiedOperationPin;
