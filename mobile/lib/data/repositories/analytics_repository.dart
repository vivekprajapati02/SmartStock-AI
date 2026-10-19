import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/cache_store.dart';
import '../models/dashboard_models.dart';
import '../models/fetched.dart';

abstract class AnalyticsRepository {
  Future<Fetched<Dashboard>> getDashboard({int trendDays = 30});
}

class ApiAnalyticsRepository implements AnalyticsRepository {
  ApiAnalyticsRepository(this._api, this._cache);

  final ApiClient _api;
  final CacheStore _cache;

  @override
  Future<Fetched<Dashboard>> getDashboard({int trendDays = 30}) async {
    final key = 'dashboard:$trendDays';
    try {
      final json = await _api.get<Map<String, dynamic>>(
        '/analytics/dashboard',
        query: {'trend_days': trendDays},
      );
      await _cache.write(key, json);
      return Fetched(Dashboard.fromJson(json));
    } on ApiException catch (e) {
      if (!e.isOffline) rethrow;
      final cached = await _cache.read(key);
      if (cached == null || cached.data is! Map<String, dynamic>) rethrow;
      return Fetched(
        Dashboard.fromJson(cached.data! as Map<String, dynamic>),
        cachedAt: cached.savedAt,
      );
    }
  }
}
