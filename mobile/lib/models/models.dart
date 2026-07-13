class Macros {
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const Macros({
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
  });

  Macros operator +(Macros other) => Macros(
        calories: calories + other.calories,
        protein: protein + other.protein,
        fat: fat + other.fat,
        carbs: carbs + other.carbs,
      );

  Macros operator *(double factor) => Macros(
        calories: calories * factor,
        protein: protein * factor,
        fat: fat * factor,
        carbs: carbs * factor,
      );

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
      };

  factory Macros.fromJson(Map<String, dynamic> json) => Macros(
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      );
}

enum Gender { male, female }

enum ActivityLevel {
  sedentary,
  light,
  moderate,
  active,
  veryActive,
}

enum Goal { lose, maintain, gain }

enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeExt on MealType {
  String get label {
    switch (this) {
      case MealType.breakfast:
        return 'Завтрак';
      case MealType.lunch:
        return 'Обед';
      case MealType.dinner:
        return 'Ужин';
      case MealType.snack:
        return 'Перекус';
    }
  }

  String get apiValue {
    switch (this) {
      case MealType.breakfast:
        return 'breakfast';
      case MealType.lunch:
        return 'lunch';
      case MealType.dinner:
        return 'dinner';
      case MealType.snack:
        return 'snack';
    }
  }

  static MealType fromString(String value) {
    switch (value) {
      case 'breakfast':
        return MealType.breakfast;
      case 'lunch':
        return MealType.lunch;
      case 'dinner':
        return MealType.dinner;
      default:
        return MealType.snack;
    }
  }
}

class UserProfile {
  final int? id;
  final Gender gender;
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activity;
  final Goal goal;
  final String preferences;
  final bool useCustomTargets;
  final double? targetCalories;
  final double? targetProtein;
  final double? targetFat;
  final double? targetCarbs;
  final double? targetWeightKg;

  const UserProfile({
    this.id,
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
    this.preferences = '',
    this.useCustomTargets = false,
    this.targetCalories,
    this.targetProtein,
    this.targetFat,
    this.targetCarbs,
    this.targetWeightKg,
  });

  Macros? get customDailyTargets {
    if (!useCustomTargets) return null;
    final kcal = targetCalories;
    final protein = targetProtein;
    final fat = targetFat;
    if (kcal == null || protein == null || fat == null) return null;
    final carbs = targetCarbs ?? ((kcal - protein * 4 - fat * 9) / 4).clamp(0, double.infinity);
    return Macros(
      calories: kcal,
      protein: protein,
      fat: fat,
      carbs: carbs,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'gender': gender.name,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity': activity.name,
        'goal': goal.name,
        'preferences': preferences,
        'use_custom_targets': useCustomTargets ? 1 : 0,
        'target_calories': targetCalories,
        'target_protein': targetProtein,
        'target_fat': targetFat,
        'target_carbs': targetCarbs,
        'target_weight_kg': targetWeightKg,
      };

  /// Профиль для коуча / API (возраст, пол, активность и т.д.).
  Map<String, dynamic> toCoachApiJson() => {
        'gender': gender.name,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity': activity.name,
        'goal': goal.name,
        'use_custom_targets': useCustomTargets,
        if (targetWeightKg != null) 'target_weight_kg': targetWeightKg,
      };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as int?,
        gender: Gender.values.byName(map['gender'] as String),
        age: map['age'] as int,
        heightCm: (map['height_cm'] as num).toDouble(),
        weightKg: (map['weight_kg'] as num).toDouble(),
        activity: ActivityLevel.values.byName(map['activity'] as String),
        goal: Goal.values.byName(map['goal'] as String),
        preferences: map['preferences'] as String? ?? '',
        useCustomTargets: map['use_custom_targets'] == 1 ||
            map['use_custom_targets'] == true,
        targetCalories: (map['target_calories'] as num?)?.toDouble(),
        targetProtein: (map['target_protein'] as num?)?.toDouble(),
        targetFat: (map['target_fat'] as num?)?.toDouble(),
        targetCarbs: (map['target_carbs'] as num?)?.toDouble(),
        targetWeightKg: (map['target_weight_kg'] as num?)?.toDouble(),
      );

  UserProfile copyWith({
    int? id,
    Gender? gender,
    int? age,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activity,
    Goal? goal,
    String? preferences,
    bool? useCustomTargets,
    double? targetCalories,
    double? targetProtein,
    double? targetFat,
    double? targetCarbs,
    double? targetWeightKg,
  }) =>
      UserProfile(
        id: id ?? this.id,
        gender: gender ?? this.gender,
        age: age ?? this.age,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activity: activity ?? this.activity,
        goal: goal ?? this.goal,
        preferences: preferences ?? this.preferences,
        useCustomTargets: useCustomTargets ?? this.useCustomTargets,
        targetCalories: targetCalories ?? this.targetCalories,
        targetProtein: targetProtein ?? this.targetProtein,
        targetFat: targetFat ?? this.targetFat,
        targetCarbs: targetCarbs ?? this.targetCarbs,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      );
}

enum WeightEntrySource { manual, scale }

class WeightEntry {
  final int? id;
  final String date;
  final DateTime recordedAt;
  final double weightKg;
  final WeightEntrySource source;

  const WeightEntry({
    this.id,
    required this.date,
    required this.recordedAt,
    required this.weightKg,
    this.source = WeightEntrySource.manual,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'recorded_at': recordedAt.toIso8601String(),
        'weight_kg': weightKg,
        'source': source.name,
      };

  factory WeightEntry.fromMap(Map<String, dynamic> map) => WeightEntry(
        id: map['id'] as int?,
        date: map['date'] as String,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        weightKg: (map['weight_kg'] as num).toDouble(),
        source: WeightEntrySource.values.byName(map['source'] as String? ?? 'manual'),
      );
}

class FoodEntry {
  final int? id;
  final String date;
  final MealType mealType;
  final String name;
  final double grams;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const FoodEntry({
    this.id,
    required this.date,
    required this.mealType,
    required this.name,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'meal_type': mealType.apiValue,
        'name': name,
        'grams': grams,
        'calories': calories,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
      };

  factory FoodEntry.fromMap(Map<String, dynamic> map) => FoodEntry(
        id: map['id'] as int?,
        date: map['date'] as String,
        mealType: MealTypeExt.fromString(map['meal_type'] as String),
        name: map['name'] as String,
        grams: (map['grams'] as num).toDouble(),
        calories: (map['calories'] as num).toDouble(),
        protein: (map['protein'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
        carbs: (map['carbs'] as num).toDouble(),
      );
}

class FoodSearchResult {
  final String name;
  final String? brand;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;

  const FoodSearchResult({
    required this.name,
    this.brand,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
  });

  Macros macrosForGrams(double grams) {
    final factor = grams / 100;
    return Macros(
      calories: kcalPer100g * factor,
      protein: proteinPer100g * factor,
      fat: fatPer100g * factor,
      carbs: carbsPer100g * factor,
    );
  }
}

class MealSuggestion {
  final Macros deficit;
  final Macros dailyDeficit;
  final Macros effectiveTarget;
  final Macros rolloverIn;
  final String topUpSummary;
  final List<String> priorityMacros;
  final String disclaimer;
  final String weightInsight;
  final List<RecipeSuggestion> recipes;
  final List<ProductSuggestion> products;

  const MealSuggestion({
    required this.deficit,
    required this.dailyDeficit,
    required this.effectiveTarget,
    required this.rolloverIn,
    required this.topUpSummary,
    required this.priorityMacros,
    required this.disclaimer,
    this.weightInsight = '',
    required this.recipes,
    required this.products,
  });

  factory MealSuggestion.fromJson(Map<String, dynamic> json) => MealSuggestion(
        deficit: Macros.fromJson(json['deficit'] as Map<String, dynamic>),
        dailyDeficit: json['daily_deficit'] != null
            ? Macros.fromJson(json['daily_deficit'] as Map<String, dynamic>)
            : Macros.fromJson(json['deficit'] as Map<String, dynamic>),
        effectiveTarget: json['effective_target'] != null
            ? Macros.fromJson(json['effective_target'] as Map<String, dynamic>)
            : Macros.fromJson(json['deficit'] as Map<String, dynamic>),
        rolloverIn: json['rollover_in'] != null
            ? Macros.fromJson(json['rollover_in'] as Map<String, dynamic>)
            : const Macros(),
        topUpSummary: json['top_up_summary'] as String? ?? '',
        priorityMacros: (json['priority_macros'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        disclaimer: json['disclaimer'] as String? ?? '',
        weightInsight: json['weight_insight'] as String? ?? '',
        recipes: (json['recipes'] as List<dynamic>? ?? [])
            .map((e) => RecipeSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        products: (json['products'] as List<dynamic>? ?? [])
            .map((e) => ProductSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RecipeSuggestion {
  final String name;
  final int cookingTimeMin;
  final String difficulty;
  final String whyFits;
  final List<Map<String, String>> ingredients;
  final List<String> steps;
  final Macros nutrition;

  const RecipeSuggestion({
    required this.name,
    required this.cookingTimeMin,
    required this.difficulty,
    required this.whyFits,
    required this.ingredients,
    required this.steps,
    required this.nutrition,
  });

  factory RecipeSuggestion.fromJson(Map<String, dynamic> json) => RecipeSuggestion(
        name: json['name'] as String? ?? '',
        cookingTimeMin: (json['cooking_time_min'] as num?)?.toInt() ?? 0,
        difficulty: json['difficulty'] as String? ?? '',
        whyFits: json['why_fits'] as String? ?? '',
        ingredients: (json['ingredients'] as List<dynamic>? ?? [])
            .map((e) => Map<String, String>.from(
                  (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
                ))
            .toList(),
        steps: (json['steps'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        nutrition: Macros.fromJson(json['nutrition'] as Map<String, dynamic>? ?? {}),
      );
}

class ProductSuggestion {
  final String name;
  final String store;
  final String reason;
  final int? priceRub;
  final String url;
  final String? imageUrl;

  const ProductSuggestion({
    required this.name,
    required this.store,
    required this.reason,
    this.priceRub,
    required this.url,
    this.imageUrl,
  });

  factory ProductSuggestion.fromJson(Map<String, dynamic> json) => ProductSuggestion(
        name: json['name'] as String? ?? '',
        store: json['store'] as String? ?? 'Перекрёсток',
        reason: json['reason'] as String? ?? '',
        priceRub: (json['price_rub'] as num?)?.toInt(),
        url: json['url'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
      );
}
