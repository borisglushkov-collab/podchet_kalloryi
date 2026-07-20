import '../models/models.dart';
import 'weight_analysis.dart';

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
    final custom = profile.customDailyTargets;
    if (custom != null) return custom;

    final calories = targetCalories(profile);
    final protein = profile.weightKg * 1.8;
    final fat = calories * 0.25 / 9;
    final carbs = carbsFromMacros(calories, protein, fat);
    return Macros(
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs.clamp(50, double.infinity),
    );
  }

  static double carbsFromMacros(double calories, double protein, double fat) {
    return ((calories - protein * 4 - fat * 9) / 4).clamp(0, double.infinity);
  }

  static double mealShare(MealType meal) {
    switch (meal) {
      case MealType.breakfast:
        return 0.25;
      case MealType.lunch:
        return 0.35;
      case MealType.dinner:
        return 0.30;
      case MealType.snack:
        return 0.10;
    }
  }

  static String mealShareLabel(MealType meal) =>
      '${(mealShare(meal) * 100).round()}% дневной нормы';

  /// Meal target must never exceed what remains for the whole day.
  static Macros capByDaily(Macros mealDeficit, Macros dailyDeficit) => Macros(
        calories: mealDeficit.calories < dailyDeficit.calories
            ? mealDeficit.calories
            : dailyDeficit.calories,
        protein: mealDeficit.protein < dailyDeficit.protein
            ? mealDeficit.protein
            : dailyDeficit.protein,
        fat: mealDeficit.fat < dailyDeficit.fat
            ? mealDeficit.fat
            : dailyDeficit.fat,
        carbs: mealDeficit.carbs < dailyDeficit.carbs
            ? mealDeficit.carbs
            : dailyDeficit.carbs,
      );

  static Macros mealTargets(Macros daily, MealType meal) {
    final share = mealShare(meal);
    return Macros(
      calories: daily.calories * share,
      protein: daily.protein * share,
      fat: daily.fat * share,
      carbs: daily.carbs * share,
    );
  }

  static Macros consumedForMeal(List<FoodEntry> entries, MealType meal) {
    var total = const Macros();
    for (final entry in entries.where((e) => e.mealType == meal)) {
      total = total +
          Macros(
            calories: entry.calories,
            protein: entry.protein,
            fat: entry.fat,
            carbs: entry.carbs,
          );
    }
    return total;
  }

  static Macros mealDeficit({
    required Macros dailyTargets,
    required Macros mealConsumed,
    required MealType meal,
  }) {
    final targets = mealTargets(dailyTargets, meal);
    return Macros(
      calories: (targets.calories - mealConsumed.calories).clamp(0, double.infinity),
      protein: (targets.protein - mealConsumed.protein).clamp(0, double.infinity),
      fat: (targets.fat - mealConsumed.fat).clamp(0, double.infinity),
      carbs: (targets.carbs - mealConsumed.carbs).clamp(0, double.infinity),
    );
  }

  static Map<MealType, Macros> consumedByMeal(List<FoodEntry> entries) {
    return {
      for (final meal in MealType.values)
        meal: consumedForMeal(entries, meal),
    };
  }

  /// Serialize today's diary for coach / suggest-meal (names + BJU).
  static List<Map<String, dynamic>> diaryEntriesForApi(
    List<FoodEntry> entries, {
    int limit = 25,
  }) {
    return entries.take(limit).map((e) => e.toDiaryApiJson()).toList();
  }

  static Map<MealType, MealPlanInfo> computeMealPlan(
    Macros dailyTargets,
    Map<MealType, Macros> mealsConsumed,
  ) {
    var rollover = const Macros();
    final plan = <MealType, MealPlanInfo>{};

    for (var index = 0; index < MealType.values.length; index++) {
      final meal = MealType.values[index];
      final base = mealTargets(dailyTargets, meal);
      final consumed = mealsConsumed[meal] ?? const Macros();
      final effective = base + rollover;
      final deficit = Macros(
        calories: (effective.calories - consumed.calories).clamp(0, double.infinity),
        protein: (effective.protein - consumed.protein).clamp(0, double.infinity),
        fat: (effective.fat - consumed.fat).clamp(0, double.infinity),
        carbs: (effective.carbs - consumed.carbs).clamp(0, double.infinity),
      );
      plan[meal] = MealPlanInfo(
        baseTarget: base,
        rolloverIn: rollover,
        effectiveTarget: effective,
        consumed: consumed,
        deficit: deficit,
        isLastMeal: index == MealType.values.length - 1,
      );
      rollover = deficit;
    }

    return plan;
  }

  static String formatMealProgress(MealPlanInfo plan) {
    final consumed = plan.consumed.calories;
    final target = plan.effectiveTarget.calories;
    var text =
        '${consumed.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} ккал';
    if (plan.rolloverIn.calories > 0) {
      text +=
          ' (+${plan.rolloverIn.calories.toStringAsFixed(0)} перенос)';
    }
    if (plan.isLastMeal && plan.deficit.calories > 0) {
      text += ' · добить день';
    }
    return text;
  }

  /// Базовые рекомендации без ИИ, когда backend недоступен.
  static MealSuggestion offlineMealSuggestion({
    required MealType mealType,
    required Macros consumed,
    required Macros targets,
    required Map<MealType, Macros> mealsConsumed,
    UserProfile? profile,
    WeightAnalysis? weightAnalysis,
  }) {
    final plan = computeMealPlan(targets, mealsConsumed)[mealType]!;
    final dailyDeficit = Macros(
      calories: (targets.calories - consumed.calories).clamp(0, double.infinity),
      protein: (targets.protein - consumed.protein).clamp(0, double.infinity),
      fat: (targets.fat - consumed.fat).clamp(0, double.infinity),
      carbs: (targets.carbs - consumed.carbs).clamp(0, double.infinity),
    );
    final deficit = capByDaily(plan.deficit, dailyDeficit);
    final priorities = <String>[];
    if (deficit.protein >= 10) priorities.add('белок');
    if (deficit.calories >= 100) priorities.add('калории');
    if (deficit.carbs >= 15) priorities.add('углеводы');
    if (deficit.fat >= 5) priorities.add('жиры');

    var summary = 'ИИ временно недоступен. ';
    if (deficit.calories <= 0) {
      summary += 'Норма на ${mealType.label.toLowerCase()} уже закрыта '
          '(или дневной остаток исчерпан).';
    } else {
      summary +=
          'Добавьте ~${deficit.calories.toStringAsFixed(0)} ккал '
          'в ${mealType.label.toLowerCase()}';
      if (priorities.isNotEmpty) {
        summary += ', упор на ${priorities.first}';
      }
      summary += ' — не больше остатка за день.';
    }
    if (profile != null) {
      summary += ' ${_offlineGoalPracticeNote(profile)}';
    }

    final weightInsight = [
      if (profile != null) _offlineProfileNote(profile),
      if (weightAnalysis != null) weightAnalysis.offlineInsight(),
    ].where((s) => s.isNotEmpty).join(' · ');

    final products = <ProductSuggestion>[];
    final seen = <String>{};
    void addProducts(List<ProductSuggestion> items) {
      for (final item in items) {
        final key = item.name.toLowerCase();
        if (seen.add(key)) products.add(item);
      }
    }
    if (profile != null) addProducts(_offlineProfileProducts(profile));
    if (weightAnalysis != null) addProducts(weightAnalysis.offlineProducts());

    return MealSuggestion(
      deficit: deficit,
      dailyDeficit: dailyDeficit,
      effectiveTarget: plan.effectiveTarget,
      rolloverIn: plan.rolloverIn,
      topUpSummary: summary,
      priorityMacros: priorities,
      weightInsight: weightInsight,
      disclaimer: 'Расчёт по вашей норме КБЖУ и динамике веса без ИИ. Рецепты появятся, когда сервер восстановится.',
      recipes: const [],
      products: products,
    );
  }

  static String _offlineGoalPracticeNote(UserProfile profile) {
    switch (profile.goal) {
      case Goal.lose:
        return 'Для похудения: белок, клетчатка, контроль порций — без экстремальных ограничений.';
      case Goal.maintain:
        return 'Для поддержания: стабильные калории, белок и клетчатка в каждом приёме.';
      case Goal.gain:
        return 'Для набора: калорийные перекусы с белком и сложными углеводами.';
    }
  }

  static List<ProductSuggestion> _offlineProfileProducts(UserProfile profile) {
    switch (profile.goal) {
      case Goal.lose:
        return const [
          ProductSuggestion(
            name: 'Творог 0-2%',
            store: 'Перекрёсток',
            reason: 'Цель похудение: белок и сытость без лишних калорий',
            url: '',
          ),
          ProductSuggestion(
            name: 'Овощной салат',
            store: 'Перекрёсток',
            reason: 'Цель похудение: клетчатка и объём, контроль порций',
            url: '',
          ),
        ];
      case Goal.maintain:
        return const [
          ProductSuggestion(
            name: 'Гречка',
            store: 'Перекрёсток',
            reason: 'Цель поддержание: сложные углеводы и клетчатка',
            url: '',
          ),
          ProductSuggestion(
            name: 'Куриная грудка',
            store: 'Перекрёсток',
            reason: 'Цель поддержание: стабильный белок в рационе',
            url: '',
          ),
        ];
      case Goal.gain:
        return const [
          ProductSuggestion(
            name: 'Греческий йогурт',
            store: 'Перекрёсток',
            reason: 'Цель набор: калории и белок для роста массы',
            url: '',
          ),
          ProductSuggestion(
            name: 'Орехи (миндаль)',
            store: 'Перекрёсток',
            reason: 'Цель набор: плотные калории и полезные жиры',
            url: '',
          ),
        ];
    }
  }

  static String _offlineProfileNote(UserProfile profile) {
    final gender = profile.gender == Gender.male ? 'мужчина' : 'женщина';
    final activity = switch (profile.activity) {
      ActivityLevel.sedentary => 'низкая активность',
      ActivityLevel.light => 'лёгкая активность',
      ActivityLevel.moderate => 'умеренная активность',
      ActivityLevel.active => 'высокая активность',
      ActivityLevel.veryActive => 'очень высокая активность',
    };
    final goal = switch (profile.goal) {
      Goal.lose => 'похудение',
      Goal.maintain => 'поддержание',
      Goal.gain => 'набор',
    };
    var note = '$gender, ${profile.age} лет, $activity, цель: $goal';
    if (profile.age >= 50) {
      note += ' — больше белка и клетчатки';
    }
    return note;
  }
}

class MealPlanInfo {
  final Macros baseTarget;
  final Macros rolloverIn;
  final Macros effectiveTarget;
  final Macros consumed;
  final Macros deficit;
  final bool isLastMeal;

  const MealPlanInfo({
    required this.baseTarget,
    required this.rolloverIn,
    required this.effectiveTarget,
    required this.consumed,
    required this.deficit,
    required this.isLastMeal,
  });

  bool get hasRollover =>
      rolloverIn.calories > 0 ||
      rolloverIn.protein > 0 ||
      rolloverIn.fat > 0 ||
      rolloverIn.carbs > 0;
}
