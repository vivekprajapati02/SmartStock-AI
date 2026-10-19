import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/utils/parse.dart';

class ChartLine {
  const ChartLine({
    required this.label,
    required this.color,
    required this.points,
    this.dashed = false,
  });

  final String label;
  final Color color;
  final List<(DateTime, double)> points;
  final bool dashed;
}

/// Daily line chart for one or more series sharing a date axis.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({super.key, required this.lines, this.height = 260});

  final List<ChartLine> lines;
  final double height;

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [for (final l in lines) ...l.points];
    if (all.isEmpty) return SizedBox(height: height);
    final origin = all.map((p) => _day(p.$1)).reduce((a, b) => a.isBefore(b) ? a : b);
    double x(DateTime d) => _day(d).difference(origin).inDays.toDouble();
    final maxX = all.map((p) => x(p.$1)).reduce(math.max);
    final maxY = all.map((p) => p.$2).reduce(math.max);
    final dateFormat = DateFormat.MMMd();
    final labelEvery = math.max(1.0, (maxX / 5).ceilToDouble());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            for (final l in lines)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 3, color: l.color),
                const SizedBox(width: 6),
                Text(l.label, style: Theme.of(context).textTheme.bodySmall),
              ]),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX <= 0 ? 1 : maxX,
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
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(NumberFormat.compact().format(v),
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: labelEvery,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        dateFormat.format(origin.add(Duration(days: v.round()))),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${lines[s.barIndex].label} '
                        '${dateFormat.format(origin.add(Duration(days: s.x.round())))}: '
                        '${formatQuantity(s.y)}',
                        TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final l in lines)
                  LineChartBarData(
                    spots: [for (final p in l.points) FlSpot(x(p.$1), p.$2)],
                    color: l.color,
                    barWidth: 2,
                    dashArray: l.dashed ? [6, 4] : null,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
