import 'dart:async';

import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/fetched.dart';
import '../../data/models/page_result.dart';
import '../../data/repositories/catalog_repository.dart';

/// Runs a write and refreshes the list. Returns an error message or null.
Future<String?> _write(PagedController<dynamic> list, Future<void> Function() op) async {
  try {
    await op();
    await list.reload();
    return null;
  } on ApiException catch (e) {
    return e.displayMessage;
  }
}

class ProductsController extends PagedController<Product> {
  ProductsController(this.repo);

  final CatalogRepository repo;
  final RxString search = ''.obs;
  final RxList<Category> categories = <Category>[].obs;
  final RxList<Supplier> suppliers = <Supplier>[].obs;
  Timer? _debounce;

  @override
  Future<Fetched<PageResult<Product>>> fetchPage(int offset, int limit) async =>
      Fetched(await repo.listProducts(
        offset: offset,
        limit: limit,
        search: search.value.trim().isEmpty ? null : search.value.trim(),
      ));

  void setSearch(String value) {
    search.value = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), reload);
  }

  /// Loads category and supplier options for the product form.
  Future<void> loadLookups() async {
    try {
      final results = await Future.wait([
        repo.listCategories(),
        repo.listSuppliers(),
      ]);
      categories.assignAll((results[0] as PageResult<Category>).items);
      suppliers.assignAll((results[1] as PageResult<Supplier>).items);
    } on ApiException {
      // The form still works without optional lookups.
    }
  }

  Future<String?> save(ProductInput input, {String? id}) => _write(
        this,
        () => id == null ? repo.createProduct(input) : repo.updateProduct(id, input),
      );

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

class StoresController extends PagedController<Store> {
  StoresController(this.repo) : super(pageSize: 200);

  final CatalogRepository repo;

  @override
  Future<Fetched<PageResult<Store>>> fetchPage(int offset, int limit) async =>
      Fetched(await repo.listStores(offset: offset, limit: limit));

  Future<String?> save({String? id, required String name, String? location}) =>
      _write(
        this,
        () => id == null
            ? repo.createStore(name: name, location: location)
            : repo.updateStore(id, name: name, location: location),
      );

  Future<String?> remove(String id) => _write(this, () => repo.deleteStore(id));
}

class CategoriesController extends PagedController<Category> {
  CategoriesController(this.repo) : super(pageSize: 200);

  final CatalogRepository repo;

  @override
  Future<Fetched<PageResult<Category>>> fetchPage(int offset, int limit) async =>
      Fetched(await repo.listCategories(offset: offset, limit: limit));

  Future<String?> save({String? id, required String name}) => _write(
        this,
        () => id == null ? repo.createCategory(name) : repo.updateCategory(id, name),
      );

  Future<String?> remove(String id) =>
      _write(this, () => repo.deleteCategory(id));
}

class SuppliersController extends PagedController<Supplier> {
  SuppliersController(this.repo) : super(pageSize: 200);

  final CatalogRepository repo;

  @override
  Future<Fetched<PageResult<Supplier>>> fetchPage(int offset, int limit) async =>
      Fetched(await repo.listSuppliers(offset: offset, limit: limit));

  Future<String?> save({
    String? id,
    required String name,
    String? contactEmail,
    String? phone,
    required int leadTimeDays,
  }) =>
      _write(
        this,
        () => id == null
            ? repo.createSupplier(
                name: name,
                contactEmail: contactEmail,
                phone: phone,
                leadTimeDays: leadTimeDays,
              )
            : repo.updateSupplier(
                id,
                name: name,
                contactEmail: contactEmail,
                phone: phone,
                leadTimeDays: leadTimeDays,
              ),
      );

  Future<String?> remove(String id) =>
      _write(this, () => repo.deleteSupplier(id));
}
