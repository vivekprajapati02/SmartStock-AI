import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/forecast_models.dart';

abstract class ForecastRepository {
  Future<ModelComparison> comparison(int horizon);

  /// Runs a chronological backtest of every model; results are persisted.
  Future<ModelComparison> runBacktest(int horizon, {int folds = 3});

  /// Forecasts every SKU/store with the model selected for [horizon].
  Future<ModelRun?> generate(int horizon);

  Future<ForecastSeries> series({
    required String productId,
    required String storeId,
    required int horizon,
    int historyDays = 60,
  });
}

class ApiForecastRepository implements ForecastRepository {
  ApiForecastRepository(this._api);

  final ApiClient _api;

  // Model training runs inside the request; allow more than the default.
  static final _slow = Options(receiveTimeout: const Duration(minutes: 3));

  @override
  Future<ModelComparison> comparison(int horizon) async => ModelComparison.fromJson(
      await _api.get<Map<String, dynamic>>('/models/comparison',
          query: {'horizon': horizon}));

  @override
  Future<ModelComparison> runBacktest(int horizon, {int folds = 3}) async =>
      ModelComparison.fromJson(await _api.post<Map<String, dynamic>>(
        '/models:backtest',
        data: {'horizon': horizon, 'folds': folds},
        options: _slow,
      ));

  @override
  Future<ModelRun?> generate(int horizon) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/forecasts:generate',
      data: {'horizon': horizon},
      options: _slow,
    );
    final run = json['run'];
    return run is Map<String, dynamic> ? ModelRun.fromJson(run) : null;
  }

  @override
  Future<ForecastSeries> series({
    required String productId,
    required String storeId,
    required int horizon,
    int historyDays = 60,
  }) async =>
      ForecastSeries.fromJson(await _api.get<Map<String, dynamic>>(
        '/forecasts/series',
        query: {
          'product_id': productId,
          'store_id': storeId,
          'horizon': horizon,
          'history_days': historyDays,
        },
      ));
}
