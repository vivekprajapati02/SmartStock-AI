import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/fetched.dart';
import '../../data/models/inventory_models.dart';
import '../../data/models/page_result.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../inventory/inventory_controller.dart';

/// Arguments for the record-movement route; all optional pre-selections.
class MovementFormArgs {
  const MovementFormArgs({this.productId, this.storeId, this.productLabel});

  final String? productId;
  final String? storeId;
  final String? productLabel;
}

class MovementsController extends PagedController<Movement> {
  MovementsController(this._inventory, this._catalog);

  final InventoryRepository _inventory;
  final CatalogRepository _catalog;

  final RxnString storeId = RxnString();
  final Rxn<Product> product = Rxn<Product>();
  final RxList<Store> stores = <Store>[].obs;

  @override
  void onReady() {
    super.onReady();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      stores.assignAll((await _catalog.listStores()).items);
    } on ApiException {
      // Optional filter data.
    }
  }

  @override
  Future<Fetched<PageResult<Movement>>> fetchPage(int offset, int limit) async =>
      Fetched(await _inventory.listMovements(
        storeId: storeId.value,
        productId: product.value?.id,
        offset: offset,
        limit: limit,
      ));

  void setStore(String? id) {
    storeId.value = id;
    reload();
  }

  void setProduct(Product? value) {
    product.value = value;
    reload();
  }

  Future<List<Product>> searchProducts(String query) =>
      searchCatalogProducts(_catalog, query);
}

Future<List<Product>> searchCatalogProducts(
  CatalogRepository catalog,
  String query,
) async {
  try {
    final page = await catalog.listProducts(
      search: query.trim().isEmpty ? null : query.trim(),
      limit: 20,
    );
    return page.items;
  } on ApiException {
    return const [];
  }
}

/// Client-side checks mirroring the backend's `MovementCreate` validator.
String? validateMovementQuantity(MovementType type, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'Quantity is required';
  final value = double.tryParse(text);
  if (value == null) return 'Enter a number';
  if (type == MovementType.adjust) {
    if (value == 0) return 'Adjustment must be a non-zero change (e.g. -3 or 5)';
  } else if (value <= 0) {
    return 'Quantity must be greater than zero';
  }
  return null;
}

class MovementFormController extends GetxController {
  MovementFormController(this._inventory, this._catalog, this.args);

  final InventoryRepository _inventory;
  final CatalogRepository _catalog;
  final MovementFormArgs args;

  final RxList<Store> stores = <Store>[].obs;
  final RxnString storeId = RxnString();
  final RxnString productId = RxnString();
  final RxnString productLabel = RxnString();
  final Rx<MovementType> type = MovementType.stockIn.obs;
  final RxBool submitting = false.obs;
  final RxnString formError = RxnString();
  final RxBool loadingStores = true.obs;

  @override
  void onInit() {
    super.onInit();
    storeId.value = args.storeId;
    productId.value = args.productId;
    productLabel.value = args.productLabel;
  }

  @override
  void onReady() {
    super.onReady();
    loadStores();
  }

  Future<void> loadStores() async {
    loadingStores.value = true;
    try {
      stores.assignAll((await _catalog.listStores()).items);
    } on ApiException catch (e) {
      formError.value = 'Could not load stores: ${e.displayMessage}';
    } finally {
      loadingStores.value = false;
    }
  }

  Future<List<Product>> searchProducts(String query) =>
      searchCatalogProducts(_catalog, query);

  void selectProduct(Product product) {
    productId.value = product.id;
    productLabel.value = '${product.sku} ${product.name}';
  }

  /// Submits the movement. Returns the created movement, or null on failure
  /// (with [formError] set to the server's message, e.g. insufficient stock).
  Future<Movement?> submit({
    required String quantity,
    String? reference,
    String? note,
  }) async {
    formError.value = null;
    if (productId.value == null) {
      formError.value = 'Choose a product';
      return null;
    }
    if (storeId.value == null) {
      formError.value = 'Choose a store';
      return null;
    }
    final quantityError = validateMovementQuantity(type.value, quantity);
    if (quantityError != null) {
      formError.value = quantityError;
      return null;
    }
    submitting.value = true;
    try {
      final movement = await _inventory.recordMovement(MovementInput(
        productId: productId.value!,
        storeId: storeId.value!,
        movementType: type.value,
        quantity: quantity.trim(),
        reference: reference?.trim(),
        note: note?.trim(),
      ));
      if (Get.isRegistered<MovementsController>()) {
        Get.find<MovementsController>().reload();
      }
      if (Get.isRegistered<InventoryController>()) {
        Get.find<InventoryController>().reload();
      }
      return movement;
    } on ApiException catch (e) {
      formError.value = e.displayMessage;
      return null;
    } finally {
      submitting.value = false;
    }
  }
}
