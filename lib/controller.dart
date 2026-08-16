import 'package:flutter/foundation.dart' hide Category;

import 'data/repository.dart';
import 'models.dart';

class WarehouseController extends ChangeNotifier {
  WarehouseController({WarehouseRepository? repository})
      : _repository = repository ?? WarehouseRepository();

  final WarehouseRepository _repository;

  List<Category> categories = const [];
  List<Product> products = const [];
  List<StockOperation> operations = const [];
  bool loading = true;
  String? error;

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        _repository.getCategories(),
        _repository.getProducts(),
        _repository.getOperations(),
      ]);
      categories = values[0] as List<Category>;
      products = values[1] as List<Product>;
      operations = values[2] as List<StockOperation>;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<int> addCategory(String name) async {
    final id = await _repository.addCategory(name);
    categories = await _repository.getCategories();
    notifyListeners();
    return id;
  }

  Future<void> addProduct({
    required String name,
    required int categoryId,
    required int bottleMl,
    required int wholeBottles,
    required int extraMl,
    required int minimumMl,
  }) async {
    await _repository.addProduct(
      name: name,
      categoryId: categoryId,
      bottleMl: bottleMl,
      wholeBottles: wholeBottles,
      extraMl: extraMl,
      minimumMl: minimumMl,
    );
    await _reloadAfterMutation();
  }

  Future<void> receiveDelivery(List<DeliveryDraftLine> lines) async {
    await _repository.receiveDelivery(lines);
    await _reloadAfterMutation();
  }

  Future<void> conductStocktake(Map<int, StocktakeDraftLine> values) async {
    await _repository.conductStocktake(values);
    await _reloadAfterMutation();
  }

  Future<void> _reloadAfterMutation() async {
    products = await _repository.getProducts();
    operations = await _repository.getOperations();
    notifyListeners();
  }
}
