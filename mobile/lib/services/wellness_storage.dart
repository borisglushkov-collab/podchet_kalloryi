import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../models/models.dart';
import 'nutrition_calculator.dart';

class WellnessStorage {
  static const _waterPrefix = 'water_glasses_';
  static const _streakCountKey = 'wellness_streak_count';
  static const _streakLastKey = 'wellness_streak_last_date';
  static const glassesPerLiter = 4;
  static const waterGoalLiters = 2.0;

  static Future<int> getWaterGlasses(String date) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_waterPrefix$date') ?? 0;
  }

  static Future<void> setWaterGlasses(String date, int glasses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_waterPrefix$date', glasses.clamp(0, 8));
  }

  static double litersFromGlasses(int glasses) => glasses / glassesPerLiter;

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakCountKey) ?? 0;
  }

  /// Updates streak when user logs food; call after adding entries.
  static Future<int> refreshStreak(String todayStr) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_streakLastKey);
    var count = prefs.getInt(_streakCountKey) ?? 0;

    if (last == todayStr) {
      return count;
    }

    final hasToday = (await AppDatabase.getEntriesForDate(todayStr)).isNotEmpty;
    if (!hasToday) return count;

    if (last == null) {
      count = 1;
    } else {
      final lastDate = DateTime.parse(last);
      final today = DateTime.parse(todayStr);
      final diff = today.difference(lastDate).inDays;
      if (diff == 1) {
        count += 1;
      } else if (diff > 1) {
        count = 1;
      }
    }

    await prefs.setInt(_streakCountKey, count);
    await prefs.setString(_streakLastKey, todayStr);
    return count;
  }

  static int dayScore({
    required double consumedKcal,
    required double targetKcal,
    required double consumedProtein,
    required double targetProtein,
  }) {
    if (targetKcal <= 0) return 0;
    final kcalPart = (consumedKcal / targetKcal).clamp(0.0, 1.0) * 50;
    final proteinPart = targetProtein > 0
        ? (consumedProtein / targetProtein).clamp(0.0, 1.0) * 50
        : 25;
    return (kcalPart + proteinPart).round().clamp(0, 100);
  }

  static String greetingForHour(int hour) {
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  static String coachTip({
    required double proteinDeficit,
    required double kcalDeficit,
    required String mealLabel,
  }) {
    if (proteinDeficit > 15) {
      return 'До цели осталось ${proteinDeficit.toStringAsFixed(0)} г белка. '
          'Попробуй белковое блюдо на $mealLabel.';
    }
    if (kcalDeficit > 50) {
      return 'Осталось ${kcalDeficit.toStringAsFixed(0)} ккал. '
          'Подбери лёгкий $mealLabel в пределах нормы.';
    }
    return 'Отличный темп! Загляни в коуч за идеями на $mealLabel.';
  }

  static MealType? nextMealWithDeficit(Map<MealType, MealPlanInfo> plan) {
    for (final meal in MealType.values) {
      final info = plan[meal];
      if (info != null && info.deficit.calories > 20) return meal;
    }
    return null;
  }
}
