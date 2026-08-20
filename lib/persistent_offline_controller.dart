import 'dart:async';

import 'data/offline_control_cache_repository.dart';
import 'offline_first_controller.dart';

class PersistentOfflineWarehouseController extends OfflineFirstWarehouseController {
  PersistentOfflineWarehouseController({OfflineControlCacheRepository? cache})
      : _cache = cache ?? OfflineControlCacheRepository();

  final OfflineControlCacheRepository _cache;

  @override
  Future<void> initialize() async {
    await _cache.ensureSchema();
    final cached = await _cache.load();
    if (cached != null) _applyCached(cached);
    await super.initialize();
    unawaited(_saveIfOnline());
  }

  @override
  Future<void> refresh() async {
    await super.refresh();
    unawaited(_saveIfOnline());
  }

  @override
  Future<void> setOperationSessionPin(String pin) {
    final result = super.setOperationSessionPin(pin);
    unawaited(_saveIfOnline());
    return result;
  }

  @override
  Future<void> onAppResumed() async {
    await super.onAppResumed();
    unawaited(_saveIfOnline());
  }

  void _applyCached(OfflineControlCache cache) {
    suppliers = cache.suppliers;
    productSuppliers = cache.productSuppliers;
    locations = cache.locations;
    locationBalances = cache.locationBalances;
    purchaseSuggestions = cache.purchaseSuggestions;
    analytics = cache.analytics;
    notifyListeners();
  }

  Future<void> _saveIfOnline() async {
    if (!sharedOnline) return;
    await _cache.save(
      suppliers: suppliers,
      productSuppliers: productSuppliers,
      locations: locations,
      locationBalances: locationBalances,
      purchaseSuggestions: purchaseSuggestions,
      analytics: analytics,
    );
  }
}
