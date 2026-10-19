import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/cache_store.dart';
import '../models/fetched.dart';
import '../models/inventory_models.dart';
import '../models/page_result.dart';

class InventoryQuery {
  const InventoryQuery({this.storeId, this.lowStockOnly = false, this.search});

  final String? storeId;
  final bool lowStockOnly;
  final String? search;

  /// Stable key for the offline cache.
  String get cacheKey =>
      'inventory:${storeId ?? '*'}:${lowStockOnly ? 1 : 0}:${search ?? ''}';
}

abstract class InventoryRepository {
  /// The first page falls back to the last cached copy when offline.
  Future<Fetched<PageResult<InventoryItem>>> listInventory(
    InventoryQuery query, {
    int limit = 50,
    int offset = 0,
  });
  Future<InventoryItem> getInventory(String id);
  Future<InventoryItem> updateSettings(
    String id, {
    String? reorderPoint,
    String? safetyStock,
    int? leadTimeDays,
  });

  Future<PageResult<Movement>> listMovements({
    String? productId,
    String? storeId,
    int limit = 50,
    int offset = 0,
  });
  Future<Movement> recordMovement(MovementInput input);
}

class ApiInventoryRepository implements InventoryRepository {
  ApiInventoryRepository(this._api, this._cache);

  final ApiClient _api;
  final CacheStore _cache;

  @override
  Future<Fetched<PageResult<InventoryItem>>> listInventory(
    InventoryQuery query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final cacheable = offset == 0;
    try {
      final json = await _api.get<Map<String, dynamic>>('/inventory', query: {
        'limit': limit,
        'offset': offset,
        'store_id': query.storeId,
        'low_stock': query.lowStockOnly ? true : null,
        'search': query.search?.trim(),
      });
      if (cacheable) await _cache.write(query.cacheKey, json);
      return Fetched(PageResult.fromJson(json, InventoryItem.fromJson));
    } on ApiException catch (e) {
      if (!e.isOffline || !cacheable) rethrow;
      final cached = await _cache.read(query.cacheKey);
      if (cached == null || cached.data is! Map<String, dynamic>) rethrow;
      return Fetched(
        PageResult.fromJson(
          cached.data! as Map<String, dynamic>,
          InventoryItem.fromJson,
        ),
        cachedAt: cached.savedAt,
      );
    }
  }

  @override
  Future<InventoryItem> getInventory(String id) async => InventoryItem.fromJson(
      await _api.get<Map<String, dynamic>>('/inventory/$id'));

  @override
  Future<InventoryItem> updateSettings(
    String id, {
    String? reorderPoint,
    String? safetyStock,
    int? leadTimeDays,
  }) async =>
      InventoryItem.fromJson(
          await _api.patch<Map<String, dynamic>>('/inventory/$id', data: {
        'reorder_point': ?reorderPoint,
        'safety_stock': ?safetyStock,
        'lead_time_days': ?leadTimeDays,
      }));

  @override
  Future<PageResult<Movement>> listMovements({
    String? productId,
    String? storeId,
    int limit = 50,
    int offset = 0,
  }) async {
    final json = await _api.get<Map<String, dynamic>>('/movements', query: {
      'limit': limit,
      'offset': offset,
      'product_id': productId,
      'store_id': storeId,
    });
    return PageResult.fromJson(json, Movement.fromJson);
  }

  @override
  Future<Movement> recordMovement(MovementInput input) async =>
      Movement.fromJson(await _api.post<Map<String, dynamic>>('/movements',
          data: input.toJson()));
}
