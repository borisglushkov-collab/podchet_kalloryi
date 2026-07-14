import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/nutrition_calculator.dart';
import '../theme/app_theme.dart';
import '../widgets/health_scale_card.dart';
import 'weight_tracker_screen.dart';

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
  final _targetWeightController = TextEditingController(text: '70');
  final _prefsController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _carbsController = TextEditingController();
  bool _loading = true;
  bool _useCustomTargets = false;
  bool _carbsManual = false;
  bool _showBodyForm = true;
  bool _showPrefs = false;
  bool _showScales = false;

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
        _targetWeightController.text = (profile.targetWeightKg ?? profile.weightKg)
            .toStringAsFixed(1);
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
    _targetWeightController.dispose();
    _prefsController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  Future<void> _applySyncedWeight(double weightKg) async {
    await AppDatabase.logWeight(weightKg, source: WeightEntrySource.scale);
    ref.invalidate(profileProvider);
    ref.invalidate(dailyTargetsProvider);
    ref.invalidate(weightEntriesProvider);
    final profile = await AppDatabase.getProfile();
    if (profile != null && !_useCustomTargets) _fillAutoTargets(profile);
    if (mounted) {
      _weightController.text = weightKg.toStringAsFixed(1);
      setState(() {});
    }
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

    final weightKg = double.parse(_weightController.text);
    final targetWeightKg = double.tryParse(_targetWeightController.text.replaceAll(',', '.'));

    final existing = await AppDatabase.getProfile();
    final profile = UserProfile(
      gender: _gender,
      age: int.parse(_ageController.text),
      heightCm: double.parse(_heightController.text),
      weightKg: weightKg,
      activity: _activity,
      goal: _goal,
      preferences: _prefsController.text,
      useCustomTargets: _useCustomTargets,
      targetCalories: _useCustomTargets ? double.parse(_kcalController.text) : null,
      targetProtein: _useCustomTargets ? double.parse(_proteinController.text) : null,
      targetFat: _useCustomTargets ? double.parse(_fatController.text) : null,
      targetCarbs: _useCustomTargets ? targetCarbs : null,
      targetWeightKg: targetWeightKg,
    );
    await AppDatabase.saveProfile(profile);
    if (existing == null ||
        (existing.weightKg - weightKg).abs() >= 0.05) {
      await AppDatabase.logWeight(weightKg, source: WeightEntrySource.manual);
    }
    ref.invalidate(profileProvider);
    ref.invalidate(dailyTargetsProvider);
    ref.invalidate(weightEntriesProvider);
    ref.invalidate(mealSuggestionProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
      if (!widget.embedded) {
        Navigator.pop(context);
      }
    }
  }

  String _goalChipLabel(double current, double target) {
    final delta = current - target;
    if (delta.abs() < 0.05) return 'цель · достигнута';
    if (delta > 0) {
      return 'цель · −${delta.toStringAsFixed(0)} кг';
    }
    return 'цель · +${(-delta).toStringAsFixed(0)} кг';
  }

  double _progress(double start, double current, double target) {
    final total = (start - target).abs();
    if (total < 0.05) return 1;
    final done = (start - current).abs();
    return (done / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Профиль'),
                backgroundColor: AppColors.background,
              ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
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

    final currentWeight = double.tryParse(_weightController.text.replaceAll(',', '.')) ?? 70;
    final targetWeight =
        double.tryParse(_targetWeightController.text.replaceAll(',', '.')) ?? currentWeight;
    final weightEntries = ref.watch(weightEntriesProvider).valueOrNull ?? const <WeightEntry>[];
    final sorted = List<WeightEntry>.from(weightEntries)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final startWeight = sorted.isNotEmpty ? sorted.first.weightKg : currentWeight;
    final progress = _progress(startWeight, currentWeight, targetWeight);
    final avatarLetter = (_prefsController.text.trim().isNotEmpty
            ? _prefsController.text.trim()[0]
            : (_gender == Gender.female ? 'А' : 'Б'))
        .toUpperCase();
    final prefsPreview = _prefsController.text.trim().isEmpty
        ? 'не указаны'
        : _prefsController.text.trim();

    final bottomPad = widget.embedded
        ? 28.0
        : 28.0 + MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Профиль'),
              backgroundColor: AppColors.background,
            ),
      // Вкладка: без SafeArea (верх уже в MainShell).
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, bottomPad),
          children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Профиль',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  _SoftChip(
                    label: _goalChipLabel(currentWeight, targetWeight),
                    background: AppColors.primary.withValues(alpha: 0.15),
                    foreground: AppColors.primaryDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                color: AppColors.surfaceMuted,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Текущий вес',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${currentWeight.toStringAsFixed(1).replaceAll('.', ',')} кг',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              avatarLetter,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: AppColors.primaryDark,
                              ),
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
                          backgroundColor: Colors.white.withValues(alpha: 0.7),
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'старт ${startWeight.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            'цель ${targetWeight.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Дневная норма',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _NormRow(
                        label: 'Калории',
                        value: previewTargets.calories.toStringAsFixed(0),
                      ),
                      _NormRow(
                        label: 'Белки',
                        value: '${previewTargets.protein.toStringAsFixed(0)} г',
                      ),
                      _NormRow(
                        label: 'Жиры',
                        value: '${previewTargets.fat.toStringAsFixed(0)} г',
                      ),
                      _NormRow(
                        label: 'Углеводы',
                        value: '${previewTargets.carbs.toStringAsFixed(0)} г',
                        last: true,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _SoftChip(
                            label: _useCustomTargets ? 'вручную' : 'авто · Миффлин',
                            background: AppColors.protein.withValues(alpha: 0.12),
                            foreground: AppColors.protein,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() {
                              _useCustomTargets = !_useCustomTargets;
                              if (!_useCustomTargets) {
                                _fillAutoTargets(_draftProfile());
                              }
                            }),
                            child: Text(_useCustomTargets ? 'Авто' : 'Вручную'),
                          ),
                        ],
                      ),
                      if (_useCustomTargets) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _kcalController,
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
                          decoration: InputDecoration(
                            labelText: 'Углеводы',
                            suffixText: 'г',
                            helperText: !_carbsManual
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    _SoftListRow(
                      icon: Icons.bluetooth_searching_outlined,
                      title: 'Умные весы',
                      subtitle: 'Futula / LeFu',
                      onTap: () => setState(() => _showScales = !_showScales),
                      trailing: Icon(
                        _showScales ? Icons.expand_less : Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_showScales)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: HealthScaleCard(
                          weightController: _weightController,
                          onWeightSynced: _applySyncedWeight,
                        ),
                      ),
                    const Divider(height: 1),
                    _SoftListRow(
                      icon: Icons.show_chart,
                      title: 'График веса',
                      subtitle: 'как в FatSecret',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WeightTrackerScreen()),
                      ),
                    ),
                    const Divider(height: 1),
                    _SoftListRow(
                      icon: Icons.restaurant_outlined,
                      title: 'Предпочтения',
                      subtitle: prefsPreview,
                      onTap: () => setState(() => _showPrefs = !_showPrefs),
                      trailing: Icon(
                        _showPrefs ? Icons.expand_less : Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_showPrefs)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: TextFormField(
                          controller: _prefsController,
                          decoration: const InputDecoration(
                            labelText: 'Предпочтения (через запятую)',
                            hintText: 'без свинины, вегетарианство',
                          ),
                          maxLines: 2,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    const Divider(height: 1),
                    _SoftListRow(
                      icon: Icons.tune_outlined,
                      title: 'Параметры тела',
                      subtitle: 'пол, рост, активность, цель',
                      onTap: () => setState(() => _showBodyForm = !_showBodyForm),
                      trailing: Icon(
                        _showBodyForm ? Icons.expand_less : Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showBodyForm) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
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
                          validator: (v) =>
                              v == null || int.tryParse(v) == null ? 'Введите возраст' : null,
                          onChanged: (_) {
                            if (!_useCustomTargets) {
                              setState(() => _fillAutoTargets(_draftProfile()));
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _heightController,
                          decoration: const InputDecoration(labelText: 'Рост (см)'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v == null || double.tryParse(v) == null ? 'Введите рост' : null,
                          onChanged: (_) {
                            if (!_useCustomTargets) {
                              setState(() => _fillAutoTargets(_draftProfile()));
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _weightController,
                          decoration: const InputDecoration(labelText: 'Вес (кг)'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v == null || double.tryParse(v) == null ? 'Введите вес' : null,
                          onChanged: (_) {
                            setState(() {
                              if (!_useCustomTargets) _fillAutoTargets(_draftProfile());
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _targetWeightController,
                          decoration: const InputDecoration(labelText: 'Желаемый вес (кг)'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v == null || double.tryParse(v.replaceAll(',', '.')) == null
                                  ? 'Введите желаемый вес'
                                  : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<ActivityLevel>(
                          value: _activity,
                          decoration: const InputDecoration(labelText: 'Активность'),
                          items: const [
                            DropdownMenuItem(
                              value: ActivityLevel.sedentary,
                              child: Text('Минимальная'),
                            ),
                            DropdownMenuItem(
                              value: ActivityLevel.light,
                              child: Text('Лёгкая'),
                            ),
                            DropdownMenuItem(
                              value: ActivityLevel.moderate,
                              child: Text('Умеренная'),
                            ),
                            DropdownMenuItem(
                              value: ActivityLevel.active,
                              child: Text('Высокая'),
                            ),
                            DropdownMenuItem(
                              value: ActivityLevel.veryActive,
                              child: Text('Очень высокая'),
                            ),
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
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Сохранить'),
                ),
              ),
            ],
          ),
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

class _NormRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const _NormRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SoftListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SoftListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primaryDark, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
    );
  }
}
