import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/nutrition_calculator.dart';
import '../widgets/widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const ProfileScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  Gender _gender = Gender.female;
  ActivityLevel _activity = ActivityLevel.moderate;
  Goal _goal = Goal.maintain;
  final _ageController = TextEditingController(text: '30');
  final _heightController = TextEditingController(text: '170');
  final _weightController = TextEditingController(text: '70');
  final _prefsController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _carbsController = TextEditingController();
  bool _loading = true;
  bool _useCustomTargets = false;
  bool _carbsManual = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AppDatabase.getProfile();
    if (profile != null && mounted) {
      setState(() {
        _gender = profile.gender;
        _activity = profile.activity;
        _goal = profile.goal;
        _ageController.text = profile.age.toString();
        _heightController.text = profile.heightCm.toStringAsFixed(0);
        _weightController.text = profile.weightKg.toStringAsFixed(1);
        _prefsController.text = profile.preferences;
        _useCustomTargets = profile.useCustomTargets;
        if (profile.useCustomTargets && profile.customDailyTargets != null) {
          final t = profile.customDailyTargets!;
          _kcalController.text = t.calories.toStringAsFixed(0);
          _proteinController.text = t.protein.toStringAsFixed(0);
          _fatController.text = t.fat.toStringAsFixed(0);
          _carbsController.text = t.carbs.toStringAsFixed(0);
          _carbsManual = profile.targetCarbs != null;
        } else {
          _fillAutoTargets(profile);
        }
        _loading = false;
      });
    } else if (mounted) {
      _fillAutoTargets(_draftProfile());
      setState(() => _loading = false);
    }
  }

  UserProfile _draftProfile() => UserProfile(
        gender: _gender,
        age: int.tryParse(_ageController.text) ?? 30,
        heightCm: double.tryParse(_heightController.text) ?? 170,
        weightKg: double.tryParse(_weightController.text) ?? 70,
        activity: _activity,
        goal: _goal,
        preferences: _prefsController.text,
      );

  void _fillAutoTargets(UserProfile profile) {
    final targets = NutritionCalculator.dailyTargets(profile);
    _kcalController.text = targets.calories.toStringAsFixed(0);
    _proteinController.text = targets.protein.toStringAsFixed(0);
    _fatController.text = targets.fat.toStringAsFixed(0);
    _carbsController.text = targets.carbs.toStringAsFixed(0);
    _carbsManual = false;
  }

  void _updateCarbsFromMacros() {
    if (_carbsManual) return;
    final kcal = double.tryParse(_kcalController.text);
    final protein = double.tryParse(_proteinController.text);
    final fat = double.tryParse(_fatController.text);
    if (kcal == null || protein == null || fat == null) return;
    _carbsController.text =
        NutritionCalculator.carbsFromMacros(kcal, protein, fat).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _prefsController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    double? targetCarbs;
    if (_useCustomTargets) {
      final kcal = double.parse(_kcalController.text);
      final protein = double.parse(_proteinController.text);
      final fat = double.parse(_fatController.text);
      targetCarbs = _carbsManual
          ? double.parse(_carbsController.text)
          : NutritionCalculator.carbsFromMacros(kcal, protein, fat);
    }

    final profile = UserProfile(
      gender: _gender,
      age: int.parse(_ageController.text),
      heightCm: double.parse(_heightController.text),
      weightKg: double.parse(_weightController.text),
      activity: _activity,
      goal: _goal,
      preferences: _prefsController.text,
      useCustomTargets: _useCustomTargets,
      targetCalories: _useCustomTargets ? double.parse(_kcalController.text) : null,
      targetProtein: _useCustomTargets ? double.parse(_proteinController.text) : null,
      targetFat: _useCustomTargets ? double.parse(_fatController.text) : null,
      targetCarbs: _useCustomTargets ? targetCarbs : null,
    );
    await AppDatabase.saveProfile(profile);
    ref.invalidate(profileProvider);
    ref.invalidate(dailyTargetsProvider);
    ref.invalidate(mealSuggestionProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final previewTargets = _useCustomTargets
        ? Macros(
            calories: double.tryParse(_kcalController.text) ?? 0,
            protein: double.tryParse(_proteinController.text) ?? 0,
            fat: double.tryParse(_fatController.text) ?? 0,
            carbs: double.tryParse(_carbsController.text) ?? 0,
          )
        : NutritionCalculator.dailyTargets(_draftProfile());

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<Gender>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Пол'),
              items: const [
                DropdownMenuItem(value: Gender.male, child: Text('Мужской')),
                DropdownMenuItem(value: Gender.female, child: Text('Женский')),
              ],
              onChanged: (v) => setState(() {
                _gender = v!;
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(labelText: 'Возраст'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || int.tryParse(v) == null ? 'Введите возраст' : null,
              onChanged: (_) {
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Рост (см)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || double.tryParse(v) == null ? 'Введите рост' : null,
              onChanged: (_) {
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(labelText: 'Вес (кг)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || double.tryParse(v) == null ? 'Введите вес' : null,
              onChanged: (_) {
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ActivityLevel>(
              value: _activity,
              decoration: const InputDecoration(labelText: 'Активность'),
              items: const [
                DropdownMenuItem(value: ActivityLevel.sedentary, child: Text('Минимальная')),
                DropdownMenuItem(value: ActivityLevel.light, child: Text('Лёгкая')),
                DropdownMenuItem(value: ActivityLevel.moderate, child: Text('Умеренная')),
                DropdownMenuItem(value: ActivityLevel.active, child: Text('Высокая')),
                DropdownMenuItem(value: ActivityLevel.veryActive, child: Text('Очень высокая')),
              ],
              onChanged: (v) => setState(() {
                _activity = v!;
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Goal>(
              value: _goal,
              decoration: const InputDecoration(labelText: 'Цель'),
              items: const [
                DropdownMenuItem(value: Goal.lose, child: Text('Похудение')),
                DropdownMenuItem(value: Goal.maintain, child: Text('Поддержание')),
                DropdownMenuItem(value: Goal.gain, child: Text('Набор массы')),
              ],
              onChanged: (v) => setState(() {
                _goal = v!;
                if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _prefsController,
              decoration: const InputDecoration(
                labelText: 'Предпочтения (через запятую)',
                hintText: 'без свинины, вегетарианство',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Text('Дневная норма', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Задать КБЖУ вручную'),
              subtitle: const Text('Например: 2000 ккал, 150 г белка, 90 г жира'),
              value: _useCustomTargets,
              onChanged: (v) => setState(() {
                _useCustomTargets = v;
                if (!v) {
                  _fillAutoTargets(_draftProfile());
                }
              }),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _kcalController,
              enabled: _useCustomTargets,
              decoration: const InputDecoration(
                labelText: 'Калории (ккал)',
                suffixText: 'ккал',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (!_useCustomTargets) return null;
                if (v == null || double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Укажите калории';
                }
                return null;
              },
              onChanged: (_) => setState(_updateCarbsFromMacros),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _proteinController,
              enabled: _useCustomTargets,
              decoration: const InputDecoration(
                labelText: 'Белки',
                suffixText: 'г',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (!_useCustomTargets) return null;
                if (v == null || double.tryParse(v) == null || double.parse(v) < 0) {
                  return 'Укажите белки';
                }
                return null;
              },
              onChanged: (_) => setState(_updateCarbsFromMacros),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fatController,
              enabled: _useCustomTargets,
              decoration: const InputDecoration(
                labelText: 'Жиры',
                suffixText: 'г',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (!_useCustomTargets) return null;
                if (v == null || double.tryParse(v) == null || double.parse(v) < 0) {
                  return 'Укажите жиры';
                }
                return null;
              },
              onChanged: (_) => setState(_updateCarbsFromMacros),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _carbsController,
              enabled: _useCustomTargets,
              decoration: InputDecoration(
                labelText: 'Углеводы',
                suffixText: 'г',
                helperText: _useCustomTargets && !_carbsManual
                    ? 'Считаются автоматически из ккал, белков и жиров'
                    : null,
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (!_useCustomTargets) return null;
                if (v == null || double.tryParse(v) == null || double.parse(v) < 0) {
                  return 'Укажите углеводы';
                }
                return null;
              },
              onChanged: (_) {
                if (_useCustomTargets) _carbsManual = true;
              },
            ),
            if (_useCustomTargets) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _carbsManual = false;
                    _updateCarbsFromMacros();
                  }),
                  child: const Text('Пересчитать углеводы автоматически'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Итого: ${formatMacrosTotal(previewTargets)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
