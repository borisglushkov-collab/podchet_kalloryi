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
            const Divider(height: 24),
            Text(
              'Осталось: ${remaining.calories.toStringAsFixed(0)} ккал',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(entry.name),
      subtitle: Text(
        '${entry.grams.toStringAsFixed(0)} г · ${entry.calories.toStringAsFixed(0)} ккал',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
