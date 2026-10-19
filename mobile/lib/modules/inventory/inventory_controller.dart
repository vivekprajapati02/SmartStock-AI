import 'dart:async';

import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/fetched.dart';
import '../../data/models/inventory_models.dart';
import '../../data/models/page_result.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';

class InventoryController extends PagedController<InventoryItem> {
  InventoryController(this._inventory, this._catalog);

  final InventoryRepository _inventory;
  final CatalogRepository _catalog;

  final RxnString storeId = RxnString();
  final RxBool lowStockOnly = false.obs;
  final RxString search = ''.obs;
  final RxList<Store> stores = <Store>[].obs;

  Timer? _debounce;

  InventoryQuery get query => InventoryQuery(
        storeId: storeId.value,
        lowStockOnly: lowStockOnly.value,
        search: search.value.trim().isEmpty ? null : search.value.trim(),
      );

  @override
  void onReady() {
    super.onReady();
    loadStores();
  }

  Future<void> loadStores() async {
    try {
      final page = await _catalog.listStores();
      stores.assignAll(page.items);
    } on ApiException {
      // Filter list is optional; the inventory list reports its own errors.
    }
  }

  @override
  Future<Fetched<PageResult<InventoryItem>>> fetchPage(int offset, int limit) =>
      _inventory.listInventory(query, offset: offset, limit: limit);

  void setStore(String? id) {
    if (storeId.value == id) return;
    storeId.value = id;
    reload();
  }

  void setLowStockOnly(bool value) {
    if (lowStockOnly.value == value) return;
    lowStockOnly.value = value;
    reload();
  }

  void setSearch(String value, {Duration debounce = const Duration(milliseconds: 350)}) {
    search.value = value;
    _debounce?.cancel();
    _debounce = Timer(debounce, reload);
  }

  /// Replaces one row after it changed elsewhere (movement or settings edit).
  void replaceItem(InventoryItem updated) {
    final index = items.indexWhere((i) => i.id == updated.id);
    if (index >= 0) items[index] = updated;
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

class InventoryDetailController extends GetxController {
  InventoryDetailController(this._inventory, this.inventoryId);

  final InventoryRepository _inventory;
  final String inventoryId;

  final Rxn<InventoryItem> item = Rxn<InventoryItem>();
  final RxList<Movement> recentMovements = <Movement>[].obs;
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool offline = false.obs;
  final RxBool saving = false.obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    offline.value = false;
    try {
      final result = await _inventory.getInventory(inventoryId);
      item.value = result;
      final movements = await _inventory.listMovements(
        productId: result.productId,
        storeId: result.storeId,
        limit: 20,
      );
      recentMovements.assignAll(movements.items);
    } on ApiException catch (e) {
      error.value = e.displayMessage;
      offline.value = e.isOffline;
    } finally {
      loading.value = false;
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> saveSettings({
    required String reorderPoint,
    required String safetyStock,
    required int leadTimeDays,
  }) async {
    saving.value = true;
    try {
      final updated = await _inventory.updateSettings(
        inventoryId,
        reorderPoint: reorderPoint,
        safetyStock: safetyStock,
        leadTimeDays: leadTimeDays,
      );
      item.value = updated;
      if (Get.isRegistered<InventoryController>()) {
        Get.find<InventoryController>().replaceItem(updated);
      }
      return null;
    } on ApiException catch (e) {
      return e.displayMessage;
    } finally {
      saving.value = false;
    }
  }
}
