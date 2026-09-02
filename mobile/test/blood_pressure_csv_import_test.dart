import 'package:flutter_test/flutter_test.dart';
import 'package:podchet_kalloriy/services/blood_pressure_csv_import.dart';

void main() {
  const sample = '''Дата,Время,Сис,Диа,Пульс,Заметки
2026-08-19,07:32,133,90,72,утро
2026-08-18,07:15,136,91,75,
2026-08-17,21:40,128,84,,вечер
''';

  test('parses Citizen CSV including empty pulse', () {
    final result = BloodPressureCsvImport.parse(sample);
    expect(result.readings.length, 3);
    expect(result.errors, isEmpty);
    expect(result.readings.first.systolic, 133);
    expect(result.readings.first.diastolic, 90);
    expect(result.readings.first.pulse, 72);
    expect(result.readings.last.pulse, isNull);
  });

  test('parses semicolon and dotted dates', () {
    const csv = 'Дата;Время;Сис;Диа;Пульс\n19.08.2026;07:32;133;90;72\n';
    final result = BloodPressureCsvImport.parse(csv);
    expect(result.readings, hasLength(1));
    expect(result.readings.first.measuredAt, DateTime(2026, 8, 19, 7, 32));
  });

  test('skips duplicate rows in the same file', () {
    final result = BloodPressureCsvImport.parse('$sample\n2026-08-19,07:32,133,90,72,\n');
    expect(result.readings, hasLength(3));
    expect(result.skippedDuplicates, 1);
  });

  test('rejects empty csv', () {
    expect(() => BloodPressureCsvImport.parse('  '), throwsFormatException);
  });
}
