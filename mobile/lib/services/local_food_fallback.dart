import '../models/models.dart';

/// Offline fallback when backend search is slow or unavailable.
const List<FoodSearchResult> kLocalFoodFallback = [
  FoodSearchResult(name: 'Омлет', kcalPer100g: 154, proteinPer100g: 10.6, fatPer100g: 11.7, carbsPer100g: 1.2),
  FoodSearchResult(name: 'Яйцо куриное', kcalPer100g: 157, proteinPer100g: 12.7, fatPer100g: 11.5, carbsPer100g: 0.7),
  FoodSearchResult(name: 'Яичница', kcalPer100g: 196, proteinPer100g: 13.6, fatPer100g: 15.3, carbsPer100g: 0.9),
  FoodSearchResult(name: 'Овсянка на воде', kcalPer100g: 68, proteinPer100g: 2.4, fatPer100g: 1.4, carbsPer100g: 12.0),
  FoodSearchResult(name: 'Овсянка на молоке', kcalPer100g: 102, proteinPer100g: 3.2, fatPer100g: 4.1, carbsPer100g: 14.2),
  FoodSearchResult(name: 'Гречка варёная', kcalPer100g: 101, proteinPer100g: 4.2, fatPer100g: 1.1, carbsPer100g: 18.6),
  FoodSearchResult(name: 'Рис варёный', kcalPer100g: 116, proteinPer100g: 2.2, fatPer100g: 0.5, carbsPer100g: 24.9),
  FoodSearchResult(name: 'Курица грудка варёная', kcalPer100g: 137, proteinPer100g: 29.8, fatPer100g: 1.8, carbsPer100g: 0.5),
  FoodSearchResult(name: 'Курица грудка жареная', kcalPer100g: 195, proteinPer100g: 28.0, fatPer100g: 8.8, carbsPer100g: 0.0),
  FoodSearchResult(name: 'Творог 5%', kcalPer100g: 121, proteinPer100g: 17.0, fatPer100g: 5.0, carbsPer100g: 1.8),
  FoodSearchResult(name: 'Творог 9%', kcalPer100g: 159, proteinPer100g: 16.7, fatPer100g: 9.0, carbsPer100g: 2.0),
  FoodSearchResult(name: 'Молоко 2.5%', kcalPer100g: 52, proteinPer100g: 2.8, fatPer100g: 2.5, carbsPer100g: 4.7),
  FoodSearchResult(name: 'Банан', kcalPer100g: 96, proteinPer100g: 1.5, fatPer100g: 0.2, carbsPer100g: 21.0),
  FoodSearchResult(name: 'Яблоко', kcalPer100g: 47, proteinPer100g: 0.4, fatPer100g: 0.4, carbsPer100g: 9.8),
  FoodSearchResult(name: 'Хлеб белый', kcalPer100g: 266, proteinPer100g: 7.7, fatPer100g: 3.2, carbsPer100g: 50.1),
  FoodSearchResult(name: 'Хлеб чёрный', kcalPer100g: 201, proteinPer100g: 6.6, fatPer100g: 1.2, carbsPer100g: 40.7),
  FoodSearchResult(name: 'Борщ', kcalPer100g: 49, proteinPer100g: 1.6, fatPer100g: 2.4, carbsPer100g: 5.7),
  FoodSearchResult(name: 'Сырники', kcalPer100g: 220, proteinPer100g: 14.0, fatPer100g: 10.0, carbsPer100g: 18.0),
  FoodSearchResult(name: 'Блины', kcalPer100g: 227, proteinPer100g: 6.1, fatPer100g: 7.8, carbsPer100g: 33.2),
  FoodSearchResult(name: 'Салат овощной', kcalPer100g: 65, proteinPer100g: 1.5, fatPer100g: 4.5, carbsPer100g: 4.5),
  FoodSearchResult(name: 'Греческий йогурт', kcalPer100g: 97, proteinPer100g: 9.0, fatPer100g: 5.0, carbsPer100g: 3.6),
  FoodSearchResult(name: 'Лосось', kcalPer100g: 208, proteinPer100g: 20.0, fatPer100g: 13.0, carbsPer100g: 0.0),
  FoodSearchResult(name: 'Макароны варёные', kcalPer100g: 112, proteinPer100g: 3.5, fatPer100g: 0.4, carbsPer100g: 23.2),
  FoodSearchResult(name: 'Картофель варёный', kcalPer100g: 82, proteinPer100g: 2.0, fatPer100g: 0.4, carbsPer100g: 16.7),
  FoodSearchResult(name: 'Котлета домашняя', kcalPer100g: 220, proteinPer100g: 15.0, fatPer100g: 15.0, carbsPer100g: 6.0),
  FoodSearchResult(name: 'Пельмени', kcalPer100g: 248, proteinPer100g: 11.9, fatPer100g: 12.4, carbsPer100g: 24.0),
];

int _relevanceScore(String name, String query) {
  final nameL = name.toLowerCase();
  final queryL = query.trim().toLowerCase();
  if (queryL.isEmpty) return 0;
  if (nameL == queryL) return 100;
  if (nameL.startsWith(queryL)) return 80;
  if (nameL.contains(queryL)) return 60;
  final tokens = queryL.split(RegExp(r'\s+')).where((t) => t.length >= 2);
  var matched = 0;
  for (final t in tokens) {
    if (nameL.contains(t)) matched++;
  }
  if (matched > 0 && matched == tokens.length) return 40;
  if (matched > 0) return 20;
  return 0;
}

List<FoodSearchResult> searchLocalFallback(String query) {
  final q = query.trim();
  if (q.length < 2) return [];
  final scored = <(int, FoodSearchResult)>[];
  for (final item in kLocalFoodFallback) {
    final score = _relevanceScore(item.name, q);
    if (score > 0) scored.add((score, item));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return scored.map((e) => e.$2).toList();
}

bool _hasRelevantMatch(List<FoodSearchResult> results, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return results.any((r) {
    final name = r.name.toLowerCase();
    return name.contains(q) || q.length >= 3 && name.contains(q.substring(0, 3));
  });
}

List<FoodSearchResult> mergeSearchResults({
  required List<FoodSearchResult> remote,
  required String query,
}) {
  final local = searchLocalFallback(query);
  if (local.isEmpty) return remote;
  if (remote.isEmpty || !_hasRelevantMatch(remote, query)) return local;

  final seen = <String>{};
  final merged = <FoodSearchResult>[];
  for (final item in [...local, ...remote]) {
    final key = item.name.toLowerCase();
    if (seen.add(key)) merged.add(item);
  }
  return merged;
}
