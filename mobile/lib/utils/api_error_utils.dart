import 'package:dio/dio.dart';

/// Человекочитаемое сообщение об ошибке API вместо сырого DioException.
String formatApiError(Object error) {
  if (error is DioException) {
    final detail = _extractDetail(error);
    if (detail != null && detail.isNotEmpty) {
      return _localizeDetail(detail);
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Сервер не ответил вовремя. Проверьте интернет и попробуйте снова.';
      case DioExceptionType.connectionError:
        return 'Не удалось подключиться к серверу. Проверьте интернет или адрес backend в настройках.';
      default:
        final code = error.response?.statusCode;
        if (code == 502 || code == 503) {
          return 'Сервис ИИ временно недоступен. Подождите минуту и нажмите «Повторить».';
        }
        if (code == 429) {
          return 'Слишком много запросов к ИИ. Попробуйте через минуту.';
        }
    }
  }
  final text = error.toString();
  if (text.contains('502')) {
    return 'Сервис ИИ временно недоступен (ошибка 502). Попробуйте позже.';
  }
  if (text.contains('409') || text.contains('busy')) {
    return 'ИИ-агент занят другим запросом. Нажмите «Сбросить сессию» и повторите.';
  }
  return 'Не удалось получить рекомендации. Проверьте интернет и backend-сервер.';
}

String? _extractDetail(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      return detail.first.toString();
    }
  }
  if (data is String && data.isNotEmpty) return data;
  return null;
}

String _localizeDetail(String detail) {
  if (detail.contains('agent is busy') || detail.contains('409')) {
    return 'ИИ-агент занят. Подождите 10–20 секунд, нажмите «Сбросить сессию» или «Повторить».';
  }
  if (detail.contains('CURSOR_API_KEY')) {
    return 'На сервере не настроен ключ Cursor API. Обратитесь к администратору.';
  }
  if (detail.startsWith('Ошибка ИИ:')) {
    return detail.replaceFirst('Ошибка ИИ:', 'Ошибка ИИ:').trim();
  }
  if (detail.startsWith('Ошибка')) return detail;
  return detail;
}

bool isAiBusyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('409') || text.contains('busy') || text.contains('занят')) {
    return true;
  }
  if (error is DioException) {
    final detail = _extractDetail(error)?.toLowerCase() ?? '';
    return detail.contains('409') || detail.contains('busy') || detail.contains('занят');
  }
  return false;
}
