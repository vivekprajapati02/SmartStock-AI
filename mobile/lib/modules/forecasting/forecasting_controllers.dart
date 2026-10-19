import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/forecast_models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/forecast_repository.dart';
import '../../widgets/async_state_view.dart';
import '../movements/movements_controller.dart' show searchCatalogProducts;

/// Persisted backtest results for one horizon; can trigger a new backtest.
class EvaluationController extends GetxController {
  EvaluationController(this._repo);

  final ForecastRepository _repo;

  final RxInt horizon = 30.obs;
  final Rx<LoadStatus> status = LoadStatus.initial.obs;
  final Rxn<ModelComparison> comparison = Rxn<ModelComparison>();
  final RxnString error = RxnString();
  final RxBool running = false.obs;
  final RxnString runError = RxnString();

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> setHorizon(int value) async {
    if (horizon.value == value) return;
    horizon.value = value;
    comparison.value = null;
    await load();
  }

  Future<void> load() async {
    final requested = horizon.value;
    status.value = LoadStatus.loading;
    error.value = null;
    try {
      final result = await _repo.comparison(requested);
      if (requested != horizon.value) return;
      comparison.value = result;
      status.value = result.isEmpty ? LoadStatus.empty : LoadStatus.data;
    } on ApiException catch (e) {
      if (requested != horizon.value) return;
      error.value = e.displayMessage;
      status.value = e.isOffline ? LoadStatus.offline : LoadStatus.error;
    }
  }

  Future<bool> runBacktest() async {
    if (running.value) return false;
    running.value = true;
    runError.value = null;
    final requested = horizon.value;
    try {
      final result = await _repo.runBacktest(requested);
      if (requested == horizon.value) {
        comparison.value = result;
        status.value = result.isEmpty ? LoadStatus.empty : LoadStatus.data;
      }
      return true;
    } on ApiException catch (e) {
      runError.value = e.displayMessage;
      return false;
    } finally {
      running.value = false;
    }
  }
}

/// History plus forecast for one SKU/store, and org-wide generation.
class ForecastController extends GetxController {
  ForecastController(this._repo, this._catalog);

  final ForecastRepository _repo;
  final CatalogRepository _catalog;

  final RxInt horizon = 30.obs;
  final RxList<Store> stores = <Store>[].obs;
  final Rxn<Product> product = Rxn<Product>();
  final RxnString storeId = RxnString();
  final Rx<LoadStatus> status = LoadStatus.initial.obs;
  final Rxn<ForecastSeries> series = Rxn<ForecastSeries>();
  final RxnString error = RxnString();
  final RxBool generating = false.obs;
  final RxnString generateError = RxnString();

  @override
  void onReady() {
    super.onReady();
    init();
  }

  /// Loads stores and preselects the first product/store so the screen shows
  /// real data immediately.
  Future<void> init() async {
    status.value = LoadStatus.loading;
    try {
      stores.assignAll((await _catalog.listStores()).items);
      final products = (await _catalog.listProducts(limit: 1)).items;
      if (stores.isEmpty || products.isEmpty) {
        status.value = LoadStatus.empty;
        return;
      }
      product.value = products.first;
      storeId.value = stores.first.id;
      await load();
    } on ApiException catch (e) {
      error.value = e.displayMessage;
      status.value = e.isOffline ? LoadStatus.offline : LoadStatus.error;
    }
  }

  Future<List<Product>> searchProducts(String q) => searchCatalogProducts(_catalog, q);

  void selectProduct(Product p) {
    product.value = p;
    load();
  }

  void selectStore(String? id) {
    storeId.value = id;
    load();
  }

  void setHorizon(int value) {
    if (horizon.value == value) return;
    horizon.value = value;
    load();
  }

  Future<void> load() async {
    final p = product.value;
    final s = storeId.value;
    if (p == null || s == null) {
      status.value = LoadStatus.empty;
      return;
    }
    final key = '${p.id}|$s|${horizon.value}';
    status.value = LoadStatus.loading;
    error.value = null;
    try {
      final result = await _repo.series(
        productId: p.id,
        storeId: s,
        horizon: horizon.value,
      );
      if (key != '${product.value?.id}|${storeId.value}|${horizon.value}') return;
      series.value = result;
      status.value = LoadStatus.data;
    } on ApiException catch (e) {
      error.value = e.displayMessage;
      status.value = e.isOffline ? LoadStatus.offline : LoadStatus.error;
    }
  }

  Future<bool> generate() async {
    if (generating.value) return false;
    generating.value = true;
    generateError.value = null;
    try {
      await _repo.generate(horizon.value);
      await load();
      return true;
    } on ApiException catch (e) {
      generateError.value = e.displayMessage;
      return false;
    } finally {
      generating.value = false;
    }
  }
}
