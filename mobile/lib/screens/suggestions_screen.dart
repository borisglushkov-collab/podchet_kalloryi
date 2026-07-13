import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../services/nutrition_calculator.dart';
import '../services/weight_analysis.dart';
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
    final weightEntries = await ref.read(weightEntriesProvider.future);
    if (!mounted || profile == null || targets == null) return;

    final weightAnalysis =
        WeightAnalysis.fromProfileAndEntries(profile, weightEntries);

    setState(() {
      _offlineSuggestion = NutritionCalculator.offlineMealSuggestion(
        mealType: _mealType,
        consumed: consumed,
        targets: targets,
        mealsConsumed: NutritionCalculator.consumedByMeal(entries),
        profile: profile,
        weightAnalysis: weightAnalysis,
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

  @override
  Widget build(BuildContext context) {
    final suggestionAsync = ref.watch(mealSuggestionProvider(_mealType));

    return Scaffold(
      appBar: AppBar(title: Text(widget.embedded ? 'Коуч' : 'ИИ-рекомендации')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<MealType>(
              value: _mealType,
              decoration: const InputDecoration(labelText: 'Приём пищи'),
              items: MealType.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _mealType = v!;
                  _offlineSuggestion = null;
                });
                ref.invalidate(mealSuggestionProvider(_mealType));
              },
            ),
          ),
          Expanded(
            child: _offlineSuggestion != null
                ? _buildSuggestionBody(_offlineSuggestion!)
                : suggestionAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('ИИ анализирует ваш дневник...\nЭто может занять до 2 минут'),
                  ],
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        formatApiError(e),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Сервер: ${SettingsService.defaultBackendUrl}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _resettingSession
                            ? null
                            : () => _retrySuggestion(resetSession: false),
                        child: Text(_resettingSession ? 'Сброс…' : 'Повторить'),
                      ),
                      if (isAiBusyError(e)) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _resettingSession
                              ? null
                              : () => _retrySuggestion(resetSession: true),
                          child: const Text('Сбросить сессию ИИ'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _showOfflinePlan,
                        child: const Text('Показать без ИИ'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                        child: const Text('Настройки сервера'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (suggestion) => _buildSuggestionBody(suggestion),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBody(MealSuggestion suggestion) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Чтобы добить норму на ${_mealType.label.toLowerCase()}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  NutritionCalculator.mealShareLabel(_mealType),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (suggestion.rolloverIn.calories > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Перенос с предыдущих приёмов: '
                    '${suggestion.rolloverIn.calories.toStringAsFixed(0)} ккал · '
                    'Б ${suggestion.rolloverIn.protein.toStringAsFixed(0)}г · '
                    'Ж ${suggestion.rolloverIn.fat.toStringAsFixed(0)}г · '
                    'У ${suggestion.rolloverIn.carbs.toStringAsFixed(0)}г',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_mealType == MealType.snack && suggestion.deficit.calories > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Последний приём — закройте весь остаток дня',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Цель с переносом: '
                  '${suggestion.effectiveTarget.calories.toStringAsFixed(0)} ккал · '
                  'Б ${suggestion.effectiveTarget.protein.toStringAsFixed(0)}г · '
                  'Ж ${suggestion.effectiveTarget.fat.toStringAsFixed(0)}г · '
                  'У ${suggestion.effectiveTarget.carbs.toStringAsFixed(0)}г',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (suggestion.topUpSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(suggestion.topUpSummary),
                ],
                if (suggestion.priorityMacros.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: suggestion.priorityMacros
                        .map(
                          (macro) => Chip(
                            label: Text('Нужно: $macro'),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Осталось: '
                  '${suggestion.deficit.calories.toStringAsFixed(0)} ккал · '
                  'Б ${suggestion.deficit.protein.toStringAsFixed(0)}г · '
                  'Ж ${suggestion.deficit.fat.toStringAsFixed(0)}г · '
                  'У ${suggestion.deficit.carbs.toStringAsFixed(0)}г',
                ),
                const SizedBox(height: 12),
                Text(
                  'За день осталось: '
                  '${suggestion.dailyDeficit.calories.toStringAsFixed(0)} ккал · '
                  'Б ${suggestion.dailyDeficit.protein.toStringAsFixed(0)}г · '
                  'Ж ${suggestion.dailyDeficit.fat.toStringAsFixed(0)}г · '
                  'У ${suggestion.dailyDeficit.carbs.toStringAsFixed(0)}г',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (suggestion.weightInsight.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.monitor_weight_outlined,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Профиль и вес',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(suggestion.weightInsight),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (suggestion.recipes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Рецепты', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...suggestion.recipes.map(
            (r) => _RecipeCard(
              recipe: r,
              mealType: _mealType,
              onAdd: () => _addRecipeToDiary(r),
            ),
          ),
        ],
        if (suggestion.products.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Продукты', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...suggestion.products.map(
            (p) => _ProductCard(product: p, onOpen: () => _openUrl(p.url)),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          suggestion.disclaimer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final RecipeSuggestion recipe;
  final MealType mealType;
  final VoidCallback onAdd;

  const _RecipeCard({
    required this.recipe,
    required this.mealType,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(recipe.name, style: Theme.of(context).textTheme.titleSmall),
            Text('${recipe.cookingTimeMin} мин · ${recipe.difficulty}'),
            if (recipe.whyFits.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                recipe.whyFits,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '~${recipe.nutrition.calories.toStringAsFixed(0)} ккал · '
              'Б ${recipe.nutrition.protein.toStringAsFixed(0)} · '
              'Ж ${recipe.nutrition.fat.toStringAsFixed(0)} · '
              'У ${recipe.nutrition.carbs.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text('Ингредиенты:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...recipe.ingredients.map(
              (i) => Text('• ${i['name'] ?? ''} ${i['amount'] ?? ''}'),
            ),
            const SizedBox(height: 8),
            const Text('Шаги:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...recipe.steps.asMap().entries.map(
              (e) => Text('${e.key + 1}. ${e.value}'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: Text('Добавить в ${mealType.label.toLowerCase()}'),
              ),
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

class _ProductCard extends StatelessWidget {
  final ProductSuggestion product;
  final VoidCallback onOpen;

  const _ProductCard({required this.product, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: product.imageUrl != null
            ? Image.network(product.imageUrl!, width: 48, height: 48, fit: BoxFit.cover)
            : const Icon(Icons.shopping_basket),
        title: Text(product.name),
        subtitle: Text(
          [
            if (product.reason.isNotEmpty) product.reason,
            if (product.priceRub != null) '${product.priceRub} ₽',
            product.store,
          ].join(' · '),
        ),
        trailing: const Icon(Icons.open_in_new),
        onTap: onOpen,
      ),
    );
  }
}
