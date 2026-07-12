import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Линейный график веса в стиле FatSecret: линия, заливка, целевые линии.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.entries,
    required this.startWeight,
    required this.targetWeight,
  });

  final List<WeightEntry> entries;
  final double startWeight;
  final double targetWeight;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Нет записей для графика')),
      );
    }

    final sorted = List<WeightEntry>.from(entries)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final minDate = sorted.first.recordedAt;
    final maxDate = sorted.last.recordedAt;
    final dateSpan = maxDate.difference(minDate).inDays.clamp(1, 3650);

    final weights = sorted.map((e) => e.weightKg).toList();
    var minY = [startWeight, targetWeight, ...weights].reduce((a, b) => a < b ? a : b);
    var maxY = [startWeight, targetWeight, ...weights].reduce((a, b) => a > b ? a : b);
    final padding = ((maxY - minY) * 0.15).clamp(1.0, 5.0);
    minY -= padding;
    maxY += padding;

    final spots = sorted.asMap().entries.map((e) {
      final days = e.value.recordedAt.difference(minDate).inDays.toDouble();
      return FlSpot(days, e.value.weightKg);
    }).toList();

    final monthLabels = <double, String>{};
    for (final entry in sorted) {
      final days = entry.recordedAt.difference(minDate).inDays.toDouble();
      final label = DateFormat('MMM yyyy', 'ru').format(entry.recordedAt);
      if (!monthLabels.containsValue(label)) {
        monthLabels[days] = label;
      }
    }

    return SizedBox(
      height: 240,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
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
                  interval: dateSpan > 60 ? 30 : (dateSpan > 14 ? 7 : 1),
                  getTitlesWidget: (value, meta) {
                    final label = monthLabels[value];
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
                  color: const Color(0xFFE57373),
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE57373),
                    ),
                    labelResolver: (_) => startWeight.toStringAsFixed(0),
                  ),
                ),
                HorizontalLine(
                  y: targetWeight,
                  color: AppColors.water,
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.bottomRight,
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.water,
                    ),
                    labelResolver: (_) => targetWeight.toStringAsFixed(0),
                  ),
                ),
              ],
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
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
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.streak,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 4,
                    color: AppColors.streak,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.streak.withValues(alpha: 0.35),
                      AppColors.streak.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
