import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/fetched.dart';
import '../../data/models/page_result.dart';
import '../../data/models/planning_models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/planning_repository.dart';
import '../movements/movements_controller.dart' show searchCatalogProducts;

/// Runs [action]; returns an error message or null.
Future<String?> guard(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on ApiException catch (e) {
    return e.displayMessage;
  }
}

// ---------------------------------------------------------------- alerts

class AlertsController extends PagedController<StockAlert> {
  AlertsController(this._repo);

  final PlanningRepository _repo;

  /// Null shows every status.
  final Rxn<AlertStatus> statusFilter = Rxn<AlertStatus>(AlertStatus.open);
  final RxBool evaluating = false.obs;
  final Rxn<EvaluateResult> lastEvaluation = Rxn<EvaluateResult>();

  @override
  Future<Fetched<PageResult<StockAlert>>> fetchPage(int offset, int limit) async =>
      Fetched(await _repo.alerts(status: statusFilter.value, offset: offset, limit: limit));

  void setStatus(AlertStatus? value) {
    statusFilter.value = value;
    reload();
  }

  Future<String?> evaluate() async {
    evaluating.value = true;
    try {
      return await guard(() async {
        lastEvaluation.value = await _repo.evaluateAlerts();
        await reload();
      });
    } finally {
      evaluating.value = false;
    }
  }

  Future<String?> setAlertStatus(StockAlert alert, AlertStatus status) =>
      guard(() async {
        await _repo.updateAlert(alert.id, status);
        await reload();
      });
}

// ---------------------------------------------------------------- replenishment

class ReplenishmentController extends PagedController<ReplenishmentItem> {
  ReplenishmentController(this._repo, this._catalog);

  final PlanningRepository _repo;
  final CatalogRepository _catalog;

  final RxList<Store> stores = <Store>[].obs;
  final RxnString storeId = RxnString();
  final RxBool reorderOnly = true.obs;
  final RxBool busy = false.obs;

  @override
  void onReady() {
    super.onReady();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      stores.assignAll((await _catalog.listStores()).items);
    } on ApiException {
      // Optional filter.
    }
  }

  @override
  Future<Fetched<PageResult<ReplenishmentItem>>> fetchPage(int offset, int limit) async =>
      Fetched(await _repo.replenishment(
        storeId: storeId.value,
        needsReorder: reorderOnly.value ? true : null,
        offset: offset,
        limit: limit,
      ));

  void setStore(String? id) {
    storeId.value = id;
    reload();
  }

  void setReorderOnly(bool value) {
    reorderOnly.value = value;
    reload();
  }

  /// Returns a user-facing result message.
  Future<String> applySettings() async {
    busy.value = true;
    try {
      var updated = 0;
      final error = await guard(() async {
        updated = await _repo.applyReplenishment(storeId: storeId.value);
        await reload();
      });
      return error ?? 'Updated reorder point and safety stock on $updated stock rows';
    } finally {
      busy.value = false;
    }
  }

  Future<(FromRecommendationsResult?, String?)> createDraftOrders() async {
    final store = storeId.value;
    if (store == null) return (null, 'Choose a store first');
    busy.value = true;
    try {
      FromRecommendationsResult? result;
      final error = await guard(() async {
        result = await _repo.fromRecommendations(store);
        await reload();
      });
      return (result, error);
    } finally {
      busy.value = false;
    }
  }
}

// ---------------------------------------------------------------- purchase orders

class PurchaseOrdersController extends PagedController<PurchaseOrder> {
  PurchaseOrdersController(this._repo);

  final PlanningRepository _repo;
  final Rxn<POStatus> statusFilter = Rxn<POStatus>();

  @override
  Future<Fetched<PageResult<PurchaseOrder>>> fetchPage(int offset, int limit) async =>
      Fetched(await _repo.purchaseOrders(
          status: statusFilter.value, offset: offset, limit: limit));

  void setStatus(POStatus? value) {
    statusFilter.value = value;
    reload();
  }
}

class PODetailController extends GetxController {
  PODetailController(this._repo, this.orderId);

  final PlanningRepository _repo;
  final String orderId;

  final Rxn<PurchaseOrder> order = Rxn<PurchaseOrder>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool offline = false.obs;
  final RxBool busy = false.obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      order.value = await _repo.purchaseOrder(orderId);
    } on ApiException catch (e) {
      error.value = e.displayMessage;
      offline.value = e.isOffline;
    } finally {
      loading.value = false;
    }
  }

  void _refreshList() {
    if (Get.isRegistered<PurchaseOrdersController>()) {
      Get.find<PurchaseOrdersController>().reload();
    }
  }

  Future<String?> transition(String action) async {
    busy.value = true;
    try {
      return await guard(() async {
        order.value = await _repo.transition(orderId, action);
        _refreshList();
      });
    } finally {
      busy.value = false;
    }
  }

  /// [quantities] maps item id to the quantity text entered (blank = skip).
  Future<String?> receive(Map<String, String> quantities, {String? note}) async {
    final lines = <String, String>{};
    for (final entry in quantities.entries) {
      final text = entry.value.trim();
      if (text.isEmpty) continue;
      final value = double.tryParse(text);
      if (value == null || value <= 0) return 'Quantities must be positive numbers';
      lines[entry.key] = text;
    }
    if (lines.isEmpty) return 'Enter a quantity for at least one line';
    busy.value = true;
    try {
      return await guard(() async {
        order.value = await _repo.receive(orderId, lines, note: note);
        _refreshList();
      });
    } finally {
      busy.value = false;
    }
  }
}

class POFormLine {
  POFormLine(this.product, this.quantity);

  final Product product;
  String quantity;
}

class POFormController extends GetxController {
  POFormController(this._repo, this._catalog);

  final PlanningRepository _repo;
  final CatalogRepository _catalog;

  final RxList<Supplier> suppliers = <Supplier>[].obs;
  final RxList<Store> stores = <Store>[].obs;
  final RxnString supplierId = RxnString();
  final RxnString storeId = RxnString();
  final RxList<POFormLine> lines = <POFormLine>[].obs;
  final RxBool saving = false.obs;
  final RxnString formError = RxnString();

  @override
  void onReady() {
    super.onReady();
    loadLookups();
  }

  Future<void> loadLookups() async {
    final error = await guard(() async {
      suppliers.assignAll((await _catalog.listSuppliers()).items);
      stores.assignAll((await _catalog.listStores()).items);
    });
    if (error != null) formError.value = error;
  }

  Future<List<Product>> searchProducts(String q) => searchCatalogProducts(_catalog, q);

  void addProduct(Product product) {
    if (lines.any((l) => l.product.id == product.id)) {
      formError.value = '${product.sku} is already on this order';
      return;
    }
    formError.value = null;
    lines.add(POFormLine(product, '1'));
  }

  void removeLine(POFormLine line) => lines.remove(line);

  /// Returns the created order, or null with [formError] set.
  Future<PurchaseOrder?> save({String? reference}) async {
    formError.value = null;
    if (supplierId.value == null) {
      formError.value = 'Choose a supplier';
      return null;
    }
    if (storeId.value == null) {
      formError.value = 'Choose a store';
      return null;
    }
    if (lines.isEmpty) {
      formError.value = 'Add at least one product';
      return null;
    }
    for (final line in lines) {
      final q = double.tryParse(line.quantity.trim());
      if (q == null || q <= 0) {
        formError.value = 'Quantity for ${line.product.sku} must be greater than zero';
        return null;
      }
    }
    saving.value = true;
    try {
      PurchaseOrder? created;
      final error = await guard(() async {
        created = await _repo.createPurchaseOrder(
          supplierId: supplierId.value!,
          storeId: storeId.value!,
          reference: reference,
          lines: [for (final l in lines) POLineInput(l.product.id, l.quantity.trim())],
        );
      });
      formError.value = error;
      if (created != null && Get.isRegistered<PurchaseOrdersController>()) {
        Get.find<PurchaseOrdersController>().reload();
      }
      return created;
    } finally {
      saving.value = false;
    }
  }
}
