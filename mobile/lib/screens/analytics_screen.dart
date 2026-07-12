import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'weight_tracker_screen.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Вес'), icon: Icon(Icons.monitor_weight_outlined, size: 18)),
              ButtonSegment(value: 1, label: Text('Калории'), icon: Icon(Icons.local_fire_department_outlined, size: 18)),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? const WeightTrackerScreen(embedded: true)
              : const _CaloriesTab(),
        ),
      ],
      ),
    );
  }
}

class _CaloriesTab extends ConsumerWidget {
  const _CaloriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(selectedDateProvider);

    return FutureBuilder<List<_DayStat>>(
      future: _loadWeekStats(today),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final stats = snapshot.data!;
        if (stats.every((s) => s.kcal <= 0)) {
          return const Center(child: Text('Пока нет данных за неделю'));
        }

        final maxKcal = stats.map((s) => s.kcal).reduce((a, b) => a > b ? a : b);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Калории за 7 дней', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...stats.map((s) {
              final progress = maxKcal > 0 ? s.kcal / maxKcal : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        DateFormat('E d', 'ru').format(s.date),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child: Text(
                        s.kcal.toStringAsFixed(0),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<List<_DayStat>> _loadWeekStats(DateTime anchor) async {
    final stats = <_DayStat>[];
    for (var i = 6; i >= 0; i--) {
      final day = anchor.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final totals = await AppDatabase.getDailyTotals(dateStr);
      stats.add(_DayStat(date: day, kcal: totals.calories));
    }
    return stats;
  }
}

class _DayStat {
  final DateTime date;
  final double kcal;

  const _DayStat({required this.date, required this.kcal});
}
