import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

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
    List<String> preferences = const [],
    String? city,
  }) async {
    final baseUrl = await SettingsService.getBackendUrl();
    final resolvedCity = city ?? await SettingsService.getCity();
    final response = await _dio.post(
      '$baseUrl/api/suggest-meal',
      data: {
        'meal_type': mealType.apiValue,
        'consumed': consumed.toJson(),
        'targets': targets.toJson(),
        'preferences': preferences,
        'city': resolvedCity,
      },
    );
    return MealSuggestion.fromJson(response.data as Map<String, dynamic>);
  }
}

class OpenFoodFactsService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<List<FoodSearchResult>> search(String query) async {
    if (query.trim().length < 2) return [];
    final baseUrl = await SettingsService.getBackendUrl();
    final response = await _dio.get(
      '$baseUrl/api/search-food',
      queryParameters: {'query': query},
    );
    final items = response.data['items'] as List<dynamic>? ?? [];
    return items.map((raw) {
      final map = raw as Map<String, dynamic>;
      return FoodSearchResult(
        name: map['name'] as String,
        brand: map['brand'] as String?,
        kcalPer100g: (map['kcal_per_100g'] as num).toDouble(),
        proteinPer100g: (map['protein_per_100g'] as num?)?.toDouble() ?? 0,
        fatPer100g: (map['fat_per_100g'] as num?)?.toDouble() ?? 0,
        carbsPer100g: (map['carbs_per_100g'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }
}
