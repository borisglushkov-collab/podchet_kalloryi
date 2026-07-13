import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Линейный график веса (дизайн A — мягкая зелёная линия).
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.entries,
    required this.startWeight,
    required this.targetWeight,
    this.compact = false,
  });

  final List<WeightEntry> entries;
  final double startWeight;
  final double targetWeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return SizedBox(
        height: compact ? 140 : 220,
        child: Center(
          child: Text(
            'Нет записей для графика',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }

    final sorted = List<WeightEntry>.from(entries)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final now = DateTime.now();
    final DateTime chartStart;
    final DateTime chartEnd;

    if (sorted.length == 1) {
      // Одна точка — растянуть ось времени, как в FatSecret
      chartStart = sorted.first.recordedAt.subtract(const Duration(days: 45));
      chartEnd = now.isAfter(sorted.first.recordedAt)
          ? now.add(const Duration(days: 7))
          : sorted.first.recordedAt.add(const Duration(days: 45));
    } else {
      chartStart = sorted.first.recordedAt;
      chartEnd = sorted.last.recordedAt.isAfter(now) ? sorted.last.recordedAt : now;
    }

    var dateSpan = chartEnd.difference(chartStart).inDays;
    if (dateSpan < 14) dateSpan = 14;

    final weights = sorted.map((e) => e.weightKg).toList();
    var minY = [startWeight, targetWeight, ...weights].reduce((a, b) => a < b ? a : b);
    var maxY = [startWeight, targetWeight, ...weights].reduce((a, b) => a > b ? a : b);
    final padding = ((maxY - minY) * 0.12).clamp(1.0, 5.0);
    minY -= padding;
    maxY += padding;

    final spots = sorted.map((entry) {
      final days = entry.recordedAt.difference(chartStart).inDays.toDouble();
      return FlSpot(days.clamp(0, dateSpan.toDouble()), entry.weightKg);
    }).toList();

    // Метки месяцев на оси X
    final monthLabels = <double, String>{};
    var cursor = DateTime(chartStart.year, chartStart.month, 1);
    while (!cursor.isAfter(chartEnd)) {
      final days = cursor.difference(chartStart).inDays.toDouble();
      if (days >= 0 && days <= dateSpan) {
        monthLabels[days] = DateFormat('MMM yyyy', 'ru').format(cursor);
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: compact ? 160 : 240,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, compact ? 8 : 16, 12, 8),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: dateSpan.toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 10),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.black.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: dateSpan > 90 ? 30 : (dateSpan > 30 ? 14 : 7),
                      getTitlesWidget: (value, meta) {
                        String? label = monthLabels[value];
                        if (label == null) {
                          for (final entry in monthLabels.entries) {
                            if ((entry.key - value).abs() < 4) {
                              label = entry.value;
                              break;
                            }
                          }
                        }
                        if (label == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: startWeight,
                      color: const Color(0xFFE25555).withValues(alpha: 0.55),
                      strokeWidth: 1.2,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: !compact,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 4, bottom: 4),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE25555),
                        ),
                        labelResolver: (_) => startWeight.toStringAsFixed(0),
                      ),
                    ),
                    HorizontalLine(
                      y: targetWeight,
                      color: AppColors.primary.withValues(alpha: 0.55),
                      strokeWidth: 1.2,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: !compact,
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.only(right: 4, top: 4),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                        labelResolver: (_) => targetWeight.toStringAsFixed(0),
                      ),
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((s) {
                      final idx = s.spotIndex.clamp(0, sorted.length - 1);
                      final entry = sorted[idx];
                      return LineTooltipItem(
                        '${entry.weightKg.toStringAsFixed(1)} кг\n'
                        '${DateFormat('d MMM', 'ru').format(entry.recordedAt)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: sorted.length > 2,
                    curveSmoothness: 0.25,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: sorted.length == 1 ? 6 : 4,
                        color: AppColors.primary,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: sorted.length >= 2,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.28),
                          AppColors.primary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (sorted.length == 1)
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 4 : 20, 0, compact ? 4 : 20, 8),
            child: Text(
              'Добавьте ещё записи веса — на графике появится линия прогресса',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
      ],
    );
  }
}
