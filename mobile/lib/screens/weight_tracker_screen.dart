import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/weight_chart.dart';

/// Вкладка / экран веса — дизайн A (Yazio Wellness Progress).
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

  String _relativeDay(DateTime date) {
    final days = DateTime.now().difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days == 0) return 'сегодня';
    if (days == 1) return 'вчера';
    if (days < 5) return '$days дня назад';
    return '$days дней назад';
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

  /// Прогресс к цели 0..1 (честный, с учётом направления).
  double _goalProgress(double start, double current, double target) {
    final total = (start - target).abs();
    if (total < 0.05) return current == target ? 1 : 0;
    // Сколько пути от старта к цели уже пройдено.
    final toward = start > target ? (start - current) : (current - start);
    return (toward / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final entriesAsync = ref.watch(weightEntriesProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
                  Text(
                    'Заполните профиль, чтобы отслеживать вес',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          );
        }

        return entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('Ошибка: $e')),
          data: (entries) {
            final sorted = List<WeightEntry>.from(entries)
              ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

            final current = sorted.isNotEmpty ? sorted.first.weightKg : profile.weightKg;
            final start = sorted.isNotEmpty ? sorted.last.weightKg : profile.weightKg;
            final target = profile.targetWeightKg ?? _defaultTarget(profile);
            final deltaFromStart = current - start;
            final remaining = (current - target).abs();
            final progress = _goalProgress(start, current, target);

            final bottomPad = widget.embedded
                ? 28.0
                : 28.0 + MediaQuery.viewPaddingOf(context).bottom;

            final content = ColoredBox(
              color: AppColors.background,
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _reload,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (widget.embedded)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _TopBar(
                            targetKg: target,
                            showBack: false,
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                'цель · ${target.toStringAsFixed(0)} кг',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _HeroProgressCard(
                          current: current,
                          start: start,
                          target: target,
                          progress: progress,
                          deltaFromStart: deltaFromStart,
                          remainingToGoal: remaining,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Динамика',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      sorted.length <= 1 ? 'добавьте записи' : 'все записи',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                WeightChart(
                                  entries: entries,
                                  startWeight: start,
                                  targetWeight: target,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _HistoryCard(
                          entries: sorted,
                          relativeDay: _relativeDay,
                          onDelete: (id) async {
                            await AppDatabase.deleteWeightEntry(id);
                            await _reload();
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
                        child: FilledButton(
                          onPressed: _addWeight,
                          child: const Text('+ Записать вес'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            // Отдельный экран (из профиля): учитываем статус-бар.
            if (widget.embedded) return content;
            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                title: const Text('Вес'),
                backgroundColor: AppColors.background,
              ),
              body: content,
            );
          },
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.targetKg,
    required this.showBack,
    required this.onBack,
  });

  final double targetKg;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            color: AppColors.textPrimary,
          ),
        Expanded(
          child: Text(
            'Вес',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'цель · ${targetKg.toStringAsFixed(0)} кг',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroProgressCard extends StatelessWidget {
  const _HeroProgressCard({
    required this.current,
    required this.start,
    required this.target,
    required this.progress,
    required this.deltaFromStart,
    required this.remainingToGoal,
  });

  final double current;
  final double start;
  final double target;
  final double progress;
  final double deltaFromStart;
  final double remainingToGoal;

  String get _deltaLabel {
    if (deltaFromStart.abs() < 0.05) return 'без изменений';
    final abs = deltaFromStart.abs().toStringAsFixed(1).replaceAll('.', ',');
    if (deltaFromStart > 0) return '↑ +$abs с старта';
    return '↓ −$abs с старта';
  }

  Color get _deltaColor {
    if (deltaFromStart.abs() < 0.05) return AppColors.textSecondary;
    // Набор — красный, сброс — зелёный (для цели похудения это интуитивно).
    return deltaFromStart > 0 ? const Color(0xFFE25555) : AppColors.primaryDark;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _ProgressRing(
                  progress: progress,
                  centerLabel: current.toStringAsFixed(0),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Текущий вес',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      Text(
                        current.toStringAsFixed(1).replaceAll('.', ','),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _deltaColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _deltaLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _deltaColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'до цели ${remainingToGoal.toStringAsFixed(1).replaceAll('.', ',')} кг',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.75),
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'старт ${start.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  'цель ${target.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.centerLabel});

  final double progress;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 118,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 118,
            height: 118,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 10,
              backgroundColor: Colors.white,
              color: AppColors.primary,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'кг',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entries,
    required this.relativeDay,
    required this.onDelete,
  });

  final List<WeightEntry> entries;
  final String Function(DateTime) relativeDay;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'История',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Нажмите «+ Записать вес», чтобы добавить первую запись',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...entries.asMap().entries.map((indexed) {
                final i = indexed.key;
                final entry = indexed.value;
                final prev = i + 1 < entries.length ? entries[i + 1] : null;
                final delta = prev != null ? entry.weightKg - prev.weightKg : null;
                final sourceLabel =
                    entry.source == WeightEntrySource.scale ? 'весы' : 'вручную';
                final dayLabel = relativeDay(entry.recordedAt);
                final dateLabel = DateFormat('d MMM', 'ru').format(entry.recordedAt);

                return Dismissible(
                  key: ValueKey('w-${entry.id}-$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: const Color(0xFFE25555).withValues(alpha: 0.85),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: i == 0
                              ? Colors.transparent
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateLabel,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '$dayLabel · $sourceLabel',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${entry.weightKg.toStringAsFixed(1).replaceAll('.', ',')} кг',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if (delta != null && delta.abs() >= 0.05)
                              Text(
                                delta > 0
                                    ? '↑ ${delta.toStringAsFixed(1).replaceAll('.', ',')}'
                                    : '↓ ${delta.abs().toStringAsFixed(1).replaceAll('.', ',')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: delta > 0
                                      ? const Color(0xFFE25555)
                                      : AppColors.primaryDark,
                                ),
                              )
                            else
                              const Text(
                                '—',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
