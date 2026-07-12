import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class WebDatabase {
  static const _profileKey = 'user_profile';
  static const _entriesKey = 'food_entries';
  static const _weightEntriesKey = 'weight_entries';

  static Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  static Future<UserProfile?> getProfile() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_profileKey);
    if (raw == null) return null;
    return UserProfile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await _prefs;
    await prefs.setString(_profileKey, jsonEncode(profile.toMap()..remove('id')));
  }

  static Future<List<FoodEntry>> getEntriesForDate(String date) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_entriesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => FoodEntry.fromMap(e as Map<String, dynamic>))
        .where((e) => e.date == date)
        .toList();
  }

  static Future<List<FoodEntry>> _allEntries() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_entriesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => FoodEntry.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _saveEntries(List<FoodEntry> entries) async {
    final prefs = await _prefs;
    await prefs.setString(
      _entriesKey,
      jsonEncode(entries.map((e) => e.toMap()).toList()),
    );
  }

  static Future<void> addEntry(FoodEntry entry) async {
    final entries = await _allEntries();
    final nextId = entries.isEmpty
        ? 1
        : entries.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    entries.add(FoodEntry(
      id: nextId,
      date: entry.date,
      mealType: entry.mealType,
      name: entry.name,
      grams: entry.grams,
      calories: entry.calories,
      protein: entry.protein,
      fat: entry.fat,
      carbs: entry.carbs,
    ));
    await _saveEntries(entries);
  }

  static Future<void> deleteEntry(int id) async {
    final entries = await _allEntries();
    entries.removeWhere((e) => e.id == id);
    await _saveEntries(entries);
  }

  static Future<Macros> getDailyTotals(String date) async {
    final entries = await getEntriesForDate(date);
    var total = const Macros();
    for (final entry in entries) {
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

  static Future<List<WeightEntry>> getWeightEntries() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_weightEntriesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => WeightEntry.fromMap(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  static Future<void> _saveWeightEntries(List<WeightEntry> entries) async {
    final prefs = await _prefs;
    await prefs.setString(
      _weightEntriesKey,
      jsonEncode(entries.map((e) => e.toMap()).toList()),
    );
  }

  static Future<void> addWeightEntry(WeightEntry entry) async {
    final entries = await getWeightEntries();
    final nextId = entries.isEmpty
        ? 1
        : entries.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    entries.add(WeightEntry(
      id: nextId,
      date: entry.date,
      recordedAt: entry.recordedAt,
      weightKg: entry.weightKg,
      source: entry.source,
    ));
    await _saveWeightEntries(entries);
  }

  static Future<void> deleteWeightEntry(int id) async {
    final entries = await getWeightEntries();
    entries.removeWhere((e) => e.id == id);
    await _saveWeightEntries(entries);
  }
}
