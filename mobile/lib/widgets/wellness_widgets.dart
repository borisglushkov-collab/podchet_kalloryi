import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/nutrition_calculator.dart';
import '../theme/app_theme.dart';

enum MealTileStatus { done, current, empty }

class WeekStrip extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final Set<String> loggedDates;

  const WeekStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.loggedDates,
  });

  @override
  Widget build(BuildContext context) {
    final start = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final labels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = start.add(Duration(days: i));
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        final isSelected = _sameDay(day, selectedDate);
        final isLogged = loggedDates.contains(dayStr);

        return GestureDetector(
          onTap: () => onDateSelected(day),
          child: Column(
            children: [
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : isLogged
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : isLogged
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class WellnessHeroCard extends StatelessWidget {
  final Macros consumed;
  final Macros targets;

  const WellnessHeroCard({
    super.key,
    required this.consumed,
    required this.targets,
  });

  @override
  Widget build(BuildContext context) {
    final remaining =
        (targets.calories - consumed.calories).clamp(0, double.infinity);
    final progress =
        targets.calories > 0 ? (consumed.calories / targets.calories).clamp(0.0, 1.0) : 0.0;
    final score = WellnessScoreHelper.score(consumed, targets);

    return Card(
      color: AppColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Осталось сегодня', style: Theme.of(context).textTheme.bodySmall),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Оценка $score/100',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              remaining.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                height: 1,
              ),
            ),
            const Text('ккал до цели', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).round()}% дня',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${consumed.calories.toStringAsFixed(0)} из ${targets.calories.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WellnessScoreHelper {
  static int score(Macros consumed, Macros targets) {
    if (targets.calories <= 0) return 0;
    final kcalPart = (consumed.calories / targets.calories).clamp(0.0, 1.0) * 50;
    final proteinPart = targets.protein > 0
        ? (consumed.protein / targets.protein).clamp(0.0, 1.0) * 50
        : 25;
    return (kcalPart + proteinPart).round().clamp(0, 100);
  }
}

class MacroStatsRow extends StatelessWidget {
  final Macros consumed;

  const MacroStatsRow({super.key, required this.consumed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MacroStat(label: 'Белки', value: consumed.protein, color: AppColors.protein),
        _MacroStat(label: 'Жиры', value: consumed.fat, color: AppColors.fat),
        _MacroStat(label: 'Углев.', value: consumed.carbs, color: AppColors.carbs),
      ],
    );
  }
}

class _MacroStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                '${value.toStringAsFixed(0)}г',
                style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoachCard extends StatelessWidget {
  final String tip;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onMore;

  const CoachCard({
    super.key,
    required this.tip,
    required this.actionLabel,
    required this.onAction,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Совет дня', style: Theme.of(context).textTheme.titleSmall),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.protein.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Коуч',
                    style: TextStyle(
                      color: AppColors.protein,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tip, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
                if (onMore != null) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: onMore, child: const Text('Ещё идеи')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MealTile extends StatelessWidget {
  final MealType mealType;
  final MealPlanInfo plan;
  final MealTileStatus status;
  final VoidCallback onTap;

  const MealTile({
    super.key,
    required this.mealType,
    required this.plan,
    required this.status,
    required this.onTap,
  });

  Color get _color {
    switch (mealType) {
      case MealType.breakfast:
        return AppColors.breakfast;
      case MealType.lunch:
        return AppColors.lunch;
      case MealType.dinner:
        return AppColors.dinner;
      case MealType.snack:
        return AppColors.snack;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kcal = plan.consumed.calories;
    final target = plan.effectiveTarget.calories;
    final progress = target > 0 ? (kcal / target).clamp(0.0, 1.0) : 0.0;
    final isCurrent = status == MealTileStatus.current;

    return Material(
      color: isCurrent ? AppColors.surfaceMuted : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: isCurrent ? Border.all(color: AppColors.primary.withValues(alpha: 0.35)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mealType.label,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                kcal.toStringAsFixed(0),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(
                '/ ${target.toStringAsFixed(0)} ккал',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: _color.withValues(alpha: 0.15),
                  color: status == MealTileStatus.done ? AppColors.primary : _color,
                ),
              ),
              if (status == MealTileStatus.done) ...[
                const SizedBox(height: 6),
                _statusChip('Готово', AppColors.primary),
              ] else if (status == MealTileStatus.current) ...[
                const SizedBox(height: 6),
                _statusChip('Сейчас', AppColors.protein),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class WaterTrackerCard extends StatelessWidget {
  final int glasses;
  final ValueChanged<int> onChanged;

  const WaterTrackerCard({
    super.key,
    required this.glasses,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final liters = glasses / WellnessWaterHelper.glassesPerLiter;

    return Card(
      color: AppColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Вода', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '${liters.toStringAsFixed(1)} / ${WellnessWaterHelper.waterGoalLiters.toStringAsFixed(1)} л',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ],
              ),
            ),
            Row(
              children: List.generate(5, (i) {
                final filled = glasses > i * 2;
                return GestureDetector(
                  onTap: () {
                    final next = (i + 1) * 2;
                    onChanged(glasses == next ? next - 2 : next);
                  },
                  child: Container(
                    width: 12,
                    height: 22,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: filled ? AppColors.water : AppColors.water.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class WellnessWaterHelper {
  static const glassesPerLiter = 4;
  static const waterGoalLiters = 2.0;
}

class StreakBadge extends StatelessWidget {
  final int days;

  const StreakBadge({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$days',
              style: const TextStyle(
                color: AppColors.streak,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const TextSpan(text: ' дней', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

MealTileStatus mealTileStatus({
  required MealPlanInfo plan,
  required MealType? currentMeal,
  required MealType meal,
}) {
  final target = plan.effectiveTarget.calories;
  final consumed = plan.consumed.calories;
  if (target > 0 && consumed >= target * 0.9) return MealTileStatus.done;
  if (currentMeal == meal) return MealTileStatus.current;
  if (consumed <= 0) return MealTileStatus.empty;
  return MealTileStatus.empty;
}

MealType? findCurrentMeal(Map<MealType, MealPlanInfo> plan) {
  for (final meal in MealType.values) {
    final info = plan[meal]!;
    if (info.deficit.calories > 20) return meal;
  }
  return null;
}
