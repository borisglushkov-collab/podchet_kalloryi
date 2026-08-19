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
      version: 4,
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
        await _createHealthTables(db);
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
        if (oldVersion < 4) {
          await _createHealthTables(db);
        }
      },
    );
  }

  static Future<void> _createHealthTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS blood_pressure_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        measured_at TEXT NOT NULL,
        systolic INTEGER NOT NULL,
        diastolic INTEGER NOT NULL,
        pulse INTEGER,
        source TEXT NOT NULL DEFAULT 'manual',
        note TEXT,
        UNIQUE(measured_at, systolic, diastolic)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sleep_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        duration_min INTEGER NOT NULL,
        quality_label TEXT,
        source TEXT DEFAULT 'health_connect'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_daily (
        date TEXT PRIMARY KEY,
        steps INTEGER,
        active_minutes INTEGER,
        calories_burned REAL,
        synced_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_composition (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        measured_at TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        body_fat_pct REAL,
        visceral_fat REAL,
        muscle_kg REAL,
        bmr_kcal INTEGER,
        source TEXT
      )
    ''');
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

  static Future<List<BloodPressureReading>> getBloodPressureReadings({
    DateTime? from,
    DateTime? to,
  }) async {
    if (kIsWeb) return WebDatabase.getBloodPressureReadings(from: from, to: to);
    final db = await database;
    final rows = await db.query(
      'blood_pressure_readings',
      orderBy: 'measured_at DESC',
    );
    var items = rows.map(BloodPressureReading.fromMap).toList();
    if (from != null) {
      items = items.where((e) => !e.measuredAt.isBefore(from)).toList();
    }
    if (to != null) {
      items = items.where((e) => !e.measuredAt.isAfter(to)).toList();
    }
    return items;
  }

  static Future<BloodPressureReading?> getLatestBloodPressure() async {
    final items = await getBloodPressureReadings();
    return items.isEmpty ? null : items.first;
  }

  static Future<BloodPressureAverage?> getBloodPressureAverage(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final items = await getBloodPressureReadings(from: cutoff);
    if (items.isEmpty) return null;
    final sys = items.map((e) => e.systolic).reduce((a, b) => a + b) / items.length;
    final dia = items.map((e) => e.diastolic).reduce((a, b) => a + b) / items.length;
    final pulses = items.where((e) => e.pulse != null).map((e) => e.pulse!).toList();
    return BloodPressureAverage(
      systolic: sys,
      diastolic: dia,
      pulse: pulses.isEmpty ? null : pulses.reduce((a, b) => a + b) / pulses.length,
      count: items.length,
    );
  }

  static Future<bool> addBloodPressureReading(BloodPressureReading reading) async {
    if (kIsWeb) return WebDatabase.addBloodPressureReading(reading);
    final db = await database;
    final id = await db.insert(
      'blood_pressure_readings',
      reading.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  static Future<int> importBloodPressureReadings(
    List<BloodPressureReading> readings,
  ) async {
    var created = 0;
    for (final reading in readings) {
      if (await addBloodPressureReading(reading)) created += 1;
    }
    return created;
  }

  static Future<void> deleteBloodPressureReading(int id) async {
    if (kIsWeb) {
      await WebDatabase.deleteBloodPressureReading(id);
      return;
    }
    final db = await database;
    await db.delete('blood_pressure_readings', where: 'id = ?', whereArgs: [id]);
  }

  static String formatDateForDb(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
