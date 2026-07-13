import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/local_food_fallback.dart';
import '../utils/search_query_utils.dart';
import '../widgets/widgets.dart';
import 'barcode_scan_screen.dart';

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
  final _searchFocusNode = FocusNode();
  final _gramsController = TextEditingController(text: '100');
  final _nameController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController(text: '0');
  final _fatController = TextEditingController(text: '0');
  final _carbsController = TextEditingController(text: '0');
  bool _manualMode = false;
  bool _searching = false;
  bool _lookupBusy = false;
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
    _searchFocusNode.dispose();
    _gramsController.dispose();
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = normalizeSearchQuery(_searchController.text);
    if (query != _searchController.text) {
      _searchController.text = query;
      _searchController.selection = TextSelection.collapsed(offset: query.length);
    }
    setState(() {
      _searching = true;
      _results = [];
      _selected = null;
    });
    try {
      final results = await ref.read(foodSearchServiceProvider).search(query);
      if (!mounted) return;
      setState(() => _results = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ничего не найдено. Попробуйте другое название.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final local = searchLocalFallback(query);
        if (local.isNotEmpty) {
          setState(() => _results = local);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Сервер медленный — показаны продукты из локальной базы'),
            ),
          );
          return;
        }
        final message = e.toString().contains('receive timeout')
            ? 'Сервер не ответил вовремя. Проверьте интернет и адрес в настройках.'
            : 'Ошибка поиска: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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
      if (result.suggestedGrams != null && result.suggestedGrams! > 0) {
        _gramsController.text = result.suggestedGrams!.round().toString();
      }
    });
  }

  Future<void> _applyLookup(Future<FoodSearchResult> Function() loader) async {
    setState(() {
      _lookupBusy = true;
      _manualMode = false;
      _results = [];
      _selected = null;
    });
    try {
      final result = await loader();
      if (!mounted) return;
      setState(() {
        _selected = result;
        _results = [result];
        _nameController.text = result.name;
        if (result.suggestedGrams != null && result.suggestedGrams! > 0) {
          _gramsController.text = result.suggestedGrams!.round().toString();
        }
      });
      final notes = result.notes;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notes != null && notes.isNotEmpty
                ? '${result.name}\n$notes'
                : 'Распознано: ${result.name}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(foodLookupServiceProvider).formatLookupError(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  Future<void> _scanBarcode() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сканер штрихкода доступен в мобильном приложении')),
      );
      return;
    }
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || !mounted) return;
    await _applyLookup(
      () => ref.read(foodLookupServiceProvider).lookupBarcode(code),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Анализ фото доступен в мобильном приложении')),
      );
      return;
    }
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    await _applyLookup(
      () => ref.read(foodLookupServiceProvider).analyzePhoto(image.path),
    );
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Macros? get _previewMacros {
    if (_selected == null) return null;
    final grams = double.tryParse(_gramsController.text);
    if (grams == null || grams <= 0) return null;
    return _selected!.macrosForGrams(grams);
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
      if (macros.protein == 0 && macros.fat == 0 && macros.carbs == 0 && macros.calories > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'У продукта нет данных БЖУ на сервере. Заполните вручную во вкладке «Вручную».',
              ),
            ),
          );
        }
        return;
      }
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            onSelectionChanged: (s) {
              setState(() => _manualMode = s.first);
              if (!s.first) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocusNode.requestFocus();
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _gramsController,
            decoration: const InputDecoration(labelText: 'Вес (г)'),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
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
              decoration: const InputDecoration(
                labelText: 'Калории (ккал)',
                helperText: 'На всю порцию, не на 100 г',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _proteinController,
              decoration: const InputDecoration(
                labelText: 'Белки (г)',
                helperText: 'На всю порцию',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fatController,
              decoration: const InputDecoration(
                labelText: 'Жиры (г)',
                helperText: 'На всю порцию',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _carbsController,
              decoration: const InputDecoration(
                labelText: 'Углеводы (г)',
                helperText: 'На всю порцию',
              ),
              keyboardType: TextInputType.number,
            ),
          ] else ...[
            if (!kIsWeb) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lookupBusy ? null : _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Штрихкод'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lookupBusy ? null : _showPhotoOptions,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Фото'),
                    ),
                  ),
                ],
              ),
              if (_lookupBusy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                const Text(
                  'ИИ анализирует продукт… До 2 минут',
                  style: TextStyle(fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    controller: _searchController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    enableInteractiveSelection: true,
                    decoration: const InputDecoration(
                      labelText: 'Поиск продукта',
                      hintText: 'омлет, гречка...',
                      helperText:
                          'Эмулятор: экранная клав. → глобус → Русский. Или латиницей: omlet, grechka',
                      suffixIcon: Icon(Icons.keyboard),
                    ),
                    onTap: () => _searchFocusNode.requestFocus(),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['омлет', 'гречка', 'творог', 'курица'].map((sample) {
                return ActionChip(
                  label: Text(sample),
                  onPressed: () {
                    _searchController.text = sample;
                    _searchFocusNode.requestFocus();
                    _search();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            ..._results.map(
              (r) => ListTile(
                title: Text(r.name),
                subtitle: Text(
                  [
                    formatMacrosPer100(
                      kcal: r.kcalPer100g,
                      protein: r.proteinPer100g,
                      fat: r.fatPer100g,
                      carbs: r.carbsPer100g,
                    ),
                    if (r.brand != null) r.brand!,
                    if (r.notes != null && r.notes!.isNotEmpty) r.notes!,
                    if (r.source == 'ai_vision' && r.confidence != null)
                      'уверенность ${(r.confidence! * 100).round()}%',
                  ].join(' · '),
                ),
                selected: _selected?.name == r.name,
                onTap: () => _selectResult(r),
              ),
            ),
            if (_previewMacros != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'На ${_gramsController.text} г: ${formatMacrosTotal(_previewMacros!)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
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
