import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class BloodPressureChart extends StatelessWidget {
  const BloodPressureChart({
    super.key,
    required this.readings,
    this.days = 7,
  });

  final List<BloodPressureReading> readings;
  final int days;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final points = readings.where((e) => !e.measuredAt.isBefore(cutoff)).toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    if (points.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'Нет измерений за $days дн.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }

    final start = points.first.measuredAt;
    final end = points.last.measuredAt.isAfter(DateTime.now())
        ? points.last.measuredAt
        : DateTime.now();
    var span = end.difference(start).inHours / 24;
    if (span < 1) span = 1;

    final sysSpots = <FlSpot>[];
    final diaSpots = <FlSpot>[];
    for (final reading in points) {
      final x = reading.measuredAt.difference(start).inMinutes / 1440.0;
      sysSpots.add(FlSpot(x, reading.systolic.toDouble()));
      diaSpots.add(FlSpot(x, reading.diastolic.toDouble()));
    }

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: span,
          minY: 50,
          maxY: 180,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 20,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.black.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 140,
                color: const Color(0xFFE57373).withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [6, 4],
              ),
              HorizontalLine(
                y: 90,
                color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
                strokeWidth: 1,
                dashArray: [6, 4],
              ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 20,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: span > 20 ? 7 : (span > 3 ? 1 : 0.5),
                getTitlesWidget: (value, meta) {
                  final dt = start.add(Duration(minutes: (value * 1440).round()));
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('d.MM').format(dt),
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: sysSpots,
              isCurved: true,
              color: const Color(0xFFE53935),
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
            LineChartBarData(
              spots: diaSpots,
              isCurved: true,
              color: AppColors.protein,
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
