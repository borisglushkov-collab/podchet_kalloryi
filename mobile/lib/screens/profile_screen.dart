import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/health_scale_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

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
  bool _loading = true;

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
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _prefsController.dispose();
    super.dispose();
  }

  Future<void> _applySyncedWeight(double weightKg) async {
    final profile = await AppDatabase.getProfile();
    if (profile == null) return;

    final updated = profile.copyWith(weightKg: weightKg);
    await AppDatabase.saveProfile(updated);
    ref.invalidate(profileProvider);
    ref.invalidate(dailyTargetsProvider);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = UserProfile(
      gender: _gender,
      age: int.parse(_ageController.text),
      heightCm: double.parse(_heightController.text),
      weightKg: double.parse(_weightController.text),
      activity: _activity,
      goal: _goal,
      preferences: _prefsController.text,
    );
    await AppDatabase.saveProfile(profile);
    ref.invalidate(profileProvider);
    ref.invalidate(dailyTargetsProvider);
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
              onChanged: (v) => setState(() => _gender = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(labelText: 'Возраст'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || int.tryParse(v) == null ? 'Введите возраст' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Рост (см)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || double.tryParse(v) == null ? 'Введите рост' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(labelText: 'Вес (кг)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || double.tryParse(v) == null ? 'Введите вес' : null,
            ),
            const SizedBox(height: 16),
            HealthScaleCard(
              weightController: _weightController,
              onWeightSynced: _applySyncedWeight,
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
              onChanged: (v) => setState(() => _activity = v!),
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
              onChanged: (v) => setState(() => _goal = v!),
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
