import 'package:flutter/material.dart';

import '../models/models.dart';

class MacroProgressBar extends StatelessWidget {
  final String label;
  final double current;
  final double target;
  final Color color;
  final String unit;

  const MacroProgressBar({
    super.key,
    required this.label,
    required this.current,
    required this.target,
    required this.color,
    this.unit = 'г',
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} $unit',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.15),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class DailySummaryCard extends StatelessWidget {
  final Macros consumed;
  final Macros targets;

  const DailySummaryCard({
    super.key,
    required this.consumed,
    required this.targets,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = Macros(
      calories: (targets.calories - consumed.calories).clamp(0, double.infinity),
      protein: (targets.protein - consumed.protein).clamp(0, double.infinity),
      fat: (targets.fat - consumed.fat).clamp(0, double.infinity),
      carbs: (targets.carbs - consumed.carbs).clamp(0, double.infinity),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сводка дня', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Осталось сегодня ${remaining.calories.toStringAsFixed(0)} ккал',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _MacroChip(
                  label: 'Б',
                  current: consumed.protein,
                  target: targets.protein,
                  color: Colors.blue,
                ),
                _MacroChip(
                  label: 'Ж',
                  current: consumed.fat,
                  target: targets.fat,
                  color: Colors.orange,
                ),
                _MacroChip(
                  label: 'У',
                  current: consumed.carbs,
                  target: targets.carbs,
                  color: Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 12),
            MacroProgressBar(
              label: 'Калории',
              current: consumed.calories,
              target: targets.calories,
              color: Colors.green,
              unit: 'ккал',
            ),
            MacroProgressBar(
              label: 'Белки',
              current: consumed.protein,
              target: targets.protein,
              color: Colors.blue,
            ),
            MacroProgressBar(
              label: 'Жиры',
              current: consumed.fat,
              target: targets.fat,
              color: Colors.orange,
            ),
            MacroProgressBar(
              label: 'Углеводы',
              current: consumed.carbs,
              target: targets.carbs,
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final double current;
  final double target;
  final Color color;

  const _MacroChip({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label ${current.toStringAsFixed(0)}/${target.toStringAsFixed(0)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class FoodEntryTile extends StatelessWidget {
  final FoodEntry entry;
  final VoidCallback onDelete;

  const FoodEntryTile({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  static String _macroLine(FoodEntry entry) {
    final parts = <String>[
      '${entry.grams.toStringAsFixed(0)} г',
      '${entry.calories.toStringAsFixed(0)} ккал',
    ];
    if (entry.protein > 0 || entry.fat > 0 || entry.carbs > 0) {
      parts.add(
        'Б ${entry.protein.toStringAsFixed(0)} · '
        'Ж ${entry.fat.toStringAsFixed(0)} · '
        'У ${entry.carbs.toStringAsFixed(0)}',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(entry.name),
      subtitle: Text(_macroLine(entry)),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

String formatMacrosPer100({
  required double kcal,
  required double protein,
  required double fat,
  required double carbs,
}) {
  return '${kcal.toStringAsFixed(0)} ккал · '
      'Б ${protein.toStringAsFixed(1)} · '
      'Ж ${fat.toStringAsFixed(1)} · '
      'У ${carbs.toStringAsFixed(1)} (на 100 г)';
}

String formatMacrosTotal(Macros macros) {
  return '${macros.calories.toStringAsFixed(0)} ккал · '
      'Б ${macros.protein.toStringAsFixed(1)} · '
      'Ж ${macros.fat.toStringAsFixed(1)} · '
      'У ${macros.carbs.toStringAsFixed(1)}';
}
