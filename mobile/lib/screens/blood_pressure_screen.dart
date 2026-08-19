import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/health_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/blood_pressure_chart.dart';

class BloodPressureScreen extends ConsumerStatefulWidget {
  const BloodPressureScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends ConsumerState<BloodPressureScreen> {
  int _days = 7;
  bool _busy = false;
  final _repo = HealthRepository();

  Future<void> _reload() async {
    ref.invalidate(bloodPressureReadingsProvider);
  }

  Future<void> _addManual() async {
    final now = DateTime.now();
    final sysCtrl = TextEditingController();
    final diaCtrl = TextEditingController();
    final pulseCtrl = TextEditingController();
    var measured = now;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Новое измерение'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: sysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Систол'),
                      autofocus: true,
                    ),
                    TextField(
                      controller: diaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Диастол'),
                    ),
                    TextField(
                      controller: pulseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Пульс (необяз.)'),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Время'),
                      subtitle: Text(DateFormat('d MMM, HH:mm', 'ru').format(measured)),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: measured,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date == null || !ctx.mounted) return;
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(measured),
                        );
                        if (time == null) return;
                        setLocal(() {
                          measured = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final sys = int.tryParse(sysCtrl.text.trim());
    final dia = int.tryParse(diaCtrl.text.trim());
    final pulse = int.tryParse(pulseCtrl.text.trim());
    if (sys == null || dia == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите систол и диастол')),
      );
      return;
    }
    try {
      await _repo.addManualReading(
        systolic: sys,
        diastolic: dia,
        pulse: pulse,
        measuredAt: measured,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _importCsv() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Не удалось прочитать файл');
      }
      final content = utf8.decode(bytes);
      final imported = await _repo.importCsv(content);
      if (!mounted) return;
      await _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Импортировано ${imported.imported} записей'
            '${imported.skippedDuplicates == 0 ? '' : ', пропущено дублей: ${imported.skippedDuplicates}'}'
            '${imported.errors.isEmpty ? '' : ', ошибок: ${imported.errors.length}'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Импорт: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _toneFor(BloodPressureReading reading) {
    if (reading.systolic >= 140 || reading.diastolic >= 90) {
      return const Color(0xFFE53935);
    }
    if (reading.systolic >= 130 || reading.diastolic >= 85) {
      return const Color(0xFFFB8C00);
    }
    return AppColors.primaryDark;
  }

  @override
  Widget build(BuildContext context) {
    final readingsAsync = ref.watch(bloodPressureReadingsProvider);
    final bottomPad = widget.embedded
        ? 28.0
        : 28.0 + MediaQuery.viewPaddingOf(context).bottom;

    return ColoredBox(
      color: AppColors.background,
      child: readingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (readings) {
          final latest = readings.isEmpty ? null : readings.first;
          final cutoff = DateTime.now().subtract(Duration(days: _days));
          final window = readings.where((e) => !e.measuredAt.isBefore(cutoff)).toList();
          BloodPressureAverage? avg;
          if (window.isNotEmpty) {
            avg = BloodPressureAverage(
              systolic: window.map((e) => e.systolic).reduce((a, b) => a + b) / window.length,
              diastolic: window.map((e) => e.diastolic).reduce((a, b) => a + b) / window.length,
              count: window.length,
            );
          }

          return Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _reload,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 8, 16, bottomPad + 72),
                  children: [
                    if (!widget.embedded)
                      Text('Давление', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    _HeroCard(latest: latest, avg: avg, days: _days, tone: latest == null ? AppColors.primaryDark : _toneFor(latest)),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7 дней')),
                        ButtonSegment(value: 30, label: Text('30 дней')),
                      ],
                      selected: {_days},
                      onSelectionChanged: (v) => setState(() => _days = v.first),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('График $_days дн.', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            const Row(
                              children: [
                                _LegendDot(color: Color(0xFFE53935), label: 'Систол'),
                                SizedBox(width: 12),
                                _LegendDot(color: AppColors.protein, label: 'Диастол'),
                              ],
                            ),
                            BloodPressureChart(readings: readings, days: _days),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'При стабильном АД ≥140/90 обратитесь к врачу. Данные не заменяют консультацию.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text('История', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (readings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Пока нет измерений. Добавьте вручную или импортируйте CSV.')),
                      )
                    else
                      ...readings.take(40).map(
                            (reading) => Card(
                              child: ListTile(
                                title: Text(
                                  '${reading.displayValue}${reading.pulse == null ? '' : '  ·  ${reading.pulse}'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _toneFor(reading),
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    DateFormat('d MMM yyyy, HH:mm', 'ru').format(reading.measuredAt),
                                    reading.source == BloodPressureSource.csv ? 'CSV' : 'вручную',
                                    if (reading.note != null && reading.note!.isNotEmpty) reading.note!,
                                  ].join(' · '),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    if (reading.id == null) return;
                                    await _repo.deleteReading(reading.id!);
                                    await _reload();
                                  },
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: widget.embedded ? 16 : 16 + MediaQuery.viewPaddingOf(context).bottom,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'bp-csv',
                      onPressed: _busy ? null : _importCsv,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.upload_file),
                      label: const Text('CSV'),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.extended(
                      heroTag: 'bp-add',
                      onPressed: _addManual,
                      icon: const Icon(Icons.add),
                      label: const Text('Запись'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.latest,
    required this.avg,
    required this.days,
    required this.tone,
  });

  final BloodPressureReading? latest;
  final BloodPressureAverage? avg;
  final int days;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Последнее', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    latest?.displayValue ?? '—',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: tone,
                        ),
                  ),
                  if (latest?.pulse != null)
                    Text('пульс ${latest!.pulse}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Среднее $days дн.', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    avg?.displayValue ?? '—',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    avg == null ? 'нет данных' : '${avg!.count} изм.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
