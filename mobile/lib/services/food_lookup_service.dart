import 'package:dio/dio.dart';

import '../models/models.dart';
import '../utils/api_error_utils.dart';
import 'api_service.dart';

class FoodLookupService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  Future<FoodSearchResult> lookupBarcode(String barcode) async {
    final baseUrl = await SettingsService.getBackendUrl();
    final response = await _dio.get(
      '$baseUrl/api/search-barcode',
      queryParameters: {'barcode': barcode},
    );
    final item = response.data['item'] as Map<String, dynamic>;
    return FoodSearchResult.fromApiItem(item);
  }

  Future<FoodSearchResult> analyzePhoto(String filePath) async {
    final baseUrl = await SettingsService.getBackendUrl();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: 'food.jpg'),
    });
    final response = await _dio.post(
      '$baseUrl/api/analyze-food-image',
      data: formData,
    );
    final item = response.data['item'] as Map<String, dynamic>;
    return FoodSearchResult.fromApiItem(item);
  }

  /// AI search result plus optional fallback warning from backend.
  Future<AiFoodSearchOutcome> searchWithAi(String query) async {
    final baseUrl = await SettingsService.getBackendUrl();
    try {
      final response = await _dio.post(
        '$baseUrl/api/ai-search-food',
        data: {'query': query},
        options: Options(receiveTimeout: const Duration(seconds: 180)),
      );
      final items = response.data['items'] as List<dynamic>? ?? [];
      final source = response.data['source']?.toString() ?? 'ai_search';
      final warning = response.data['warning']?.toString();
      return AiFoodSearchOutcome(
        items: items
            .map((raw) => FoodSearchResult.fromApiItem(raw as Map<String, dynamic>))
            .toList(),
        source: source,
        warning: warning,
      );
    } catch (e) {
      // Client-side fallback if backend is old or AI hard-fails.
      try {
        final base = await SettingsService.getBackendUrl();
        final response = await _dio.get(
          '$base/api/search-food',
          queryParameters: {'query': query},
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        final items = response.data['items'] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          return AiFoodSearchOutcome(
            items: items
                .map((raw) => FoodSearchResult.fromApiItem(raw as Map<String, dynamic>))
                .toList(),
            source: 'fallback_client',
            warning:
                'ИИ недоступен — показаны результаты обычного поиска. '
                '${formatApiError(e)}',
          );
        }
      } catch (_) {}
      rethrow;
    }
  }

  String formatLookupError(Object error) => formatApiError(error);
}

class AiFoodSearchOutcome {
  final List<FoodSearchResult> items;
  final String source;
  final String? warning;

  const AiFoodSearchOutcome({
    required this.items,
    required this.source,
    this.warning,
  });

  bool get usedFallback => source.startsWith('fallback');
}
