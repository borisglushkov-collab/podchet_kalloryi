import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../providers/providers.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  final String date;

  const SuggestionsScreen({super.key, required this.date});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  MealType _mealType = MealType.dinner;

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

  @override
  Widget build(BuildContext context) {
    final suggestionAsync = ref.watch(mealSuggestionProvider(_mealType));

    return Scaffold(
      appBar: AppBar(title: const Text('ИИ-рекомендации')),
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
                setState(() => _mealType = v!);
                ref.invalidate(mealSuggestionProvider(_mealType));
              },
            ),
          ),
          Expanded(
            child: suggestionAsync.when(
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
                      Text('$e', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(mealSuggestionProvider(_mealType)),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (suggestion) => ListView(
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
                            'Осталось до нормы',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${suggestion.deficit.calories.toStringAsFixed(0)} ккал · '
                            'Б ${suggestion.deficit.protein.toStringAsFixed(0)}г · '
                            'Ж ${suggestion.deficit.fat.toStringAsFixed(0)}г · '
                            'У ${suggestion.deficit.carbs.toStringAsFixed(0)}г',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Рецепты', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...suggestion.recipes.map((r) => _RecipeCard(recipe: r)),
                  const SizedBox(height: 16),
                  Text('Продукты', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...suggestion.products.map(
                    (p) => _ProductCard(product: p, onOpen: () => _openUrl(p.url)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    suggestion.disclaimer,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final RecipeSuggestion recipe;

  const _RecipeCard({required this.recipe});

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
          ],
        ),
      ),
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
