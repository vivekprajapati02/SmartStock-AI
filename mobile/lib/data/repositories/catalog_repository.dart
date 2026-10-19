import '../../core/network/api_client.dart';
import '../models/catalog_models.dart';
import '../models/page_result.dart';

abstract class CatalogRepository {
  Future<PageResult<Product>> listProducts({
    int limit = 50,
    int offset = 0,
    String? search,
  });
  Future<Product> createProduct(ProductInput input);
  Future<Product> updateProduct(String id, ProductInput input);

  Future<PageResult<Store>> listStores({int limit = 200, int offset = 0});
  Future<Store> createStore({required String name, String? location});
  Future<Store> updateStore(String id, {required String name, String? location});
  Future<void> deleteStore(String id);

  Future<PageResult<Category>> listCategories({int limit = 200, int offset = 0});
  Future<Category> createCategory(String name);
  Future<Category> updateCategory(String id, String name);
  Future<void> deleteCategory(String id);

  Future<PageResult<Supplier>> listSuppliers({int limit = 200, int offset = 0});
  Future<Supplier> createSupplier({
    required String name,
    String? contactEmail,
    String? phone,
    required int leadTimeDays,
  });
  Future<Supplier> updateSupplier(
    String id, {
    required String name,
    String? contactEmail,
    String? phone,
    required int leadTimeDays,
  });
  Future<void> deleteSupplier(String id);
}

class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._api);

  final ApiClient _api;

  Future<PageResult<T>> _page<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> query,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(path, query: query);
    return PageResult.fromJson(json, fromJson);
  }

  static String? _blankToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  @override
  Future<PageResult<Product>> listProducts({
    int limit = 50,
    int offset = 0,
    String? search,
  }) =>
      _page('/products', Product.fromJson,
          {'limit': limit, 'offset': offset, 'search': search});

  @override
  Future<Product> createProduct(ProductInput input) async => Product.fromJson(
      await _api.post<Map<String, dynamic>>('/products', data: input.toJson()));

  @override
  Future<Product> updateProduct(String id, ProductInput input) async =>
      Product.fromJson(await _api.patch<Map<String, dynamic>>(
          '/products/$id',
          data: input.toJson()));

  @override
  Future<PageResult<Store>> listStores({int limit = 200, int offset = 0}) =>
      _page('/stores', Store.fromJson, {'limit': limit, 'offset': offset});

  @override
  Future<Store> createStore({required String name, String? location}) async =>
      Store.fromJson(await _api.post<Map<String, dynamic>>('/stores',
          data: {'name': name.trim(), 'location': _blankToNull(location)}));

  @override
  Future<Store> updateStore(
    String id, {
    required String name,
    String? location,
  }) async =>
      Store.fromJson(await _api.patch<Map<String, dynamic>>('/stores/$id',
          data: {'name': name.trim(), 'location': _blankToNull(location)}));

  @override
  Future<void> deleteStore(String id) => _api.delete('/stores/$id');

  @override
  Future<PageResult<Category>> listCategories({int limit = 200, int offset = 0}) =>
      _page('/categories', Category.fromJson, {'limit': limit, 'offset': offset});

  @override
  Future<Category> createCategory(String name) async => Category.fromJson(
      await _api.post<Map<String, dynamic>>('/categories',
          data: {'name': name.trim()}));

  @override
  Future<Category> updateCategory(String id, String name) async =>
      Category.fromJson(await _api.patch<Map<String, dynamic>>(
          '/categories/$id',
          data: {'name': name.trim()}));

  @override
  Future<void> deleteCategory(String id) => _api.delete('/categories/$id');

  @override
  Future<PageResult<Supplier>> listSuppliers({int limit = 200, int offset = 0}) =>
      _page('/suppliers', Supplier.fromJson, {'limit': limit, 'offset': offset});

  Map<String, dynamic> _supplierBody(
    String name,
    String? contactEmail,
    String? phone,
    int leadTimeDays,
  ) =>
      {
        'name': name.trim(),
        'contact_email': _blankToNull(contactEmail),
        'phone': _blankToNull(phone),
        'lead_time_days': leadTimeDays,
      };

  @override
  Future<Supplier> createSupplier({
    required String name,
    String? contactEmail,
    String? phone,
    required int leadTimeDays,
  }) async =>
      Supplier.fromJson(await _api.post<Map<String, dynamic>>('/suppliers',
          data: _supplierBody(name, contactEmail, phone, leadTimeDays)));

  @override
  Future<Supplier> updateSupplier(
    String id, {
    required String name,
    String? contactEmail,
    String? phone,
    required int leadTimeDays,
  }) async =>
      Supplier.fromJson(await _api.patch<Map<String, dynamic>>(
          '/suppliers/$id',
          data: _supplierBody(name, contactEmail, phone, leadTimeDays)));

  @override
  Future<void> deleteSupplier(String id) => _api.delete('/suppliers/$id');
}
