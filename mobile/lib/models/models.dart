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

  const UserProfile({
    this.id,
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
    this.preferences = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'gender': gender.name,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'activity': activity.name,
        'goal': goal.name,
        'preferences': preferences,
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
  final String disclaimer;
  final List<RecipeSuggestion> recipes;
  final List<ProductSuggestion> products;

  const MealSuggestion({
    required this.deficit,
    required this.disclaimer,
    required this.recipes,
    required this.products,
  });

  factory MealSuggestion.fromJson(Map<String, dynamic> json) => MealSuggestion(
        deficit: Macros.fromJson(json['deficit'] as Map<String, dynamic>),
        disclaimer: json['disclaimer'] as String? ?? '',
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
  final List<Map<String, String>> ingredients;
  final List<String> steps;
  final Macros nutrition;

  const RecipeSuggestion({
    required this.name,
    required this.cookingTimeMin,
    required this.difficulty,
    required this.ingredients,
    required this.steps,
    required this.nutrition,
  });

  factory RecipeSuggestion.fromJson(Map<String, dynamic> json) => RecipeSuggestion(
        name: json['name'] as String? ?? '',
        cookingTimeMin: (json['cooking_time_min'] as num?)?.toInt() ?? 0,
        difficulty: json['difficulty'] as String? ?? '',
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
