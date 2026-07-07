import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'add_food_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'suggestions_screen.dart';

class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final dateStr = formatDate(date);
    final entriesAsync = ref.watch(dailyEntriesProvider(dateStr));
    final totalsAsync = ref.watch(dailyTotalsProvider(dateStr));
    final targetsAsync = ref.watch(dailyTargetsProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Дневник питания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Сначала заполните профиль'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                    child: const Text('Профиль'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dailyEntriesProvider(dateStr));
              ref.invalidate(dailyTotalsProvider(dateStr));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DateSelector(
                  date: date,
                  onChanged: (d) => ref.read(selectedDateProvider.notifier).state = d,
                ),
                const SizedBox(height: 16),
                totalsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (totals) => targetsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (targets) {
                      if (targets == null) return const SizedBox.shrink();
                      return DailySummaryCard(consumed: totals, targets: targets);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SuggestionsScreen(date: dateStr),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Что съесть дальше?'),
                ),
                const SizedBox(height: 24),
                ...MealType.values.map((meal) {
                  return entriesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (entries) => _MealSection(
                      mealType: meal,
                      entries: entries.where((e) => e.mealType == meal).toList(),
                      date: dateStr,
                      onRefresh: () {
                        ref.invalidate(dailyEntriesProvider(dateStr));
                        ref.invalidate(dailyTotalsProvider(dateStr));
                      },
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: profileAsync.valueOrNull != null
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddFoodScreen(date: dateStr),
                  ),
                );
                ref.invalidate(dailyEntriesProvider(dateStr));
                ref.invalidate(dailyTotalsProvider(dateStr));
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book), label: 'Дневник'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Профиль'),
        ],
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          }
        },
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _DateSelector({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('d MMMM yyyy', 'ru').format(date);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
        ),
        Text(formatted, style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(date.add(const Duration(days: 1))),
        ),
      ],
    );
  }
}

class _MealSection extends StatelessWidget {
  final MealType mealType;
  final List<FoodEntry> entries;
  final String date;
  final VoidCallback onRefresh;

  const _MealSection({
    required this.mealType,
    required this.entries,
    required this.date,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final totalKcal = entries.fold(0.0, (sum, e) => sum + e.calories);
    final totalProtein = entries.fold(0.0, (sum, e) => sum + e.protein);
    final totalFat = entries.fold(0.0, (sum, e) => sum + e.fat);
    final totalCarbs = entries.fold(0.0, (sum, e) => sum + e.carbs);
    final macroSummary = (totalProtein > 0 || totalFat > 0 || totalCarbs > 0)
        ? ' · Б ${totalProtein.toStringAsFixed(0)} · Ж ${totalFat.toStringAsFixed(0)} · У ${totalCarbs.toStringAsFixed(0)}'
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(mealType.label),
            subtitle: Text('${totalKcal.toStringAsFixed(0)} ккал$macroSummary'),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddFoodScreen(date: date, mealType: mealType),
                  ),
                );
                onRefresh();
              },
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Нет записей'),
            )
          else
            ...entries.map(
              (e) => FoodEntryTile(
                entry: e,
                onDelete: () async {
                  await AppDatabase.deleteEntry(e.id!);
                  onRefresh();
                },
              ),
            ),
        ],
      ),
    );
  }
}
