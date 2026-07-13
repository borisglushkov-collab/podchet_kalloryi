import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../services/nutrition_calculator.dart';
import '../theme/app_theme.dart';
import '../utils/api_error_utils.dart';
import '../widgets/widgets.dart';
import 'settings_screen.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  final String date;
  final bool embedded;

  const SuggestionsScreen({super.key, required this.date, this.embedded = false});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  MealType _mealType = MealType.dinner;
  MealSuggestion? _offlineSuggestion;
  bool _resettingSession = false;

  Future<void> _retrySuggestion({bool resetSession = false}) async {
    setState(() => _offlineSuggestion = null);
    if (resetSession) {
      setState(() => _resettingSession = true);
      try {
        await ref.read(apiServiceProvider).resetAiSession();
      } catch (_) {
        // ignore — всё равно пробуем заново
      } finally {
        if (mounted) setState(() => _resettingSession = false);
      }
    }
    ref.invalidate(mealSuggestionProvider(_mealType));
  }

  Future<void> _showOfflinePlan() async {
    final profile = await ref.read(profileProvider.future);
    final targets = await ref.read(dailyTargetsProvider.future);
    final consumed = await ref.read(dailyTotalsProvider(widget.date).future);
    final entries = await ref.read(dailyEntriesProvider(widget.date).future);
    if (!mounted || profile == null || targets == null) return;

    setState(() {
      _offlineSuggestion = NutritionCalculator.offlineMealSuggestion(
        mealType: _mealType,
        consumed: consumed,
        targets: targets,
        mealsConsumed: NutritionCalculator.consumedByMeal(entries),
      );
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку')),
        );
      }
    }
  }

  Future<void> _addRecipeToDiary(RecipeSuggestion recipe) async {
    final portions = await showDialog<double>(
      context: context,
      builder: (ctx) => _PortionDialog(
        recipeName: recipe.name,
        nutrition: recipe.nutrition,
      ),
    );
    if (portions == null || !mounted) return;

    final factor = portions;
    await AppDatabase.addEntry(FoodEntry(
      date: widget.date,
      mealType: _mealType,
      name: recipe.name,
      grams: 100 * factor,
      calories: recipe.nutrition.calories * factor,
      protein: recipe.nutrition.protein * factor,
      fat: recipe.nutrition.fat * factor,
      carbs: recipe.nutrition.carbs * factor,
    ));

    ref.invalidate(dailyEntriesProvider(widget.date));
    ref.invalidate(dailyTotalsProvider(widget.date));
    ref.invalidate(mealSuggestionProvider(_mealType));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '«${recipe.name}» добавлено в ${_mealType.label} '
          '(${formatMacrosTotal(recipe.nutrition * factor)})',
        ),
      ),
    );
  }

  void _selectMeal(MealType meal) {
    if (meal == _mealType) return;
    setState(() {
      _mealType = meal;
      _offlineSuggestion = null;
    });
    ref.invalidate(mealSuggestionProvider(_mealType));
  }

  @override
  Widget build(BuildContext context) {
    final suggestionAsync = ref.watch(mealSuggestionProvider(_mealType));
    final totalsAsync = ref.watch(dailyTotalsProvider(widget.date));
    final targetsAsync = ref.watch(dailyTargetsProvider);

    final remainingKcal = () {
      final totals = totalsAsync.valueOrNull;
      final targets = targetsAsync.valueOrNull;
      if (totals == null || targets == null) return null;
      return (targets.calories - totals.calories).clamp(0, double.infinity);
    }();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Коуч'),
              backgroundColor: AppColors.background,
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, widget.embedded ? 12 : 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Коуч',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (remainingKcal != null)
                    _SoftChip(
                      label: 'осталось ${remainingKcal.toStringAsFixed(0)} ккал',
                      background: AppColors.primary.withValues(alpha: 0.15),
                      foreground: AppColors.primaryDark,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _MealChips(
                selected: _mealType,
                onSelected: _selectMeal,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _offlineSuggestion != null
                  ? _buildSuggestionBody(_offlineSuggestion!)
                  : suggestionAsync.when(
                      loading: () => const _CoachLoading(),
                      error: (e, _) => _CoachError(
                        error: e,
                        resettingSession: _resettingSession,
                        onRetry: () => _retrySuggestion(resetSession: false),
                        onResetSession: () => _retrySuggestion(resetSession: true),
                        onOffline: _showOfflinePlan,
                        onSettings: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                      ),
                      data: (suggestion) => _buildSuggestionBody(suggestion),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionBody(MealSuggestion suggestion) {
    final tipText = suggestion.topUpSummary.isNotEmpty
        ? suggestion.topUpSummary
        : _fallbackTip(suggestion);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _TipCard(
          mealLabel: _mealType.label.toLowerCase(),
          tipText: tipText,
          deficit: suggestion.deficit,
          priorityMacros: suggestion.priorityMacros,
          rolloverIn: suggestion.rolloverIn,
          mealShare: NutritionCalculator.mealShareLabel(_mealType),
          isSnackCloseDay: _mealType == MealType.snack && suggestion.deficit.calories > 0,
          dailyDeficit: suggestion.dailyDeficit,
        ),
        if (suggestion.recipes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Рецепты',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...suggestion.recipes.map(
                    (r) => _CompactRecipeTile(
                      recipe: r,
                      onAdd: () => _addRecipeToDiary(r),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (suggestion.products.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Продукты',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  ...suggestion.products.map(
                    (p) => _ProductTile(product: p, onOpen: () => _openUrl(p.url)),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _resettingSession
              ? null
              : () => _retrySuggestion(resetSession: false),
          child: Text(_resettingSession ? 'Обновляем…' : 'Ещё идеи'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _showOfflinePlan,
          child: const Text('Показать без ИИ'),
        ),
        const SizedBox(height: 16),
        Text(
          suggestion.disclaimer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }

  String _fallbackTip(MealSuggestion suggestion) {
    if (suggestion.priorityMacros.isNotEmpty) {
      final focus = suggestion.priorityMacros.first;
      return 'До цели не хватает по макросу «$focus». '
          'Выберите блюдо, которое закроет норму на ${_mealType.label.toLowerCase()} '
          'без лишнего перебора.';
    }
    final kcal = suggestion.deficit.calories.toStringAsFixed(0);
    return 'На ${_mealType.label.toLowerCase()} осталось около $kcal ккал. '
        'Подберите рецепт под свой дефицит.';
  }
}

class _MealChips extends StatelessWidget {
  final MealType selected;
  final ValueChanged<MealType> onSelected;

  const _MealChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: MealType.values.map((meal) {
          final on = meal == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(meal),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on
                        ? AppColors.primary
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  meal.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: on ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SoftChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _SoftChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String mealLabel;
  final String tipText;
  final Macros deficit;
  final List<String> priorityMacros;
  final Macros rolloverIn;
  final String mealShare;
  final bool isSnackCloseDay;
  final Macros dailyDeficit;

  const _TipCard({
    required this.mealLabel,
    required this.tipText,
    required this.deficit,
    required this.priorityMacros,
    required this.rolloverIn,
    required this.mealShare,
    required this.isSnackCloseDay,
    required this.dailyDeficit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Совет на $mealLabel',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                _SoftChip(
                  label: 'ИИ',
                  background: AppColors.protein.withValues(alpha: 0.15),
                  foreground: AppColors.protein,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              mealShare,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (rolloverIn.calories > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Перенос с предыдущих приёмов: '
                '${rolloverIn.calories.toStringAsFixed(0)} ккал',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
            if (isSnackCloseDay) ...[
              const SizedBox(height: 4),
              Text(
                'Последний приём — закройте весь остаток дня',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              tipText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                  ),
            ),
            if (priorityMacros.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: priorityMacros
                    .map(
                      (macro) => _SoftChip(
                        label: 'Нужно: $macro',
                        background: AppColors.primary.withValues(alpha: 0.12),
                        foreground: AppColors.primaryDark,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SoftChip(
                  label: '${deficit.calories.toStringAsFixed(0)} ккал',
                  background: AppColors.primary.withValues(alpha: 0.15),
                  foreground: AppColors.primaryDark,
                ),
                _SoftChip(
                  label: 'Б ${deficit.protein.toStringAsFixed(0)}г',
                  background: AppColors.protein.withValues(alpha: 0.15),
                  foreground: AppColors.protein,
                ),
                _SoftChip(
                  label: 'Ж ${deficit.fat.toStringAsFixed(0)}г',
                  background: AppColors.fat.withValues(alpha: 0.18),
                  foreground: AppColors.fat,
                ),
                _SoftChip(
                  label: 'У ${deficit.carbs.toStringAsFixed(0)}г',
                  background: AppColors.carbs.withValues(alpha: 0.15),
                  foreground: AppColors.carbs,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'За день осталось: '
              '${dailyDeficit.calories.toStringAsFixed(0)} ккал · '
              'Б ${dailyDeficit.protein.toStringAsFixed(0)}г · '
              'Ж ${dailyDeficit.fat.toStringAsFixed(0)}г · '
              'У ${dailyDeficit.carbs.toStringAsFixed(0)}г',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRecipeTile extends StatefulWidget {
  final RecipeSuggestion recipe;
  final VoidCallback onAdd;

  const _CompactRecipeTile({required this.recipe, required this.onAdd});

  @override
  State<_CompactRecipeTile> createState() => _CompactRecipeTileState();
}

class _CompactRecipeTileState extends State<_CompactRecipeTile> {
  bool _expanded = false;

  /// Emoji-бейдж блюда (как в макете Coach A) — Material Icons часто
  /// не рисуются после tree-shake / на части устройств.
  String get _dishEmoji {
    final name = widget.recipe.name.toLowerCase();
    final hay = '$name ${widget.recipe.ingredients.map((i) => i['name'] ?? '').join(' ').toLowerCase()}';

    if (_any(hay, ['лосос', 'семг', 'рыб', 'тунец', 'треск', 'форел', 'селед', 'кревет', 'морепроду'])) {
      return '🐟';
    }
    if (_any(hay, ['курин', 'куриц', 'индейк', 'цыпл'])) {
      return '🍗';
    }
    if (_any(hay, ['говяд', 'телят', 'стейк'])) {
      return '🥩';
    }
    if (_any(hay, ['свинин', 'бекон'])) {
      return '🥓';
    }
    if (_any(hay, ['салат', 'овощ', 'broccoli', 'броккол', 'шпинат', 'зелень'])) {
      return '🥗';
    }
    if (_any(hay, ['творог', 'йогурт', 'кефир', 'сыр', 'молоч'])) {
      return '🧀';
    }
    if (_any(hay, ['яйц', 'омлет', 'яичн'])) {
      return '🥚';
    }
    if (_any(hay, ['каш', 'овсян', 'гречк', 'рис', 'киноа', 'пшён', 'пшен'])) {
      return '🥣';
    }
    if (_any(hay, ['суп', 'борщ', 'бульон', 'похлёб', 'похлеб'])) {
      return '🍲';
    }
    if (_any(hay, ['паст', 'спагет', 'лапш', 'макарон'])) {
      return '🍝';
    }
    if (_any(hay, ['тост', 'хлеб', 'бутер', 'сэндвич', 'сендвич'])) {
      return '🥪';
    }
    if (_any(hay, ['фрукт', 'яблок', 'банан', 'ягод', 'смузи'])) {
      return '🍎';
    }
    if (_any(hay, ['орех', 'семеч', 'авокад'])) {
      return '🥑';
    }
    return '🍽️';
  }

  bool _any(String hay, List<String> keys) => keys.any(hay.contains);

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _dishEmoji,
                        style: const TextStyle(fontSize: 24, height: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '~${r.nutrition.calories.toStringAsFixed(0)} ккал · '
                            'Б ${r.nutrition.protein.toStringAsFixed(0)}г · '
                            '${r.cookingTimeMin} мин',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: widget.onAdd,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppColors.primaryDark,
                              side: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.45),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('В дневник'),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  if (r.whyFits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.whyFits,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Ингредиенты',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  ...r.ingredients.map(
                    (i) => Text(
                      '• ${i['name'] ?? ''} ${i['amount'] ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Шаги',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  ...r.steps.asMap().entries.map(
                        (e) => Text(
                          '${e.key + 1}. ${e.value}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductSuggestion product;
  final VoidCallback onOpen;

  const _ProductTile({required this.product, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: product.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                product.imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.shopping_basket_outlined),
              ),
            )
          : Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shopping_basket_outlined, color: AppColors.textSecondary),
            ),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(
        [
          if (product.reason.isNotEmpty) product.reason,
          if (product.priceRub != null) '${product.priceRub} ₽',
          product.store,
        ].join(' · '),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.open_in_new, size: 18, color: AppColors.textSecondary),
      onTap: onOpen,
    );
  }
}

class _CoachLoading extends StatelessWidget {
  const _CoachLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'ИИ анализирует ваш дневник…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Это может занять до 2 минут',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachError extends StatelessWidget {
  final Object error;
  final bool resettingSession;
  final VoidCallback onRetry;
  final VoidCallback onResetSession;
  final VoidCallback onOffline;
  final VoidCallback onSettings;

  const _CoachError({
    required this.error,
    required this.resettingSession,
    required this.onRetry,
    required this.onResetSession,
    required this.onOffline,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.cloud_off_outlined, size: 32, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              formatApiError(error),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Сервер: ${SettingsService.defaultBackendUrl}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: resettingSession ? null : onRetry,
              child: Text(resettingSession ? 'Сброс…' : 'Повторить'),
            ),
            if (isAiBusyError(error)) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: resettingSession ? null : onResetSession,
                child: const Text('Сбросить сессию ИИ'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onOffline,
              child: const Text('Показать без ИИ'),
            ),
            TextButton(
              onPressed: onSettings,
              child: const Text('Настройки сервера'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortionDialog extends StatefulWidget {
  final String recipeName;
  final Macros nutrition;

  const _PortionDialog({
    required this.recipeName,
    required this.nutrition,
  });

  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  double _portions = 1;

  @override
  Widget build(BuildContext context) {
    final scaled = widget.nutrition * _portions;
    return AlertDialog(
      title: Text('Добавить «${widget.recipeName}»?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Сколько порций добавить в дневник?'),
          const SizedBox(height: 12),
          Slider(
            value: _portions,
            min: 0.5,
            max: 2,
            divisions: 3,
            label: _portions.toStringAsFixed(1),
            onChanged: (v) => setState(() => _portions = v),
          ),
          Text('Порций: ${_portions.toStringAsFixed(1)}'),
          const SizedBox(height: 12),
          Text(
            formatMacrosTotal(scaled),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _portions),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
