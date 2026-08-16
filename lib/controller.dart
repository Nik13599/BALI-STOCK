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
  List<StocktakeDraft> activeStocktakeDrafts = const [];
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
        _repository.getActiveStocktakeDrafts(),
      ]);
      categories = values[0] as List<Category>;
      products = values[1] as List<Product>;
      operations = values[2] as List<StockOperation>;
      activeStocktakeDrafts = values[3] as List<StocktakeDraft>;
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
    required int packageSize,
    required int wholePackages,
    required int extraAmount,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    await _repository.addProduct(
      name: name,
      categoryId: categoryId,
      packageSize: packageSize,
      wholePackages: wholePackages,
      extraAmount: extraAmount,
      minimumAmount: minimumAmount,
      stockUnit: stockUnit,
    );
    await _reloadAfterMutation();
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required int categoryId,
    required int packageSize,
    required int minimumAmount,
    required StockUnit stockUnit,
  }) async {
    await _repository.updateProduct(
      productId: productId,
      name: name,
      categoryId: categoryId,
      packageSize: packageSize,
      minimumAmount: minimumAmount,
      stockUnit: stockUnit,
    );
    await _reloadAfterMutation();
  }

  Future<void> receiveDelivery(List<DeliveryDraftLine> lines) async {
    await _repository.receiveDelivery(lines);
    await _reloadAfterMutation();
  }

  Future<String?> getLastStocktakeEmployee() => _repository.getLastStocktakeEmployee();

  Future<StocktakeDraft?> getActiveStocktakeDraft(String employeeName) =>
      _repository.getActiveStocktakeDraft(employeeName);

  Future<StocktakeDraft> createStocktakeDraft(String employeeName) async {
    final draft = await _repository.createStocktakeDraft(employeeName);
    await _reloadDrafts();
    return draft;
  }

  Future<StocktakeDraft> resumeStocktakeDraft(int draftId) async {
    final draft = await _repository.resumeStocktakeDraft(draftId);
    await _reloadDrafts();
    return draft;
  }

  Future<void> pauseStocktakeDraft(int draftId, int activeSeconds) async {
    await _repository.pauseStocktakeDraft(draftId, activeSeconds);
    await _reloadDrafts();
  }

  Future<void> saveStocktakeActiveSeconds(int draftId, int activeSeconds) =>
      _repository.saveStocktakeActiveSeconds(draftId, activeSeconds);

  Future<void> saveStocktakeDraftLine({
    required int draftId,
    required int productId,
    required int? wholePackages,
    required int? extraAmount,
  }) async {
    await _repository.saveStocktakeDraftLine(
      draftId: draftId,
      productId: productId,
      wholePackages: wholePackages,
      extraAmount: extraAmount,
    );
  }

  Future<void> deleteStocktakeDraft(int draftId) async {
    await _repository.deleteStocktakeDraft(draftId);
    await _reloadDrafts();
  }

  Future<int> completeStocktakeDraft(int draftId, int activeSeconds) async {
    final operationId = await _repository.completeStocktakeDraft(draftId, activeSeconds);
    await _reloadAfterMutation();
    return operationId;
  }

  Future<void> _reloadDrafts() async {
    activeStocktakeDrafts = await _repository.getActiveStocktakeDrafts();
    notifyListeners();
  }

  Future<void> _reloadAfterMutation() async {
    products = await _repository.getProducts();
    operations = await _repository.getOperations();
    activeStocktakeDrafts = await _repository.getActiveStocktakeDrafts();
    notifyListeners();
  }
}
