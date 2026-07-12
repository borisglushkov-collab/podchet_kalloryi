import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/weight_chart.dart';

/// Экран отслеживания веса в стиле FatSecret.
class WeightTrackerScreen extends ConsumerStatefulWidget {
  const WeightTrackerScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WeightTrackerScreen> createState() => _WeightTrackerScreenState();
}

class _WeightTrackerScreenState extends ConsumerState<WeightTrackerScreen> {
  Future<void> _reload() async {
    ref.invalidate(weightEntriesProvider);
    ref.invalidate(profileProvider);
  }

  Future<void> _addWeight() async {
    final profile = await AppDatabase.getProfile();
    if (profile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала заполните профиль')),
        );
      }
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController(
      text: profile.weightKg.toStringAsFixed(1),
    );

    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Записать вес'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Вес (кг)',
            suffixText: 'кг',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(',', '.'));
              if (v == null || v <= 0) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (kg == null) return;
    await AppDatabase.logWeight(kg, source: WeightEntrySource.manual);
    await _reload();
  }

  String _daysAgoText(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days == 0) return 'сегодня';
    if (days == 1) return '1 день назад';
    if (days < 5) return '$days дня назад';
    return '$days дней назад';
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final entriesAsync = ref.watch(weightEntriesProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (profile) {
        if (profile == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.monitor_weight_outlined, size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text('Заполните профиль, чтобы отслеживать вес'),
                ],
              ),
            ),
          );
        }

        return entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Ошибка: $e')),
          data: (entries) {
            final sorted = List<WeightEntry>.from(entries)
              ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

            final current = sorted.isNotEmpty ? sorted.first.weightKg : profile.weightKg;
            final start = sorted.isNotEmpty ? sorted.last.weightKg : profile.weightKg;
            final target = profile.targetWeightKg ?? _defaultTarget(profile);
            final lost = start - current;
            final remaining = (current - target).abs();

            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _WeightHeader(
                      currentWeight: current,
                      startWeight: start,
                      targetWeight: target,
                      daysAgoText: sorted.isNotEmpty
                          ? _daysAgoText(sorted.first.recordedAt)
                          : null,
                      onAdd: _addWeight,
                      showBack: !widget.embedded,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProgressRow(
                      lost: lost,
                      remaining: remaining,
                      goal: profile.goal,
                    ),
                  ),
                  if (sorted.length >= 2)
                    SliverToBoxAdapter(
                      child: _StreakBanner(entryCount: sorted.length),
                    ),
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.surface,
                      child: WeightChart(
                        entries: entries,
                        startWeight: start,
                        targetWeight: target,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _HistoryList(
                      entries: sorted,
                      onDelete: (id) async {
                        await AppDatabase.deleteWeightEntry(id);
                        await _reload();
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double _defaultTarget(UserProfile profile) {
    switch (profile.goal) {
      case Goal.lose:
        return profile.weightKg * 0.9;
      case Goal.gain:
        return profile.weightKg * 1.1;
      case Goal.maintain:
        return profile.weightKg;
    }
  }
}

class _WeightHeader extends StatelessWidget {
  const _WeightHeader({
    required this.currentWeight,
    required this.startWeight,
    required this.targetWeight,
    required this.onAdd,
    this.daysAgoText,
    this.showBack = false,
  });

  final double currentWeight;
  final double startWeight;
  final double targetWeight;
  final VoidCallback onAdd;
  final String? daysAgoText;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, showBack ? 8 : 16, 16, 20),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showBack)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  )
                else
                  const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Текущий вес',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ],
            ),
            Text(
              '${currentWeight.toStringAsFixed(1).replaceAll('.', ',')} кг',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            if (daysAgoText != null) ...[
              const SizedBox(height: 4),
              Text(
                'Последнее взвешивание — $daysAgoText',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    label: 'Начальный вес',
                    value: '${startWeight.toStringAsFixed(1).replaceAll('.', ',')} кг',
                  ),
                ),
                Container(width: 1, height: 36, color: Colors.white24),
                Expanded(
                  child: _HeaderStat(
                    label: 'Желаемый вес',
                    value: '${targetWeight.toStringAsFixed(1).replaceAll('.', ',')} кг',
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

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.lost,
    required this.remaining,
    required this.goal,
  });

  final double lost;
  final double remaining;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final lostLabel = goal == Goal.gain
        ? 'Набрано'
        : goal == Goal.lose
            ? 'Сброшено'
            : 'Изменение';
    final remainLabel = goal == Goal.gain
        ? 'Осталось набрать'
        : goal == Goal.lose
            ? 'Осталось'
            : 'До цели';

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$lostLabel: ${lost.abs().toStringAsFixed(1).replaceAll('.', ',')} кг',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Icon(
            Icons.monitor_weight_outlined,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          Expanded(
            child: Text(
              '$remainLabel: ${remaining.toStringAsFixed(1).replaceAll('.', ',')} кг',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakBanner extends StatelessWidget {
  const _StreakBanner({required this.entryCount});

  final int entryCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: AppColors.streak),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Записей веса: $entryCount',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  'Записывайте вес регулярно, чтобы видеть прогресс на графике',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries, required this.onDelete});

  final List<WeightEntry> entries;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Нажмите + чтобы добавить первую запись',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      );
    }

    final grouped = <int, List<WeightEntry>>{};
    for (final e in entries) {
      grouped.putIfAbsent(e.recordedAt.year, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((yearGroup) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '${yearGroup.key}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            ...yearGroup.value.asMap().entries.map((i) {
              final entry = i.value;
              final prev = i.key + 1 < yearGroup.value.length
                  ? yearGroup.value[i.key + 1]
                  : null;
              final delta = prev != null ? entry.weightKg - prev.weightKg : null;

              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red.shade300,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Удалить запись?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) {
                  if (entry.id != null) onDelete(entry.id!);
                },
                child: Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          DateFormat('MMM dd', 'ru').format(entry.recordedAt),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${entry.weightKg.toStringAsFixed(1).replaceAll('.', ',')} кг',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (delta != null && delta.abs() >= 0.05)
                        Icon(
                          delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 18,
                          color: delta > 0
                              ? const Color(0xFFE57373)
                              : AppColors.water,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }
}
