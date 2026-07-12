import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/wellness_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/wellness_widgets.dart';
import 'weight_tracker_screen.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  /// 0 = Калории (дизайн A), 1 = Вес
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
                ButtonSegment(
                  value: 0,
                  label: Text('Калории'),
                  icon: Icon(Icons.local_fire_department_outlined, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Вес'),
                  icon: Icon(Icons.monitor_weight_outlined, size: 18),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? const _CaloriesTab()
                : const WeightTrackerScreen(embedded: true),
          ),
        ],
      ),
    );
  }
}

enum _AnalyticsPeriod { week, month }

class _CaloriesTab extends ConsumerStatefulWidget {
  const _CaloriesTab();

  @override
  ConsumerState<_CaloriesTab> createState() => _CaloriesTabState();
}

class _CaloriesTabState extends ConsumerState<_CaloriesTab> {
  _AnalyticsPeriod _period = _AnalyticsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(selectedDateProvider);
    final targetsAsync = ref.watch(dailyTargetsProvider);
    final dayCount = _period == _AnalyticsPeriod.week ? 7 : 30;

    return targetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (targets) {
        return FutureBuilder<_AnalyticsData>(
          future: _loadStats(today, dayCount, targets),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            if (!data.hasAnyLogs) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Пока нет данных.\nДобавьте приёмы пищи в дневник.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PeriodToggle(
                        period: _period,
                        onChanged: (p) => setState(() => _period = p),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<int>(
                      future: WellnessStorage.getStreak(),
                      builder: (context, snapshot) {
                        final streak = snapshot.data ?? 0;
                        if (streak <= 0) return const SizedBox.shrink();
                        return StreakBadge(days: streak);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AverageCard(data: data),
                const SizedBox(height: 12),
                _WeekBarsCard(data: data),
                const SizedBox(height: 12),
                _MacroRingsCard(data: data),
                const SizedBox(height: 12),
                _InsightsCard(data: data),
              ],
            );
          },
        );
      },
    );
  }

  Future<_AnalyticsData> _loadStats(
    DateTime anchor,
    int dayCount,
    Macros? targets,
  ) async {
    final days = <_DayStat>[];
    for (var i = dayCount - 1; i >= 0; i--) {
      final day = DateTime(anchor.year, anchor.month, anchor.day)
          .subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final totals = await AppDatabase.getDailyTotals(dateStr);
      final hasLog = totals.calories > 0 ||
          (await AppDatabase.getEntriesForDate(dateStr)).isNotEmpty;
      days.add(_DayStat(date: day, macros: totals, hasLog: hasLog));
    }

    final logged = days.where((d) => d.hasLog).toList();
    final targetKcal = targets?.calories ?? 0;
    final targetProtein = targets?.protein ?? 0;
    final targetFat = targets?.fat ?? 0;
    final targetCarbs = targets?.carbs ?? 0;

    double avgKcal = 0;
    double avgProtein = 0;
    double avgFat = 0;
    double avgCarbs = 0;
    if (logged.isNotEmpty) {
      for (final d in logged) {
        avgKcal += d.macros.calories;
        avgProtein += d.macros.protein;
        avgFat += d.macros.fat;
        avgCarbs += d.macros.carbs;
      }
      avgKcal /= logged.length;
      avgProtein /= logged.length;
      avgFat /= logged.length;
      avgCarbs /= logged.length;
    }

    var withinGoal = 0;
    _DayStat? highest;
    for (final d in logged) {
      if (targetKcal > 0) {
        final ratio = d.macros.calories / targetKcal;
        if (ratio >= 0.85 && ratio <= 1.1) withinGoal++;
      }
      if (highest == null || d.macros.calories > highest.macros.calories) {
        highest = d;
      }
    }

    return _AnalyticsData(
      days: days,
      targets: targets ?? const Macros(),
      avgKcal: avgKcal,
      avgProtein: avgProtein,
      avgFat: avgFat,
      avgCarbs: avgCarbs,
      loggedDays: logged.length,
      withinGoalDays: withinGoal,
      highestDay: highest,
      targetKcal: targetKcal,
      targetProtein: targetProtein,
      targetFat: targetFat,
      targetCarbs: targetCarbs,
    );
  }
}

class _AnalyticsData {
  final List<_DayStat> days;
  final Macros targets;
  final double avgKcal;
  final double avgProtein;
  final double avgFat;
  final double avgCarbs;
  final int loggedDays;
  final int withinGoalDays;
  final _DayStat? highestDay;
  final double targetKcal;
  final double targetProtein;
  final double targetFat;
  final double targetCarbs;

  const _AnalyticsData({
    required this.days,
    required this.targets,
    required this.avgKcal,
    required this.avgProtein,
    required this.avgFat,
    required this.avgCarbs,
    required this.loggedDays,
    required this.withinGoalDays,
    required this.highestDay,
    required this.targetKcal,
    required this.targetProtein,
    required this.targetFat,
    required this.targetCarbs,
  });

  bool get hasAnyLogs => loggedDays > 0;

  double get vsGoalPercent {
    if (targetKcal <= 0 || avgKcal <= 0) return 0;
    return ((avgKcal - targetKcal) / targetKcal) * 100;
  }

  double get proteinPct =>
      targetProtein > 0 ? (avgProtein / targetProtein).clamp(0.0, 1.5) : 0;
  double get fatPct =>
      targetFat > 0 ? (avgFat / targetFat).clamp(0.0, 1.5) : 0;
  double get carbsPct =>
      targetCarbs > 0 ? (avgCarbs / targetCarbs).clamp(0.0, 1.5) : 0;
}

class _DayStat {
  final DateTime date;
  final Macros macros;
  final bool hasLog;

  const _DayStat({
    required this.date,
    required this.macros,
    required this.hasLog,
  });
}

class _PeriodToggle extends StatelessWidget {
  final _AnalyticsPeriod period;
  final ValueChanged<_AnalyticsPeriod> onChanged;

  const _PeriodToggle({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _seg('Неделя', _AnalyticsPeriod.week),
          _seg('Месяц', _AnalyticsPeriod.month),
        ],
      ),
    );
  }

  Widget _seg(String label, _AnalyticsPeriod value) {
    final on = period == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: on ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AverageCard extends StatelessWidget {
  final _AnalyticsData data;

  const _AverageCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final vs = data.vsGoalPercent;
    final good = vs <= 0;
    final chipColor = good ? AppColors.primary : AppColors.streak;
    final chipBg = chipColor.withValues(alpha: 0.12);
    final chipText = vs == 0
        ? 'в цели'
        : '${vs > 0 ? '+' : ''}${vs.toStringAsFixed(0)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Среднее за период',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        TextSpan(
                          text: data.avgKcal.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const TextSpan(
                          text: '  ккал',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Цель', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  data.targetKcal > 0
                      ? data.targetKcal.toStringAsFixed(0)
                      : '—',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (data.targetKcal > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      chipText,
                      style: TextStyle(
                        color: chipColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekBarsCard extends StatelessWidget {
  final _AnalyticsData data;

  const _WeekBarsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final chartDays = data.days.length > 7
        ? data.days.sublist(data.days.length - 7)
        : data.days;
    final maxKcal = [
      ...chartDays.map((d) => d.macros.calories),
      data.targetKcal,
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    final today = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.days.length > 7 ? 'Последние 7 дней' : 'Калории по дням',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in chartDays) ...[
                    Expanded(
                      child: _DayBar(
                        day: day,
                        maxKcal: maxKcal,
                        targetKcal: data.targetKcal,
                        isToday: _sameDay(day.date, today),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayBar extends StatelessWidget {
  final _DayStat day;
  final double maxKcal;
  final double targetKcal;
  final bool isToday;

  const _DayBar({
    required this.day,
    required this.maxKcal,
    required this.targetKcal,
    required this.isToday,
  });

  Color get _barColor {
    if (!day.hasLog || day.macros.calories <= 0) {
      return AppColors.surfaceMuted;
    }
    if (targetKcal <= 0) return AppColors.primary;
    final ratio = day.macros.calories / targetKcal;
    if (ratio > 1.1) return AppColors.streak;
    if (ratio < 0.85) return AppColors.breakfast;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final h = maxKcal > 0
        ? (day.macros.calories / maxKcal).clamp(0.0, 1.0) * 96
        : 0.0;
    final label = DateFormat('E', 'ru').format(day.date);
    final short = label.length > 2 ? label.substring(0, 2) : label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (day.hasLog && day.macros.calories > 0)
            Text(
              day.macros.calories.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary.withValues(alpha: 0.85),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            height: h < 4 && day.hasLog ? 4 : h,
            decoration: BoxDecoration(
              color: _barColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: isToday
                  ? Border.all(color: AppColors.primaryDark, width: 2)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            short,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isToday ? AppColors.primaryDark : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRingsCard extends StatelessWidget {
  final _AnalyticsData data;

  const _MacroRingsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Баланс БЖУ', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Среднее относительно дневной цели',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MacroRing(
                  label: 'Белки',
                  percent: data.proteinPct,
                  color: AppColors.protein,
                  grams: data.avgProtein,
                ),
                _MacroRing(
                  label: 'Жиры',
                  percent: data.fatPct,
                  color: AppColors.fat,
                  grams: data.avgFat,
                ),
                _MacroRing(
                  label: 'Углеводы',
                  percent: data.carbsPct,
                  color: AppColors.carbs,
                  grams: data.avgCarbs,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroRing extends StatelessWidget {
  final String label;
  final double percent;
  final Color color;
  final double grams;

  const _MacroRing({
    required this.label,
    required this.percent,
    required this.color,
    required this.grams,
  });

  @override
  Widget build(BuildContext context) {
    final shown = (percent * 100).clamp(0, 150).round();
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    strokeWidth: 8,
                    backgroundColor: AppColors.surfaceMuted,
                    color: color,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$shown%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            '${grams.toStringAsFixed(0)} г',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final _AnalyticsData data;

  const _InsightsCard({required this.data});

  List<_Insight> _buildInsights() {
    final items = <_Insight>[];
    final total = data.days.where((d) => d.hasLog).length;

    if (data.withinGoalDays > 0 && data.targetKcal > 0) {
      items.add(
        _Insight(
          color: AppColors.primary,
          title: data.withinGoalDays >= (total * 0.7).ceil()
              ? 'Стабильный период'
              : 'Есть дни в цели',
          subtitle:
              '${data.withinGoalDays} из $total дней с логом в пределах цели',
        ),
      );
    }

    final highest = data.highestDay;
    if (highest != null &&
        data.targetKcal > 0 &&
        highest.macros.calories > data.targetKcal * 1.1) {
      final over = highest.macros.calories - data.targetKcal;
      final dayLabel = DateFormat('EEEE', 'ru').format(highest.date);
      items.add(
        _Insight(
          color: AppColors.streak,
          title: '${_capitalize(dayLabel)} выше цели',
          subtitle:
              '+${over.toStringAsFixed(0)} ккал (${highest.macros.calories.toStringAsFixed(0)} ккал)',
        ),
      );
    }

    if (data.targetProtein > 0 && data.proteinPct < 0.85) {
      items.add(
        _Insight(
          color: AppColors.protein,
          title: 'Белок ниже цели',
          subtitle:
              'В среднем ${(data.proteinPct * 100).round()}% от нормы — можно подтянуть',
        ),
      );
    } else if (data.targetProtein > 0 && data.proteinPct >= 0.95) {
      items.add(
        _Insight(
          color: AppColors.protein,
          title: 'Белок в норме',
          subtitle:
              'Среднее ${data.avgProtein.toStringAsFixed(0)} г при цели ${data.targetProtein.toStringAsFixed(0)} г',
        ),
      );
    }

    if (data.loggedDays < data.days.length) {
      items.add(
        _Insight(
          color: AppColors.textSecondary,
          title: 'Не все дни заполнены',
          subtitle: 'Лог есть за ${data.loggedDays} из ${data.days.length} дней',
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const _Insight(
          color: AppColors.primary,
          title: 'Продолжайте вести дневник',
          subtitle: 'Через несколько дней здесь появятся персональные выводы',
        ),
      );
    }

    return items.take(3).toList();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final insights = _buildInsights();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Инсайты', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (var i = 0; i < insights.length; i++) ...[
              if (i > 0)
                Divider(height: 20, color: Colors.black.withValues(alpha: 0.06)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: insights[i].color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insights[i].title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          insights[i].subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Insight {
  final Color color;
  final String title;
  final String subtitle;

  const _Insight({
    required this.color,
    required this.title,
    required this.subtitle,
  });
}
