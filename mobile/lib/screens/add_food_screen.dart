import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';

class AddFoodScreen extends ConsumerStatefulWidget {
  final String date;
  final MealType? mealType;

  const AddFoodScreen({
    super.key,
    required this.date,
    this.mealType,
  });

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  MealType _mealType = MealType.breakfast;
  final _searchController = TextEditingController();
  final _gramsController = TextEditingController(text: '100');
  final _nameController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController(text: '0');
  final _fatController = TextEditingController(text: '0');
  final _carbsController = TextEditingController(text: '0');
  bool _manualMode = false;
  bool _searching = false;
  List<FoodSearchResult> _results = [];
  FoodSearchResult? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.mealType != null) _mealType = widget.mealType!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gramsController.dispose();
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _results = [];
      _selected = null;
    });
    try {
      final results = await ref.read(offServiceProvider).search(_searchController.text);
      if (!mounted) return;
      setState(() => _results = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ничего не найдено. Попробуйте другое название.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка поиска: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectResult(FoodSearchResult result) {
    setState(() {
      _selected = result;
      _nameController.text = result.name;
    });
  }

  Future<void> _save() async {
    final grams = double.tryParse(_gramsController.text);
    if (grams == null || grams <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите вес в граммах')),
      );
      return;
    }

    late Macros macros;
    late String name;

    if (_manualMode) {
      name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите название')),
        );
        return;
      }
      macros = Macros(
        calories: double.tryParse(_kcalController.text) ?? 0,
        protein: double.tryParse(_proteinController.text) ?? 0,
        fat: double.tryParse(_fatController.text) ?? 0,
        carbs: double.tryParse(_carbsController.text) ?? 0,
      );
    } else if (_selected != null) {
      name = _selected!.name;
      macros = _selected!.macrosForGrams(grams);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите продукт из поиска')),
      );
      return;
    }

    await AppDatabase.addEntry(FoodEntry(
      date: widget.date,
      mealType: _mealType,
      name: name,
      grams: grams,
      calories: macros.calories,
      protein: macros.protein,
      fat: macros.fat,
      carbs: macros.carbs,
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить продукт')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<MealType>(
            value: _mealType,
            decoration: const InputDecoration(labelText: 'Приём пищи'),
            items: MealType.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (v) => setState(() => _mealType = v!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Поиск')),
              ButtonSegment(value: true, label: Text('Вручную')),
            ],
            selected: {_manualMode},
            onSelectionChanged: (s) => setState(() => _manualMode = s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _gramsController,
            decoration: const InputDecoration(labelText: 'Вес (г)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          if (_manualMode) ...[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _kcalController,
              decoration: const InputDecoration(labelText: 'Калории (ккал)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _proteinController,
              decoration: const InputDecoration(labelText: 'Белки (г)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fatController,
              decoration: const InputDecoration(labelText: 'Жиры (г)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _carbsController,
              decoration: const InputDecoration(labelText: 'Углеводы (г)'),
              keyboardType: TextInputType.number,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Поиск продукта',
                      hintText: 'овсянка, курица...',
                    ),
                    onFieldSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(
                  icon: _searching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._results.map(
              (r) => ListTile(
                title: Text(r.name),
                subtitle: Text(
                  '${r.kcalPer100g.toStringAsFixed(0)} ккал/100г'
                  '${r.brand != null ? ' · ${r.brand}' : ''}',
                ),
                selected: _selected?.name == r.name,
                onTap: () => _selectResult(r),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
