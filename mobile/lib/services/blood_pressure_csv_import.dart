import '../models/models.dart';

class CsvImportResult {
  final List<BloodPressureReading> readings;
  final int skippedDuplicates;
  final List<String> errors;
  final int? created;

  const CsvImportResult({
    required this.readings,
    this.skippedDuplicates = 0,
    this.errors = const [],
    this.created,
  });

  int get imported => created ?? readings.length;
}

class BloodPressureCsvImport {
  static const _dateAliases = {
    'дата',
    'date',
    'день',
    'day',
  };
  static const _timeAliases = {'время', 'time', 'час'};
  static const _sysAliases = {
    'сис',
    'систол',
    'систолическое',
    'systolic',
    'sys',
    'сд',
  };
  static const _diaAliases = {
    'диа',
    'диастол',
    'диастолическое',
    'diastolic',
    'dia',
    'дд',
  };
  static const _pulseAliases = {'пульс', 'pulse', 'hr', 'чсс', 'heart rate'};
  static const _noteAliases = {
    'заметки',
    'заметка',
    'примечание',
    'note',
    'notes',
    'комментарий',
  };

  static CsvImportResult parse(String content, {BloodPressureSource source = BloodPressureSource.csv}) {
    var text = content.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (text.isEmpty) {
      throw const FormatException('Пустой CSV');
    }

    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      throw const FormatException('Пустой CSV');
    }

    final delimiter = _detectDelimiter(lines.first);
    final header = _parseRow(lines.first, delimiter).map(_norm).toList();
    final dateIdx = _findColumn(header, _dateAliases);
    final timeIdx = _findColumn(header, _timeAliases);
    final sysIdx = _findColumn(header, _sysAliases);
    final diaIdx = _findColumn(header, _diaAliases);
    final pulseIdx = _findColumn(header, _pulseAliases);
    final noteIdx = _findColumn(header, _noteAliases);

    if (dateIdx == null || sysIdx == null || diaIdx == null) {
      throw const FormatException(
        'Не найдены колонки. Ожидается формат Citizen: Дата,Время,Сис,Диа,Пульс',
      );
    }

    final readings = <BloodPressureReading>[];
    final errors = <String>[];
    final seen = <String>{};
    var skipped = 0;

    for (var i = 1; i < lines.length; i++) {
      final row = _parseRow(lines[i], delimiter);
      if (row.every((c) => c.trim().isEmpty)) continue;
      try {
        final dateS = _cell(row, dateIdx);
        final timeS = timeIdx == null ? '00:00' : _cell(row, timeIdx);
        final measuredAt = _parseDateTime(dateS, timeS);
        final systolic = _parseInt(_cell(row, sysIdx));
        final diastolic = _parseInt(_cell(row, diaIdx));
        final pulse = pulseIdx == null ? null : _parseInt(_cell(row, pulseIdx));
        final note = noteIdx == null ? null : _cell(row, noteIdx);
        _validate(systolic, diastolic, pulse);
        final key = '${measuredAt.toIso8601String()}|$systolic|$diastolic';
        if (!seen.add(key)) {
          skipped += 1;
          continue;
        }
        readings.add(
          BloodPressureReading(
            measuredAt: measuredAt,
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            source: source,
            note: (note == null || note.isEmpty) ? null : note,
          ),
        );
      } catch (e) {
        errors.add('Строка ${i + 1}: $e');
      }
    }

    return CsvImportResult(
      readings: readings,
      skippedDuplicates: skipped,
      errors: errors,
    );
  }

  static String _norm(String value) =>
      value.replaceAll('\uFEFF', '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _detectDelimiter(String header) {
    final semi = ';'.allMatches(header).length;
    final comma = ','.allMatches(header).length;
    return semi > comma ? ';' : ',';
  }

  static List<String> _parseRow(String line, String delimiter) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString().trim());
    return out;
  }

  static int? _findColumn(List<String> header, Set<String> aliases) {
    for (var i = 0; i < header.length; i++) {
      final key = header[i];
      if (aliases.contains(key) || aliases.any((a) => key.startsWith(a))) {
        return i;
      }
    }
    return null;
  }

  static String _cell(List<String> row, int index) =>
      index < row.length ? row[index].trim() : '';

  static int? _parseInt(String value) {
    final text = value.replaceAll(',', '.').trim();
    if (text.isEmpty || text == '-' || text == '—' || text.toLowerCase() == 'nan') {
      return null;
    }
    final match = RegExp(r'\d+').firstMatch(text);
    return match == null ? null : int.parse(match.group(0)!);
  }

  static DateTime _parseDateTime(String dateS, String timeS) {
    final time = timeS.trim().isEmpty ? '00:00' : timeS.trim();
    final dateFormats = [
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),
      RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$'),
      RegExp(r'^(\d{2})/(\d{2})/(\d{4})$'),
      RegExp(r'^(\d{4})/(\d{2})/(\d{2})$'),
    ];
    DateTime? date;
    final iso = dateFormats[0].firstMatch(dateS);
    if (iso != null) {
      date = DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
    final dmyDot = dateFormats[1].firstMatch(dateS);
    if (date == null && dmyDot != null) {
      date = DateTime(
        int.parse(dmyDot.group(3)!),
        int.parse(dmyDot.group(2)!),
        int.parse(dmyDot.group(1)!),
      );
    }
    final dmySlash = dateFormats[2].firstMatch(dateS);
    if (date == null && dmySlash != null) {
      date = DateTime(
        int.parse(dmySlash.group(3)!),
        int.parse(dmySlash.group(2)!),
        int.parse(dmySlash.group(1)!),
      );
    }
    final ymdSlash = dateFormats[3].firstMatch(dateS);
    if (date == null && ymdSlash != null) {
      date = DateTime(
        int.parse(ymdSlash.group(1)!),
        int.parse(ymdSlash.group(2)!),
        int.parse(ymdSlash.group(3)!),
      );
    }
    if (date == null) {
      throw FormatException('Не удалось разобрать дату: $dateS');
    }
    final timeParts = time.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
    final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }

  static void _validate(int? systolic, int? diastolic, int? pulse) {
    if (systolic == null || diastolic == null) {
      throw const FormatException('нет систол/диастол');
    }
    if (systolic < 70 || systolic > 250) {
      throw FormatException('систол $systolic вне диапазона 70–250');
    }
    if (diastolic < 40 || diastolic > 150) {
      throw FormatException('диастол $diastolic вне диапазона 40–150');
    }
    if (systolic <= diastolic) {
      throw FormatException('систол $systolic должен быть больше диастол $diastolic');
    }
    if (pulse != null && (pulse < 30 || pulse > 220)) {
      throw FormatException('пульс $pulse вне диапазона 30–220');
    }
  }
}
