import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/models.dart';
import 'web_database.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<String> _databasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'podchet_kalloriy.db');
  }

  static Future<Database> _init() async {
    final path = await _databasePath();
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_profile (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            gender TEXT NOT NULL,
            age INTEGER NOT NULL,
            height_cm REAL NOT NULL,
            weight_kg REAL NOT NULL,
            activity TEXT NOT NULL,
            goal TEXT NOT NULL,
            preferences TEXT NOT NULL DEFAULT '',
            use_custom_targets INTEGER NOT NULL DEFAULT 0,
            target_calories REAL,
            target_protein REAL,
            target_fat REAL,
            target_carbs REAL,
            target_weight_kg REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE food_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            meal_type TEXT NOT NULL,
            name TEXT NOT NULL,
            grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein REAL NOT NULL,
            fat REAL NOT NULL,
            carbs REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE weight_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            weight_kg REAL NOT NULL,
            source TEXT NOT NULL DEFAULT 'manual'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN use_custom_targets INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN target_calories REAL',
          );
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN target_protein REAL',
          );
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN target_fat REAL',
          );
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN target_carbs REAL',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE user_profile ADD COLUMN target_weight_kg REAL',
          );
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL,
              recorded_at TEXT NOT NULL,
              weight_kg REAL NOT NULL,
              source TEXT NOT NULL DEFAULT 'manual'
            )
          ''');
          final rows = await db.query('user_profile', limit: 1);
          if (rows.isNotEmpty) {
            final weight = (rows.first['weight_kg'] as num).toDouble();
            final goal = rows.first['goal'] as String;
            final target = goal == 'lose'
                ? (weight * 0.9)
                : goal == 'gain'
                    ? (weight * 1.1)
                    : weight;
            await db.update(
              'user_profile',
              {'target_weight_kg': target},
              where: 'id = ?',
              whereArgs: [rows.first['id']],
            );
            final today = DateTime.now();
            final dateStr =
                '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
            await db.insert('weight_entries', {
              'date': dateStr,
              'recorded_at': today.toIso8601String(),
              'weight_kg': weight,
              'source': 'manual',
            });
          }
        }
      },
    );
  }

  static Future<UserProfile?> getProfile() async {
    if (kIsWeb) return WebDatabase.getProfile();
    final db = await database;
    final rows = await db.query('user_profile', limit: 1);
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  static Future<void> saveProfile(UserProfile profile) async {
    if (kIsWeb) {
      await WebDatabase.saveProfile(profile);
      return;
    }
    final db = await database;
    final existing = await getProfile();
    if (existing == null) {
      await db.insert('user_profile', profile.toMap()..remove('id'));
    } else {
      await db.update(
        'user_profile',
        profile.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    }
  }

  static Future<List<FoodEntry>> getEntriesForDate(String date) async {
    if (kIsWeb) return WebDatabase.getEntriesForDate(date);
    final db = await database;
    final rows = await db.query(
      'food_entries',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return rows.map(FoodEntry.fromMap).toList();
  }

  static Future<void> addEntry(FoodEntry entry) async {
    if (kIsWeb) {
      await WebDatabase.addEntry(entry);
      return;
    }
    final db = await database;
    await db.insert('food_entries', entry.toMap()..remove('id'));
  }

  static Future<void> deleteEntry(int id) async {
    if (kIsWeb) {
      await WebDatabase.deleteEntry(id);
      return;
    }
    final db = await database;
    await db.delete('food_entries', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Macros> getDailyTotals(String date) async {
    if (kIsWeb) return WebDatabase.getDailyTotals(date);
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
    if (kIsWeb) return WebDatabase.getWeightEntries();
    final db = await database;
    final rows = await db.query('weight_entries', orderBy: 'recorded_at ASC');
    return rows.map(WeightEntry.fromMap).toList();
  }

  static Future<void> addWeightEntry(WeightEntry entry) async {
    if (kIsWeb) {
      await WebDatabase.addWeightEntry(entry);
      return;
    }
    final db = await database;
    await db.insert('weight_entries', entry.toMap()..remove('id'));
  }

  static Future<void> deleteWeightEntry(int id) async {
    if (kIsWeb) {
      await WebDatabase.deleteWeightEntry(id);
      return;
    }
    final db = await database;
    await db.delete('weight_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Записать вес в историю и обновить текущий вес в профиле.
  static Future<void> logWeight(
    double weightKg, {
    WeightEntrySource source = WeightEntrySource.manual,
  }) async {
    final profile = await getProfile();
    if (profile == null) return;

    final now = DateTime.now();
    final dateStr = formatDateForDb(now);
    final entries = await getWeightEntries();
    final lastToday = entries.where((e) => e.date == dateStr).toList();
    if (lastToday.isNotEmpty &&
        (lastToday.last.weightKg - weightKg).abs() < 0.05) {
      return;
    }

    await addWeightEntry(WeightEntry(
      date: dateStr,
      recordedAt: now,
      weightKg: weightKg,
      source: source,
    ));

    await saveProfile(profile.copyWith(weightKg: weightKg));
  }

  static String formatDateForDb(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
