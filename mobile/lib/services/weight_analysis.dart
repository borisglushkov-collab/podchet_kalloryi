import '../models/models.dart';

/// Анализ динамики веса для рекомендаций коуча.
class WeightAnalysis {
  final double currentKg;
  final double startKg;
  final double? targetKg;
  final Goal goal;
  final int entryCount;
  final int? daysSinceLast;
  final double? change7d;
  final double? change30d;
  final String trend; // losing, gaining, stable, plateau, unknown
  final double? remainingKg;
  final List<Map<String, dynamic>> recentEntries;

  const WeightAnalysis({
    required this.currentKg,
    required this.startKg,
    this.targetKg,
    required this.goal,
    required this.entryCount,
    this.daysSinceLast,
    this.change7d,
    this.change30d,
    required this.trend,
    this.remainingKg,
    this.recentEntries = const [],
  });

  bool get hasData => entryCount > 0;

  Map<String, dynamic> toApiJson() => {
        'current_kg': currentKg,
        'start_kg': startKg,
        'target_kg': targetKg,
        'goal': goal.name,
        'entry_count': entryCount,
        'days_since_last': daysSinceLast,
        'change_7d_kg': change7d,
        'change_30d_kg': change30d,
        'trend': trend,
        'remaining_kg': remainingKg,
        'recent_entries': recentEntries,
      };

  static WeightAnalysis fromProfileAndEntries(
    UserProfile profile,
    List<WeightEntry> entries,
  ) {
    if (entries.isEmpty) {
      final target = profile.targetWeightKg ?? _defaultTarget(profile);
      return WeightAnalysis(
        currentKg: profile.weightKg,
        startKg: profile.weightKg,
        targetKg: target,
        goal: profile.goal,
        entryCount: 0,
        trend: 'unknown',
        remainingKg: (profile.weightKg - target).abs(),
      );
    }

    final sorted = List<WeightEntry>.from(entries)
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    final current = sorted.last.weightKg;
    final start = sorted.first.weightKg;
    final target = profile.targetWeightKg ?? _defaultTarget(profile);
    final now = DateTime.now();
    final daysSince = now.difference(sorted.last.recordedAt).inDays;

    final change7d = _changeOverDays(sorted, 7);
    final change30d = _changeOverDays(sorted, 30);
    final trend = _detectTrend(sorted, profile.goal, change7d, change30d);

    final recent = sorted.length <= 8
        ? sorted
        : sorted.sublist(sorted.length - 8);
    final recentJson = recent
        .map((e) => {
              'date': e.date,
              'weight_kg': e.weightKg,
            })
        .toList();

    return WeightAnalysis(
      currentKg: current,
      startKg: start,
      targetKg: target,
      goal: profile.goal,
      entryCount: sorted.length,
      daysSinceLast: daysSince,
      change7d: change7d,
      change30d: change30d,
      trend: trend,
      remainingKg: (current - target).abs(),
      recentEntries: recentJson,
    );
  }

  static double _defaultTarget(UserProfile profile) {
    switch (profile.goal) {
      case Goal.lose:
        return profile.weightKg * 0.9;
      case Goal.gain:
        return profile.weightKg * 1.1;
      case Goal.maintain:
        return profile.weightKg;
    }
  }

  static double? _changeOverDays(List<WeightEntry> sorted, int days) {
    if (sorted.length < 2) return null;
    final latest = sorted.last;
    final cutoff = latest.recordedAt.subtract(Duration(days: days));
    WeightEntry? anchor;
    for (final e in sorted) {
      if (!e.recordedAt.isAfter(cutoff)) anchor = e;
    }
    anchor ??= sorted.first;
    if (anchor.id == latest.id) return null;
    return latest.weightKg - anchor.weightKg;
  }

  static String _detectTrend(
    List<WeightEntry> sorted,
    Goal goal,
    double? change7d,
    double? change30d,
  ) {
    if (sorted.length < 2) return 'unknown';

    final delta = change7d ?? change30d ?? (sorted.last.weightKg - sorted.first.weightKg);
    if (delta.abs() < 0.15) {
      if (sorted.length >= 3) return 'plateau';
      return 'stable';
    }
    if (delta < -0.15) return 'losing';
    if (delta > 0.15) return 'gaining';
    return 'stable';
  }

  /// Краткий текст для офлайн-режима коуча.
  String offlineInsight() {
    if (!hasData) {
      return 'Записей веса пока нет. Взвесьтесь в профиле — коуч сможет учитывать динамику.';
    }

    final parts = <String>[];
    parts.add('Текущий вес ${currentKg.toStringAsFixed(1)} кг');

    if (change7d != null) {
      final sign = change7d! >= 0 ? '+' : '';
      parts.add('за 7 дней: $sign${change7d!.toStringAsFixed(1)} кг');
    }

    switch (trend) {
      case 'losing':
        parts.add('тренд: снижение');
      case 'gaining':
        parts.add('тренд: набор');
      case 'plateau':
        parts.add('тренд: плато');
      case 'stable':
        parts.add('тренд: стабильно');
      default:
        break;
    }

    if (targetKg != null && remainingKg != null) {
      parts.add('до цели ${targetKg!.toStringAsFixed(1)} кг осталось ${remainingKg!.toStringAsFixed(1)} кг');
    }

    return parts.join(' · ');
  }

  /// Продукты для офлайн-режима с учётом динамики веса.
  List<ProductSuggestion> offlineProducts() {
    if (!hasData) return const [];

    final products = <ProductSuggestion>[];

    if (goal == Goal.lose) {
      if (trend == 'gaining' || (change7d != null && change7d! > 0.2)) {
        products.addAll(const [
          ProductSuggestion(
            name: 'Творог 0-2%',
            store: 'Перекрёсток',
            reason: 'Вес растёт — лёгкий белок без лишних калорий',
            url: '',
          ),
          ProductSuggestion(
            name: 'Огурцы / салат',
            store: 'Перекрёсток',
            reason: 'Объёмная еда с минимумом калорий',
            url: '',
          ),
        ]);
      } else if (trend == 'plateau' || trend == 'stable') {
        products.addAll(const [
          ProductSuggestion(
            name: 'Куриная грудка',
            store: 'Перекрёсток',
            reason: 'Плато — добавьте белок для ускорения метаболизма',
            url: '',
          ),
          ProductSuggestion(
            name: 'Гречка',
            store: 'Перекрёсток',
            reason: 'Сложные углеводы и клетчатка при стабильном весе',
            url: '',
          ),
        ]);
      } else {
        products.add(const ProductSuggestion(
          name: 'Яйца',
          store: 'Перекрёсток',
          reason: 'Хороший темп снижения — поддержите белком',
          url: '',
        ));
      }
    } else if (goal == Goal.gain) {
      products.addAll(const [
        ProductSuggestion(
          name: 'Греческий йогурт',
          store: 'Перекрёсток',
          reason: 'Калорийный перекус с белком для набора',
          url: '',
        ),
        ProductSuggestion(
          name: 'Орехи (миндаль)',
          store: 'Перекрёсток',
          reason: 'Плотные калории и полезные жиры',
          url: '',
        ),
      ]);
    }

    return products;
  }
}
