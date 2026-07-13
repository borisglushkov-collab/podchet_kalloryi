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

  String formatLookupError(Object error) => formatApiError(error);
}
