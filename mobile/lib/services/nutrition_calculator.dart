import '../models/models.dart';

class NutritionCalculator {
  static double bmr(UserProfile profile) {
    final w = profile.weightKg;
    final h = profile.heightCm;
    final a = profile.age.toDouble();
    if (profile.gender == Gender.male) {
      return 10 * w + 6.25 * h - 5 * a + 5;
    }
    return 10 * w + 6.25 * h - 5 * a - 161;
  }

  static double activityMultiplier(ActivityLevel level) {
    switch (level) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.light:
        return 1.375;
      case ActivityLevel.moderate:
        return 1.55;
      case ActivityLevel.active:
        return 1.725;
      case ActivityLevel.veryActive:
        return 1.9;
    }
  }

  static double tdee(UserProfile profile) => bmr(profile) * activityMultiplier(profile.activity);

  static double targetCalories(UserProfile profile) {
    final base = tdee(profile);
    switch (profile.goal) {
      case Goal.lose:
        return base - 400;
      case Goal.maintain:
        return base;
      case Goal.gain:
        return base + 300;
    }
  }

  static Macros dailyTargets(UserProfile profile) {
    final calories = targetCalories(profile);
    final protein = profile.weightKg * 1.8;
    final fat = calories * 0.25 / 9;
    final carbs = (calories - protein * 4 - fat * 9) / 4;
    return Macros(
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs.clamp(50, double.infinity),
    );
  }
}
