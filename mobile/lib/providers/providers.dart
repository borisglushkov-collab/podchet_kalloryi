import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/nutrition_calculator.dart';

final apiServiceProvider = Provider((ref) => ApiService());
final offServiceProvider = Provider((ref) => OpenFoodFactsService());

final profileProvider = FutureProvider<UserProfile?>((ref) async {
  return AppDatabase.getProfile();
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

final dailyEntriesProvider = FutureProvider.family<List<FoodEntry>, String>((ref, date) async {
  return AppDatabase.getEntriesForDate(date);
});

final dailyTotalsProvider = FutureProvider.family<Macros, String>((ref, date) async {
  return AppDatabase.getDailyTotals(date);
});

final dailyTargetsProvider = FutureProvider<Macros?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return null;
  return NutritionCalculator.dailyTargets(profile);
});

final backendHealthProvider = FutureProvider<bool>((ref) async {
  return ref.read(apiServiceProvider).checkHealth();
});

final mealSuggestionProvider =
    FutureProvider.family<MealSuggestion, MealType>((ref, mealType) async {
  final date = formatDate(ref.watch(selectedDateProvider));
  final profile = await ref.watch(profileProvider.future);
  final targets = await ref.watch(dailyTargetsProvider.future);
  final consumed = await ref.watch(dailyTotalsProvider(date).future);
  if (profile == null || targets == null) {
    throw Exception('Заполните профиль');
  }
  final prefs = profile.preferences
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return ref.read(apiServiceProvider).suggestMeal(
        mealType: mealType,
        consumed: consumed,
        targets: targets,
        preferences: prefs,
      );
});
