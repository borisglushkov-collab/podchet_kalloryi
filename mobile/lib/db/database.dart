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
      version: 2,
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
            target_carbs REAL
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
}
