import '../../core/utils/parse.dart';

const forecastHorizons = [7, 14, 30, 90];

/// Measured backtest accuracy. WAPE and bias are null when actual demand
/// summed to zero (undefined), never filled in.
class ForecastMetrics {
  const ForecastMetrics({
    required this.mae,
    required this.rmse,
    this.wape,
    this.bias,
    required this.nPoints,
  });

  factory ForecastMetrics.fromJson(Map<String, dynamic> json) => ForecastMetrics(
        mae: parseDouble(json['mae']),
        rmse: parseDouble(json['rmse']),
        wape: parseDoubleOrNull(json['wape']),
        bias: parseDoubleOrNull(json['bias']),
        nPoints: parseInt(json['n_points']),
      );

  final double mae;
  final double rmse;
  final double? wape;
  final double? bias;
  final int nPoints;
}

String modelLabel(String name) => switch (name) {
      'seasonal_naive' => 'Seasonal naive (7-day)',
      'moving_average' => 'Moving average (28-day)',
      'exponential_smoothing' => 'Exponential smoothing',
      'lightgbm' => 'LightGBM',
      _ => name,
    };

class ModelRun {
  const ModelRun({
    required this.id,
    required this.modelName,
    required this.kind,
    required this.horizon,
    required this.selected,
    required this.isBaseline,
    this.metrics,
    this.params = const {},
    this.datasetStart,
    this.datasetEnd,
    required this.trainedAt,
  });

  factory ModelRun.fromJson(Map<String, dynamic> json) => ModelRun(
        id: json['id'] as String,
        modelName: json['model_name'] as String,
        kind: json['kind'] as String? ?? 'backtest',
        horizon: parseInt(json['horizon']),
        selected: json['selected'] as bool? ?? false,
        isBaseline: json['is_baseline'] as bool? ?? true,
        metrics: json['metrics'] is Map<String, dynamic>
            ? ForecastMetrics.fromJson(json['metrics'] as Map<String, dynamic>)
            : null,
        params: (json['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        datasetStart: json['dataset_start'] == null ? null : parseDateTime(json['dataset_start']),
        datasetEnd: json['dataset_end'] == null ? null : parseDateTime(json['dataset_end']),
        trainedAt: parseDateTime(json['trained_at']),
      );

  final String id;
  final String modelName;
  final String kind;
  final int horizon;
  final bool selected;
  final bool isBaseline;
  final ForecastMetrics? metrics;
  final Map<String, dynamic> params;
  final DateTime? datasetStart;
  final DateTime? datasetEnd;
  final DateTime trainedAt;

  String get label => modelLabel(modelName);

  /// For forecast runs: the backtest metrics of the model that was used.
  ForecastMetrics? get backtestMetrics {
    final raw = params['backtest_metrics'];
    return raw is Map<String, dynamic> ? ForecastMetrics.fromJson(raw) : null;
  }
}

class ActualVsPredicted {
  const ActualVsPredicted({required this.day, required this.actual, required this.predicted});

  factory ActualVsPredicted.fromJson(Map<String, dynamic> json) => ActualVsPredicted(
        day: parseDateTime(json['day']),
        actual: parseDouble(json['actual']),
        predicted: parseDouble(json['predicted']),
      );

  final DateTime day;
  final double actual;
  final double predicted;
}

class ModelComparison {
  const ModelComparison({
    required this.horizon,
    this.runAt,
    this.datasetStart,
    this.datasetEnd,
    this.folds,
    this.cutoffs = const [],
    required this.nSeries,
    required this.models,
    this.selectedModel,
    this.bestBaseline,
    this.wapeImprovement,
    this.forecastVsActual = const [],
    required this.isDemo,
  });

  factory ModelComparison.fromJson(Map<String, dynamic> json) => ModelComparison(
        horizon: parseInt(json['horizon']),
        runAt: json['run_at'] == null ? null : parseDateTime(json['run_at']),
        datasetStart: json['dataset_start'] == null ? null : parseDateTime(json['dataset_start']),
        datasetEnd: json['dataset_end'] == null ? null : parseDateTime(json['dataset_end']),
        folds: json['folds'] as int?,
        cutoffs: (json['cutoffs'] as List? ?? const []).map(parseDateTime).toList(),
        nSeries: parseInt(json['n_series']),
        models: (json['models'] as List? ?? const [])
            .map((e) => ModelRun.fromJson(e as Map<String, dynamic>))
            .toList(),
        selectedModel: json['selected_model'] as String?,
        bestBaseline: json['best_baseline'] as String?,
        wapeImprovement: parseDoubleOrNull(json['wape_improvement_vs_baseline']),
        forecastVsActual: (json['forecast_vs_actual'] as List? ?? const [])
            .map((e) => ActualVsPredicted.fromJson(e as Map<String, dynamic>))
            .toList(),
        isDemo: json['is_demo'] as bool? ?? false,
      );

  final int horizon;
  final DateTime? runAt;
  final DateTime? datasetStart;
  final DateTime? datasetEnd;
  final int? folds;
  final List<DateTime> cutoffs;
  final int nSeries;
  final List<ModelRun> models;
  final String? selectedModel;
  final String? bestBaseline;
  final double? wapeImprovement;
  final List<ActualVsPredicted> forecastVsActual;
  final bool isDemo;

  bool get isEmpty => models.isEmpty;
}

class DayQuantity {
  const DayQuantity(this.day, this.quantity);

  factory DayQuantity.fromJson(Map<String, dynamic> json) =>
      DayQuantity(parseDateTime(json['day']), parseDouble(json['quantity']));

  final DateTime day;
  final double quantity;
}

class ForecastSeries {
  const ForecastSeries({this.run, required this.history, required this.forecast});

  factory ForecastSeries.fromJson(Map<String, dynamic> json) => ForecastSeries(
        run: json['run'] is Map<String, dynamic>
            ? ModelRun.fromJson(json['run'] as Map<String, dynamic>)
            : null,
        history: (json['history'] as List? ?? const [])
            .map((e) => DayQuantity.fromJson(e as Map<String, dynamic>))
            .toList(),
        forecast: (json['forecast'] as List? ?? const [])
            .map((e) => DayQuantity.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final ModelRun? run;
  final List<DayQuantity> history;
  final List<DayQuantity> forecast;
}
