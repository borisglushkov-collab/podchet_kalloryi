import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/search_query_utils.dart';
import 'local_food_fallback.dart';
import 'weight_analysis.dart';

class SettingsService {
  static const _backendUrlKey = 'backend_url';
  static const _cityKey = 'city';
  static const defaultBackendUrl = 'http://5.42.111.122';
  static const defaultCity = 'Москва';

  static Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backendUrlKey) ?? defaultBackendUrl;
  }

  static Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, url.trim());
  }

  static Future<String> getCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cityKey) ?? defaultCity;
  }

  static Future<void> setCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, city.trim());
  }
}

class ApiService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 200),
    ),
  );

  Future<bool> checkHealth({String? baseUrl}) async {
    try {
      final url = (baseUrl ?? await SettingsService.getBackendUrl()).trim();
      final response = await _dio.get('$url/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<MealSuggestion> suggestMeal({
    required MealType mealType,
    required Macros consumed,
    required Macros targets,
    required Macros mealConsumed,
    required Map<MealType, Macros> mealsConsumed,
    List<String> preferences = const [],
    String? city,
    WeightAnalysis? weightAnalysis,
  }) async {
    final baseUrl = await SettingsService.getBackendUrl();
    final resolvedCity = city ?? await SettingsService.getCity();
    final response = await _dio.post(
      '$baseUrl/api/suggest-meal',
      data: {
        'meal_type': mealType.apiValue,
        'consumed': consumed.toJson(),
        'targets': targets.toJson(),
        'meal_consumed': mealConsumed.toJson(),
        'meals_consumed': {
          for (final entry in mealsConsumed.entries)
            entry.key.apiValue: entry.value.toJson(),
        },
        'preferences': preferences,
        'city': resolvedCity,
        if (weightAnalysis != null && weightAnalysis.hasData)
          'weight_context': weightAnalysis.toApiJson(),
      },
    );
    return MealSuggestion.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> resetAiSession() async {
    final baseUrl = await SettingsService.getBackendUrl();
    await _dio.post('$baseUrl/api/reset-session');
  }
}

class FoodSearchService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<List<FoodSearchResult>> search(String query) async {
    if (query.trim().length < 2) return [];
    final q = normalizeSearchQuery(query);
    try {
      final baseUrl = await SettingsService.getBackendUrl();
      final response = await _dio.get(
        '$baseUrl/api/search-food',
        queryParameters: {'query': q},
      );
      final items = response.data['items'] as List<dynamic>? ?? [];
      final remote = items.map((raw) {
        final map = raw as Map<String, dynamic>;
        return FoodSearchResult(
          name: map['name'] as String,
          brand: map['brand'] as String?,
          kcalPer100g: _num(map['kcal_per_100g']),
          proteinPer100g: _num(map['protein_per_100g'] ?? map['proteins_per_100g']),
          fatPer100g: _num(map['fat_per_100g']),
          carbsPer100g: _num(map['carbs_per_100g'] ?? map['carbohydrates_per_100g']),
        );
      }).toList();
      return mergeSearchResults(remote: remote, query: q);
    } catch (_) {
      final local = searchLocalFallback(q);
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
