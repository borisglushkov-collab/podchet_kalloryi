import '../db/database.dart';
import '../models/models.dart';
import 'blood_pressure_csv_import.dart';

class HealthRepository {
  Future<List<BloodPressureReading>> listBloodPressure({
    DateTime? from,
    DateTime? to,
  }) {
    return AppDatabase.getBloodPressureReadings(from: from, to: to);
  }

  Future<BloodPressureReading?> latestBloodPressure() {
    return AppDatabase.getLatestBloodPressure();
  }

  Future<BloodPressureAverage?> averageBloodPressure(int days) {
    return AppDatabase.getBloodPressureAverage(days);
  }

  Future<bool> addManualReading({
    required int systolic,
    required int diastolic,
    int? pulse,
    DateTime? measuredAt,
    String? note,
  }) {
    return AppDatabase.addBloodPressureReading(
      BloodPressureReading(
        measuredAt: measuredAt ?? DateTime.now(),
        systolic: systolic,
        diastolic: diastolic,
        pulse: pulse,
        source: BloodPressureSource.manual,
        note: note,
      ),
    );
  }

  Future<CsvImportResult> importCsv(String content) async {
    final parsed = BloodPressureCsvImport.parse(content);
    final created = await AppDatabase.importBloodPressureReadings(parsed.readings);
    return CsvImportResult(
      readings: parsed.readings,
      skippedDuplicates: parsed.skippedDuplicates + (parsed.readings.length - created),
      errors: parsed.errors,
      created: created,
    );
  }

  Future<void> deleteReading(int id) {
    return AppDatabase.deleteBloodPressureReading(id);
  }

  Future<Map<String, dynamic>?> healthContextForCoach({
    UserProfile? profile,
    Macros? targets,
  }) async {
    final latest = await latestBloodPressure();
    final avg7d = await averageBloodPressure(7);
    if (latest == null && avg7d == null && profile == null) return null;
    return {
      if (latest != null) 'blood_pressure_latest': latest.toApiJson(),
      if (avg7d != null) 'blood_pressure_avg_7d': avg7d.toApiJson(),
      if (profile != null) 'weight_latest_kg': profile.weightKg,
      if (targets != null)
        'coaching_targets': {
          'kcal_min': (targets.calories - 100).round().clamp(1200, 4000),
          'kcal_max': (targets.calories + 100).round().clamp(1200, 4000),
          'protein_g': targets.protein.round(),
        },
    };
  }
}
