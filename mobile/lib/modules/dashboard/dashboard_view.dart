import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/parse.dart';
import '../../data/models/dashboard_models.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/common.dart';
import 'dashboard_controller.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DashboardController>();
    return Obx(() => AsyncStateView(
          status: c.status.value,
          errorMessage: c.error.value,
          onRetry: c.load,
          cachedAt: c.cachedAt.value,
          builder: (context) => RefreshIndicator(
            onRefresh: c.load,
            child: _DashboardBody(
              dashboard: c.dashboard.value!,
              trendDays: c.trendDays.value,
              onTrendDays: c.setTrendDays,
            ),
          ),
        ));
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.dashboard,
    required this.trendDays,
    required this.onTrendDays,
  });

  final Dashboard dashboard;
  final int trendDays;
  final ValueChanged<int> onTrendDays;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(decimalDigits: 2);
    final number = NumberFormat.decimalPattern();
    final d = dashboard;
    final tiles = [
      KpiCard(
        key: const Key('kpi-inventory-value'),
        label: 'Inventory value',
        value: currency.format(d.inventoryValue),
        icon: Icons.payments_outlined,
      ),
      KpiCard(
        key: const Key('kpi-sku-count'),
        label: 'SKUs',
        value: number.format(d.skuCount),
        icon: Icons.qr_code_2,
      ),
      KpiCard(
        key: const Key('kpi-store-count'),
        label: 'Stores',
        value: number.format(d.storeCount),
        icon: Icons.storefront_outlined,
      ),
      KpiCard(
        key: const Key('kpi-low-stock'),
        label: 'Low stock',
        value: number.format(d.lowStockCount),
        icon: Icons.trending_down,
        color: AppTheme.lowStock,
      ),
      KpiCard(
        key: const Key('kpi-stockout'),
        label: 'Stockouts',
        value: number.format(d.stockoutCount),
        icon: Icons.remove_shopping_cart_outlined,
        color: AppTheme.stockout,
      ),
      KpiCard(
        key: const Key('kpi-pending-orders'),
        label: 'Pending orders',
        value: number.format(d.pendingOrderCount),
        icon: Icons.local_shipping_outlined,
      ),
      KpiCard(
        key: const Key('kpi-open-alerts'),
        label: 'Open alerts',
        value: number.format(d.openAlertCount),
        icon: Icons.notifications_active_outlined,
        color: d.openAlertCount > 0 ? AppTheme.stockout : null,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 3
          : constraints.maxWidth >= 560
              ? 2
              : 1;
      const spacing = 12.0;
      final tileWidth =
          (constraints.maxWidth - 32 - spacing * (columns - 1)) / columns;
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (d.isDemo)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  key: Key('demo-badge'),
                  avatar: Icon(Icons.science_outlined, size: 18),
                  label: Text('Synthetic demo data'),
                ),
              ),
            ),
          if (d.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Card(
                key: Key('dashboard-empty-hint'),
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No catalogue data yet'),
                  subtitle: Text(
                      'Add stores and products in the Catalogue tab. Metrics are '
                      'computed from your stored data, so they start at zero.'),
                ),
              ),
            ),
          Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final t in tiles) SizedBox(width: tileWidth, child: t),
            ],
          ),
          const SizedBox(height: 16),
          _TrendCard(
            points: d.demandTrend,
            trendDays: trendDays,
            onTrendDays: onTrendDays,
          ),
        ],
      );
    });
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.points,
    required this.trendDays,
    required this.onTrendDays,
  });

  final List<DemandPoint> points;
  final int trendDays;
  final ValueChanged<int> onTrendDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = points.fold<double>(0, (sum, p) => sum + p.quantity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily demand', style: theme.textTheme.titleMedium),
                    Text(
                      'Units sold, last $trendDays days - total ${formatQuantity(total)}',
                      key: const Key('trend-total'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                SegmentedButton<int>(
                  segments: [
                    for (final days in DashboardController.trendOptions)
                      ButtonSegment(value: days, label: Text('${days}d')),
                  ],
                  selected: {trendDays},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => onTrendDays(s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              // The API returns one zero-filled point per day, so "no data"
              // means no recorded sales rather than an empty list.
              child: total == 0
                  ? const StateMessage(
                      key: Key('trend-empty'),
                      icon: Icons.show_chart,
                      title: 'No sales recorded in this period',
                      message: 'Import sales history to see demand trends.',
                    )
                  : _TrendChart(points: points),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<DemandPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat.MMMd();
    final maxY = points.map((p) => p.quantity).reduce(math.max);
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].quantity),
    ];
    final labelEvery = math.max(1, (points.length / 6).ceil());
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.1,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(NumberFormat.compact().format(value),
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length || i % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(dateFormat.format(points[i].date),
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${dateFormat.format(points[s.x.toInt()].date)}\n'
                  '${formatQuantity(s.y)} units',
                  TextStyle(color: scheme.onInverseSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: scheme.primary,
            barWidth: 2,
            dotData: FlDotData(show: points.length <= 31),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
