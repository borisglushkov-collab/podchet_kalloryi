import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/nutrition_calculator.dart';
import '../services/wellness_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/wellness_widgets.dart';
import '../widgets/widgets.dart';
import 'add_food_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'suggestions_screen.dart';

class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key});

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  int _streak = 0;
  int _waterGlasses = 0;
  Set<String> _loggedDates = {};

  @override
  void initState() {
    super.initState();
    _loadWellness();
  }

  Future<void> _loadWellness() async {
    final date = ref.read(selectedDateProvider);
    final dateStr = formatDate(date);
    final glasses = await WellnessStorage.getWaterGlasses(dateStr);
    final streak = await WellnessStorage.refreshStreak(dateStr);
    final logged = await _loadLoggedWeek(date);
    if (mounted) {
      setState(() {
        _waterGlasses = glasses;
        _streak = streak;
        _loggedDates = logged;
      });
    }
  }

  Future<Set<String>> _loadLoggedWeek(DateTime anchor) async {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    final dates = <String>{};
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final dateStr = formatDate(day);
      final entries = await AppDatabase.getEntriesForDate(dateStr);
      if (entries.isNotEmpty) dates.add(dateStr);
    }
    return dates;
  }

  Future<void> _refresh(String dateStr) async {
    ref.invalidate(dailyEntriesProvider(dateStr));
    ref.invalidate(dailyTotalsProvider(dateStr));
    await _loadWellness();
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider);
    final dateStr = formatDate(date);
    final entriesAsync = ref.watch(dailyEntriesProvider(dateStr));
    final totalsAsync = ref.watch(dailyTotalsProvider(dateStr));
    final targetsAsync = ref.watch(dailyTargetsProvider);
    final profileAsync = ref.watch(profileProvider);

    ref.listen(selectedDateProvider, (_, __) => _loadWellness());

    return Scaffold(
      backgroundColor: AppColors.background,
      // primary: false — статус-бар уже учтён SafeArea в MainShell.
      appBar: AppBar(
        primary: false,
        toolbarHeight: 56,
        title: const Text('Сегодня'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.eco_outlined, size: 64, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text('Заполните профиль, чтобы начать путь к цели'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      ),
                      child: const Text('Создать профиль'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _refresh(dateStr),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            WellnessStorage.greetingForHour(DateTime.now().hour),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Твой план на сегодня',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    StreakBadge(days: _streak),
                  ],
                ),
                const SizedBox(height: 16),
                WeekStrip(
                  selectedDate: date,
                  loggedDates: _loggedDates,
                  onDateSelected: (d) =>
                      ref.read(selectedDateProvider.notifier).state = d,
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
                      return Column(
                        children: [
                          WellnessHeroCard(consumed: totals, targets: targets),
                          const SizedBox(height: 12),
                          MacroStatsRow(consumed: totals),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                entriesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (entries) => totalsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (totals) => targetsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (targets) {
                        if (targets == null) return const SizedBox.shrink();
                        final mealPlan = NutritionCalculator.computeMealPlan(
                          targets,
                          NutritionCalculator.consumedByMeal(entries),
                        );
                        final currentMeal = findCurrentMeal(mealPlan);
                        final proteinDeficit =
                            (targets.protein - totals.protein).clamp(0.0, double.infinity);
                        final kcalDeficit =
                            (targets.calories - totals.calories).clamp(0.0, double.infinity);
                        final coachMeal = currentMeal ?? MealType.lunch;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CoachCard(
                              tip: WellnessStorage.coachTip(
                                proteinDeficit: proteinDeficit,
                                kcalDeficit: kcalDeficit,
                                mealLabel: coachMeal.label.toLowerCase(),
                              ),
                              actionLabel: 'Добавить в ${coachMeal.label.toLowerCase()}',
                              onAction: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SuggestionsScreen(date: dateStr),
                                ),
                              ),
                              onMore: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddFoodScreen(
                                    date: dateStr,
                                    mealType: coachMeal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Приёмы пищи', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _MealTileGrid(
                              mealPlan: mealPlan,
                              currentMeal: currentMeal,
                              date: dateStr,
                              onRefresh: () => _refresh(dateStr),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                WaterTrackerCard(
                  glasses: _waterGlasses,
                  onChanged: (g) async {
                    await WellnessStorage.setWaterGlasses(dateStr, g);
                    setState(() => _waterGlasses = g);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MealTileGrid extends StatelessWidget {
  final Map<MealType, MealPlanInfo> mealPlan;
  final MealType? currentMeal;
  final String date;
  final VoidCallback onRefresh;

  const _MealTileGrid({
    required this.mealPlan,
    required this.currentMeal,
    required this.date,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final meals = MealType.values;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MealTile(
                mealType: meals[0],
                plan: mealPlan[meals[0]]!,
                status: mealTileStatus(
                  plan: mealPlan[meals[0]]!,
                  currentMeal: currentMeal,
                  meal: meals[0],
                ),
                onTap: () => _openMeal(context, meals[0]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MealTile(
                mealType: meals[1],
                plan: mealPlan[meals[1]]!,
                status: mealTileStatus(
                  plan: mealPlan[meals[1]]!,
                  currentMeal: currentMeal,
                  meal: meals[1],
                ),
                onTap: () => _openMeal(context, meals[1]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MealTile(
                mealType: meals[2],
                plan: mealPlan[meals[2]]!,
                status: mealTileStatus(
                  plan: mealPlan[meals[2]]!,
                  currentMeal: currentMeal,
                  meal: meals[2],
                ),
                onTap: () => _openMeal(context, meals[2]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MealTile(
                mealType: meals[3],
                plan: mealPlan[meals[3]]!,
                status: mealTileStatus(
                  plan: mealPlan[meals[3]]!,
                  currentMeal: currentMeal,
                  meal: meals[3],
                ),
                onTap: () => _openMeal(context, meals[3]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openMeal(BuildContext context, MealType meal) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MealDetailSheet(
        initialMeal: meal,
        date: date,
        mealPlan: mealPlan,
        onRefresh: onRefresh,
      ),
    );
  }
}

class _MealDetailSheet extends ConsumerStatefulWidget {
  final MealType initialMeal;
  final String date;
  final Map<MealType, MealPlanInfo> mealPlan;
  final VoidCallback onRefresh;

  const _MealDetailSheet({
    required this.initialMeal,
    required this.date,
    required this.mealPlan,
    required this.onRefresh,
  });

  @override
  ConsumerState<_MealDetailSheet> createState() => _MealDetailSheetState();
}

class _MealDetailSheetState extends ConsumerState<_MealDetailSheet> {
  late MealType _mealType;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMeal;
  }

  MealPlanInfo get _plan => widget.mealPlan[_mealType]!;

  Future<void> _addFood() async {
    // Не закрываем sheet — вернёмся сюда после добавления.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddFoodScreen(date: widget.date, mealType: _mealType),
      ),
    );
    if (!mounted) return;
    widget.onRefresh();
    ref.invalidate(dailyEntriesProvider(widget.date));
    ref.invalidate(dailyTotalsProvider(widget.date));
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(dailyEntriesProvider(widget.date));
    final targetsAsync = ref.watch(dailyTargetsProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Живой план по текущим записям (после добавления/удаления).
    final livePlan = () {
      final entries = entriesAsync.valueOrNull;
      final targets = targetsAsync.valueOrNull;
      if (entries == null || targets == null) return _plan;
      return NutritionCalculator.computeMealPlan(
        targets,
        NutritionCalculator.consumedByMeal(entries),
      )[_mealType]!;
    }();

    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Приём пищи',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MealType.values.map((meal) {
                  final on = meal == _mealType;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(meal.label),
                      selected: on,
                      onSelected: (_) => setState(() => _mealType = meal),
                      selectedColor: AppColors.primary.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: on ? AppColors.primaryDark : AppColors.textPrimary,
                      ),
                      side: BorderSide(
                        color: on
                            ? AppColors.primary
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${livePlan.consumed.calories.toStringAsFixed(0)} / '
              '${livePlan.effectiveTarget.calories.toStringAsFixed(0)} ккал',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (livePlan.hasRollover)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Перенос: ${livePlan.rolloverIn.calories.toStringAsFixed(0)} ккал',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: entriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Ошибка загрузки')),
                data: (entries) {
                  final mealEntries =
                      entries.where((e) => e.mealType == _mealType).toList();
                  if (mealEntries.isEmpty) {
                    return Center(
                      child: Text(
                        'Нет записей.\nНажмите «+ Добавить», чтобы внести продукт.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: mealEntries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = mealEntries[i];
                      return FoodEntryTile(
                        entry: e,
                        onDelete: () async {
                          if (e.id == null) return;
                          await AppDatabase.deleteEntry(e.id!);
                          widget.onRefresh();
                          ref.invalidate(dailyEntriesProvider(widget.date));
                          ref.invalidate(dailyTotalsProvider(widget.date));
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addFood,
                icon: const Icon(Icons.add),
                label: Text('+ Добавить в ${_mealType.label.toLowerCase()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
