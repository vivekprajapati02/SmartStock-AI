import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:smartstock/data/models/forecast_models.dart';
import 'package:smartstock/modules/forecasting/forecasting_controllers.dart';
import 'package:smartstock/modules/forecasting/forecasting_views.dart';
import 'package:smartstock/widgets/async_state_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Map<String, dynamic> _store() => {
      'id': 'store-1', 'org_id': 'o', 'name': 'Main Store', 'location': null,
      'created_at': '2026-10-01T00:00:00Z',
    };

Map<String, dynamic> _product() => {
      'id': 'prod-1', 'org_id': 'o', 'sku': 'SKU-1', 'name': 'Widget', 'category_id': null,
      'supplier_id': null, 'unit': 'unit', 'unit_cost': '1.00', 'unit_price': '2.00',
      'is_active': true, 'created_at': '2026-10-01T00:00:00Z',
    };

Map<String, dynamic> _series({bool withRun = true}) => {
      'product_id': 'prod-1',
      'store_id': 'store-1',
      'run': withRun
          ? (runJson('lightgbm', kind: 'forecast', selected: true, baseline: false)
            ..['params'] = {
              'kind': 'forecast',
              'backtest_metrics': {'mae': 1.0, 'rmse': 1.5, 'wape': 0.156, 'bias': 0.01, 'n_points': 90},
            })
          : null,
      'history': [
        {'day': '2026-10-18', 'quantity': 10.0},
        {'day': '2026-10-19', 'quantity': 12.0},
      ],
      'forecast': withRun
          ? [
              {'day': '2026-10-20', 'quantity': 11.5},
              {'day': '2026-10-21', 'quantity': 9.25},
            ]
          : [],
    };

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  test('comparison parses measured metrics and undefined ratios', () {
    final json = comparisonJson();
    (json['models'] as List).add({
      ...runJson('exponential_smoothing'),
      'metrics': {'mae': 0.0, 'rmse': 0.0, 'wape': null, 'bias': null, 'n_points': 5},
    });
    final c = ModelComparison.fromJson(json);
    expect(c.selectedModel, 'lightgbm');
    expect(c.models.first.metrics!.wape, 0.156);
    expect(c.models.first.isBaseline, isFalse);
    expect(c.models.last.metrics!.wape, isNull);
    expect(c.cutoffs, hasLength(3));
    expect(c.forecastVsActual.first.predicted, 690.5);
    expect(ModelComparison.fromJson(comparisonJson(empty: true)).isEmpty, isTrue);
  });

  test('formatting never invents values', () {
    expect(fmtPct(null), 'n/a');
    expect(fmtPct(0.1564), '15.6%');
    expect(fmtPct(0.031, signed: true), '+3.1%');
    expect(fmtPct(-0.031, signed: true), '-3.1%');
  });

  group('EvaluationController', () {
    test('no backtest yet is the empty state', () async {
      final h = Harness((o) async => (200, comparisonJson(empty: true)));
      final c = EvaluationController(h.forecasts);
      await c.load();
      expect(c.status.value, LoadStatus.empty);
      expect(h.adapter.requests.single.query['horizon'], 30);
    });

    test('run backtest posts horizon and shows the persisted result', () async {
      final h = Harness((o) async => (200, comparisonJson()));
      final c = EvaluationController(h.forecasts);
      c.horizon.value = 14;
      expect(await c.runBacktest(), isTrue);
      final req = h.adapter.requests.single;
      expect(req.path, '/models:backtest');
      expect(req.body, {'horizon': 14, 'folds': 3});
      expect(c.status.value, LoadStatus.data);
      expect(c.comparison.value!.models, hasLength(3));
    });

    test('insufficient history message is shown', () async {
      final h = Harness((o) async => (
            422,
            errorJson('unprocessable', 'Need at least 326 days of sales history for a 90-day backtest with 3 folds.'),
          ));
      final c = EvaluationController(h.forecasts);
      expect(await c.runBacktest(), isFalse);
      expect(c.runError.value, contains('326 days'));
    });
  });

  group('ForecastController', () {
    test('preselects the first product and store and loads its series', () async {
      final h = Harness((o) async => switch (o.path) {
            '/stores' => (200, pageJson([_store()])),
            '/products' => (200, pageJson([_product()])),
            _ => (200, _series()),
          });
      final c = ForecastController(h.forecasts, h.catalog);
      await c.init();
      expect(c.status.value, LoadStatus.data);
      expect(c.series.value!.forecast, hasLength(2));
      final req = h.adapter.requests.last;
      expect(req.path, '/forecasts/series');
      expect(req.query, {
        'product_id': 'prod-1', 'store_id': 'store-1', 'horizon': 30, 'history_days': 60,
      });
    });

    test('empty catalogue is the empty state', () async {
      final h = Harness((o) async => (200, pageJson([])));
      final c = ForecastController(h.forecasts, h.catalog);
      await c.init();
      expect(c.status.value, LoadStatus.empty);
    });

    test('generate posts the horizon then reloads the series', () async {
      final h = Harness((o) async => switch (o.path) {
            '/stores' => (200, pageJson([_store()])),
            '/products' => (200, pageJson([_product()])),
            '/forecasts:generate' => (200, {'run': runJson('lightgbm', kind: 'forecast'), 'items': [], 'total': 0, 'limit': 50, 'offset': 0}),
            _ => (200, _series()),
          });
      final c = ForecastController(h.forecasts, h.catalog);
      await c.init();
      c.horizon.value = 7;
      expect(await c.generate(), isTrue);
      final paths = h.adapter.requests.map((r) => r.path).toList();
      expect(paths.sublist(paths.length - 2), ['/forecasts:generate', '/forecasts/series']);
      expect(h.adapter.requests[paths.length - 2].body, {'horizon': 7});
    });
  });

  group('views', () {
    testWidgets('evaluation shows selection, metrics and synthetic note', (tester) async {
      final h = Harness((o) async => (200, comparisonJson()));
      h.register(role: 'manager');
      Get.put(EvaluationController(h.forecasts));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: EvaluationView())));
      await tester.pumpAndSettle();
      expect(find.text('Selected: LightGBM'), findsOneWidget);
      expect(find.textContaining('4.3% lower WAPE'), findsOneWidget);
      expect(find.text('15.6%'), findsOneWidget);
      expect(find.text('-3.1%'), findsNWidgets(3));
      expect(find.byKey(const Key('synthetic-note')), findsOneWidget);
      expect(find.byKey(const Key('run-backtest')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('fva-chart')),
        300,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.byKey(const Key('fva-chart')), findsOneWidget);
    });

    testWidgets('baseline selection is explained honestly', (tester) async {
      final h = Harness((o) async => (200, comparisonJson(selected: 'moving_average', demo: false)));
      h.register(role: 'viewer');
      Get.put(EvaluationController(h.forecasts));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: EvaluationView())));
      await tester.pumpAndSettle();
      expect(find.textContaining('LightGBM did not beat the best baseline'), findsOneWidget);
      expect(find.byKey(const Key('synthetic-note')), findsNothing);
      expect(find.byKey(const Key('run-backtest')), findsNothing);
    });

    testWidgets('forecast screen shows run info or a no-forecast message', (tester) async {
      final h = Harness((o) async => switch (o.path) {
            '/stores' => (200, pageJson([_store()])),
            '/products' => (200, pageJson([_product()])),
            _ => (200, _series(withRun: false)),
          });
      h.register(role: 'viewer');
      Get.put(ForecastController(h.forecasts, h.catalog));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: ForecastView())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-forecast')), findsOneWidget);
      expect(find.byKey(const Key('forecast-chart')), findsOneWidget);
      expect(find.byKey(const Key('generate-forecasts')), findsNothing);
    });
  });
}
