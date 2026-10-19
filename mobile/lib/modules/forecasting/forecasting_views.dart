import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/forecast_models.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/common.dart';
import '../../widgets/time_series_chart.dart';
import '../movements/movements_view.dart' show ProductPicker;
import 'forecasting_controllers.dart';

String fmtNum(double v) => NumberFormat('#,##0.00').format(v);

String fmtPct(double? v, {bool signed = false}) {
  if (v == null) return 'n/a';
  final text = '${(v * 100).toStringAsFixed(1)}%';
  return signed && v > 0 ? '+$text' : text;
}

class HorizonSelector extends StatelessWidget {
  const HorizonSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: [
        for (final h in forecastHorizons) ButtonSegment(value: h, label: Text('${h}d')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _SyntheticNote extends StatelessWidget {
  const _SyntheticNote();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('synthetic-note'),
      child: ListTile(
        leading: Icon(Icons.science_outlined),
        title: Text('Measured on synthetic demo data'),
        subtitle: Text('These metrics describe accuracy on generated sales, '
            'not on real business data.'),
      ),
    );
  }
}

// ---------------------------------------------------------------- evaluation

class EvaluationView extends StatelessWidget {
  const EvaluationView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<EvaluationController>();
    return Obx(() {
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HorizonSelector(value: c.horizon.value, onChanged: c.setHorizon),
            RoleGate(
              child: FilledButton.icon(
                key: const Key('run-backtest'),
                onPressed: c.running.value
                    ? null
                    : () async {
                        if (await c.runBacktest()) showSnack('Backtest complete');
                      },
                icon: c.running.value
                    ? const SizedBox.square(
                        dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(c.running.value ? 'Running backtest...' : 'Run backtest'),
              ),
            ),
            if (c.runError.value != null)
              Text(c.runError.value!,
                  key: const Key('backtest-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      );
      return Column(
        children: [
          header,
          Expanded(
            child: AsyncStateView(
              status: c.status.value,
              errorMessage: c.error.value,
              onRetry: c.load,
              emptyTitle: 'No backtest for ${c.horizon.value} days yet',
              emptyMessage: 'A backtest trains each model on past sales and scores it '
                  'on the following days it never saw. Results appear here.',
              builder: (context) => _ComparisonBody(comparison: c.comparison.value!),
            ),
          ),
        ],
      );
    });
  }
}

class _ComparisonBody extends StatelessWidget {
  const _ComparisonBody({required this.comparison});

  final ModelComparison comparison;

  @override
  Widget build(BuildContext context) {
    final cmp = comparison;
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd();
    final selected = cmp.selectedModel;
    final improvement = cmp.wapeImprovement;
    final verdict = selected == null
        ? 'No model selected.'
        : selected == 'lightgbm'
            ? 'LightGBM beat the best baseline (${modelLabel(cmp.bestBaseline ?? '')}) '
                'with ${fmtPct(improvement)} lower WAPE, so it is used for forecasts.'
            : '${modelLabel(selected)} is used for forecasts: LightGBM did not beat the '
                'best baseline on this horizon.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (cmp.isDemo) const _SyntheticNote(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected: ${selected == null ? '-' : modelLabel(selected)}',
                    key: const Key('selected-model'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(verdict, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  [
                    if (cmp.runAt != null) 'Run ${date.add_jm().format(cmp.runAt!.toLocal())}',
                    if (cmp.datasetStart != null && cmp.datasetEnd != null)
                      'data ${date.format(cmp.datasetStart!)} - ${date.format(cmp.datasetEnd!)}',
                    '${cmp.nSeries} SKU/store series',
                    '${cmp.folds ?? 0} folds x ${cmp.horizon} days',
                  ].join(' - '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('metrics-table'),
              columns: const [
                DataColumn(label: Text('Model')),
                DataColumn(label: Text('MAE'), numeric: true),
                DataColumn(label: Text('RMSE'), numeric: true),
                DataColumn(label: Text('WAPE'), numeric: true),
                DataColumn(label: Text('Bias'), numeric: true),
                DataColumn(label: Text('Points'), numeric: true),
              ],
              rows: [
                for (final m in cmp.models)
                  DataRow(
                    selected: m.selected,
                    cells: [
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(m.label),
                        const SizedBox(width: 8),
                        if (m.selected)
                          const StatusChip(label: 'Selected', color: AppTheme.healthy)
                        else if (!m.isBaseline)
                          const StatusChip(label: 'ML', color: Colors.indigo),
                      ])),
                      DataCell(Text(m.metrics == null ? 'n/a' : fmtNum(m.metrics!.mae))),
                      DataCell(Text(m.metrics == null ? 'n/a' : fmtNum(m.metrics!.rmse))),
                      DataCell(Text(fmtPct(m.metrics?.wape))),
                      DataCell(Text(fmtPct(m.metrics?.bias, signed: true))),
                      DataCell(Text('${m.metrics?.nPoints ?? 0}')),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'MAE/RMSE in units per SKU-store-day. WAPE = total absolute error / total '
            'actual demand. Bias > 0 means over-forecasting.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (cmp.forecastVsActual.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Forecast vs actual (last backtest fold, all SKUs)',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TimeSeriesChart(
                    key: const Key('fva-chart'),
                    lines: [
                      ChartLine(
                        label: 'Actual',
                        color: theme.colorScheme.primary,
                        points: [for (final p in cmp.forecastVsActual) (p.day, p.actual)],
                      ),
                      ChartLine(
                        label: 'Predicted',
                        color: AppTheme.lowStock,
                        dashed: true,
                        points: [for (final p in cmp.forecastVsActual) (p.day, p.predicted)],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- forecasts

class ForecastView extends StatelessWidget {
  const ForecastView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ForecastController>();
    return Obx(() => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HorizonSelector(value: c.horizon.value, onChanged: c.setHorizon),
                SizedBox(
                  width: 280,
                  child: ProductPicker(
                    key: ValueKey('forecast-product-${c.product.value?.id}'),
                    search: c.searchProducts,
                    onSelected: c.selectProduct,
                    initialText: c.product.value == null
                        ? null
                        : '${c.product.value!.sku} ${c.product.value!.name}',
                  ),
                ),
                DropdownButton<String>(
                  value: c.storeId.value,
                  hint: const Text('Store'),
                  items: [
                    for (final s in c.stores) DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: c.selectStore,
                ),
                RoleGate(
                  child: OutlinedButton.icon(
                    key: const Key('generate-forecasts'),
                    onPressed: c.generating.value
                        ? null
                        : () async {
                            if (await c.generate()) {
                              showSnack('Forecasts generated for every SKU/store');
                            }
                          },
                    icon: c.generating.value
                        ? const SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_graph),
                    label: Text(c.generating.value
                        ? 'Generating...'
                        : 'Generate ${c.horizon.value}-day forecasts'),
                  ),
                ),
              ],
            ),
            if (c.generateError.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.generateError.value!,
                    key: const Key('generate-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 420,
              child: AsyncStateView(
                status: c.status.value,
                errorMessage: c.error.value,
                onRetry: c.init,
                emptyTitle: 'Nothing to forecast yet',
                emptyMessage: 'Add products and stores, then import sales history.',
                builder: (context) => _SeriesCard(series: c.series.value!, horizon: c.horizon.value),
              ),
            ),
          ],
        ));
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.horizon});

  final ForecastSeries series;
  final int horizon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = series.run;
    final metrics = run?.backtestMetrics;
    final total = series.forecast.fold<double>(0, (s, p) => s + p.quantity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (run == null)
              Text('No $horizon-day forecast has been generated yet.',
                  key: const Key('no-forecast'), style: theme.textTheme.titleSmall)
            else ...[
              Text(
                '${run.label} - generated '
                '${DateFormat.yMMMd().add_jm().format(run.trainedAt.toLocal())}',
                key: const Key('forecast-run'),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                'Next $horizon days: ${fmtNum(total)} units forecast'
                '${metrics == null ? '' : ' - backtest WAPE ${fmtPct(metrics.wape)}'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            TimeSeriesChart(
                key: const Key('forecast-chart'),
                height: 240,
                lines: [
                  ChartLine(
                    label: 'Actual sales',
                    color: theme.colorScheme.primary,
                    points: [for (final p in series.history) (p.day, p.quantity)],
                  ),
                  if (series.forecast.isNotEmpty)
                    ChartLine(
                      label: 'Forecast',
                      color: AppTheme.lowStock,
                      dashed: true,
                      points: [for (final p in series.forecast) (p.day, p.quantity)],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
