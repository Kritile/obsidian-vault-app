import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'period_report_data.dart';
import 'vault_models.dart';

class ReportService {
  Future<String?> exportCsv(
    List<WorkEntry> entries,
    ReportPeriod period, {
    List<ParsedNote> trainings = const [],
    PeriodReportData? reportData,
  }) async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Папка для CSV-отчёта',
    );
    if (folder == null) return null;
    final file = File(
      '$folder/report-${_compactDate(period.start)}-${_compactDate(period.end)}.csv',
    );
    await file.writeAsString(
      detailedCsv(
        entries,
        period,
        trainings: trainings,
        reportData: reportData,
      ),
      flush: true,
    );
    return file.path;
  }

  String detailedCsv(
    List<WorkEntry> entries,
    ReportPeriod period, {
    List<ParsedNote> trainings = const [],
    PeriodReportData? reportData,
  }) {
    const columns = [
      'record_type',
      'date',
      'title',
      'status',
      'description',
      'steps',
      'sleep_hours',
      'daily_calories',
      'done_count',
      'habit',
      'project',
      'hours',
      'task_type',
      'sport',
      'time',
      'duration_min',
      'distance_km',
      'avg_speed_kmh',
      'avg_hr',
      'max_hr',
      'training_calories',
      'aerobic_te',
      'anaerobic_te',
      'trimp',
      'load',
      'recovery_hours',
      'joint_risk',
      'cardio',
      'mood',
      'strokes',
      'stroke_rate',
      'stroke_avg_time',
      'jumps',
      'best_series',
      'games',
      'area',
      'date_source',
      'source_path',
    ];
    final rows = <Map<String, Object?>>[];
    for (final item in reportData?.dailies ?? const <DailyReportItem>[]) {
      rows.add({
        'record_type': 'daily',
        'date': _isoDate(item.dateInfo.date),
        'title': item.note.title,
        'steps': item.steps,
        'sleep_hours': item.sleep,
        'daily_calories': item.calories,
        'done_count': item.doneCount,
        'date_source': item.dateInfo.source,
        'source_path': item.note.document.path,
      });
    }
    for (final item in reportData?.doneItems ?? const <DoneReportItem>[]) {
      rows.add({
        'record_type': 'done',
        'date': _isoDate(item.date),
        'description': item.text,
        'source_path': item.note.document.path,
      });
    }
    for (final item in reportData?.habits ?? const <HabitReportItem>[]) {
      rows.add({
        'record_type': 'habit',
        'date': _isoDate(item.date),
        'status': item.completed ? 'completed' : 'open',
        'habit': item.name,
      });
    }
    for (final entry in entries) {
      rows.add({
        'record_type': 'work',
        'date': _isoDate(entry.date),
        'description': entry.description,
        'hours': entry.hours,
        'project': entry.projects.join('|'),
        'source_path': entry.sourcePath,
      });
    }
    for (final item in reportData?.tasks ?? const <TaskReportItem>[]) {
      rows.add({
        'record_type': 'task',
        'date': _isoDate(item.dateInfo.date),
        'title': item.name,
        'status': item.completed ? 'completed' : 'open',
        'project': item.projects.join('|'),
        'hours': item.hours,
        'task_type': item.kind,
        'date_source': item.dateInfo.source,
        'source_path': item.note.document.path,
      });
    }
    final trainingItems =
        reportData?.trainings ??
        trainings
            .map(
              (note) => TrainingReportItem(
                note: note,
                dateInfo: ReportDateInfo(
                  date: note.date ?? note.document.modifiedAt,
                  source: note.date == null ? 'file.mtime' : 'date',
                  fallback: note.date == null,
                ),
              ),
            )
            .toList(growable: false);
    for (final item in trainingItems) {
      final note = item.note;
      final metrics = _map(note.frontmatter['metrics']);
      final assessment = _map(note.frontmatter['assessment']);
      rows.add({
        'record_type': 'training',
        'date': _isoDate(item.dateInfo.date),
        'title': note.title,
        'sport': _sport(note),
        'time': note.frontmatter['time'],
        'duration_min': metrics['duration'],
        'distance_km': metrics['distance'],
        'avg_speed_kmh': metrics['avg_speed'],
        'avg_hr': metrics['avg_hr'],
        'max_hr': metrics['max_hr'],
        'training_calories': metrics['calories'],
        'aerobic_te': metrics['aerobic_te'],
        'anaerobic_te': metrics['anaerobic_te'],
        'trimp': assessment['trimp'],
        'load': assessment['load'],
        'recovery_hours': assessment['recovery_hours'],
        'joint_risk': assessment['joint_risk'],
        'cardio': assessment['cardio'],
        'mood': note.frontmatter['mood'],
        'strokes': metrics['strokes'],
        'stroke_rate': metrics['stroke_rate'],
        'stroke_avg_time': metrics['stroke_avg_time'],
        'jumps': metrics['jumps'],
        'best_series': metrics['best_series'],
        'games': metrics['games'],
        'date_source': item.dateInfo.source,
        'source_path': note.document.path,
      });
    }
    for (final item in reportData?.notes ?? const <ContentNoteReportItem>[]) {
      rows.add({
        'record_type': 'note',
        'date': _isoDate(item.dateInfo.date),
        'title': item.note.title,
        'area': item.area,
        'date_source': item.dateInfo.source,
        'source_path': item.note.document.path,
      });
    }
    return '${columns.join(',')}\n${rows.map((row) => columns.map((column) => _csv(row[column]?.toString() ?? '')).join(',')).join('\n')}\n';
  }

  Future<String?> exportPdf(
    List<WorkEntry> entries,
    ReportPeriod period, {
    List<ParsedNote> trainings = const [],
    PeriodReportData? reportData,
  }) async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Папка для PDF-отчёта',
    );
    if (folder == null) return null;
    final file = File(
      '$folder/report-${_compactDate(period.start)}-${_compactDate(period.end)}.pdf',
    );
    await file.writeAsBytes(
      await buildPdf(
        entries,
        period,
        trainings: trainings,
        reportData: reportData,
      ),
      flush: true,
    );
    return file.path;
  }

  Future<Uint8List> buildPdf(
    List<WorkEntry> entries,
    ReportPeriod period, {
    List<ParsedNote> trainings = const [],
    PeriodReportData? reportData,
  }) async {
    final fonts = await _unicodeFonts();
    final pdf = pw.Document(
      title: 'Pavel Vault detailed report',
      author: 'Pavel Vault',
      subject: '${_isoDate(period.start)} - ${_isoDate(period.end)}',
    );
    final totals = _projectTotals(entries);
    final trainingItems =
        reportData?.trainings ??
        trainings
            .map(
              (note) => TrainingReportItem(
                note: note,
                dateInfo: ReportDateInfo(
                  date: note.date ?? note.document.modifiedAt,
                  source: note.date == null ? 'file.mtime' : 'date',
                  fallback: note.date == null,
                ),
              ),
            )
            .toList(growable: false);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.$1, bold: fonts.$2),
        build: (_) => [
          pw.Header(level: 0, child: pw.Text('Pavel Vault detailed report')),
          pw.Text('${_isoDate(period.start)} - ${_isoDate(period.end)}'),
          if (reportData != null) ...[
            _pdfHeader('Overview'),
            _pdfTable(
              const ['Metric', 'Value'],
              [
                [
                  'Filled days',
                  '${reportData.dailies.length}/${reportData.periodDays}',
                ],
                [
                  'Steps total / average',
                  '${_value(reportData.steps)} / ${_value(reportData.averageSteps)}',
                ],
                ['Average sleep, h', _value(reportData.averageSleep)],
                [
                  'Daily calories total / average',
                  '${_value(reportData.calories)} / ${_value(reportData.averageCalories)}',
                ],
                [
                  'Trainings / duration, min',
                  '${reportData.trainings.length} / ${_value(reportData.trainingDuration)}',
                ],
                [
                  'Completed tasks / total',
                  '${reportData.completedTasks}/${reportData.tasks.length}',
                ],
                [
                  'New notes / fallback dates',
                  '${reportData.notes.length}/${reportData.fallbackNotes}',
                ],
              ],
            ),
            if (reportData.dailies.isNotEmpty) ...[
              _pdfHeader('Daily health metrics'),
              _pdfTable(
                const [
                  'Date',
                  'Steps',
                  'Sleep h',
                  'Calories',
                  'Done',
                  'Source',
                ],
                reportData.dailies
                    .map(
                      (item) => [
                        _isoDate(item.dateInfo.date),
                        _value(item.steps),
                        _value(item.sleep),
                        _value(item.calories),
                        '${item.doneCount}',
                        item.note.document.path,
                      ],
                    )
                    .toList(),
              ),
            ],
            if (reportData.habits.isNotEmpty) ...[
              _pdfHeader('Habits'),
              _pdfTable(
                const ['Date', 'Habit', 'Status'],
                reportData.habits
                    .map(
                      (item) => [
                        _isoDate(item.date),
                        item.name,
                        item.completed ? 'Completed' : 'Open',
                      ],
                    )
                    .toList(),
              ),
            ],
            if (reportData.doneItems.isNotEmpty) ...[
              _pdfHeader('Done items'),
              _pdfTable(
                const ['Date', 'Entry', 'Source'],
                reportData.doneItems
                    .map(
                      (item) => [
                        _isoDate(item.date),
                        item.text,
                        item.note.document.path,
                      ],
                    )
                    .toList(),
              ),
            ],
          ],
          if (entries.isNotEmpty) ...[
            _pdfHeader('Work log'),
            _pdfTable(
              const ['Date', 'Description', 'Hours', 'Projects', 'Source'],
              entries
                  .map(
                    (entry) => [
                      _isoDate(entry.date),
                      entry.description,
                      _value(entry.hours),
                      entry.projects.join(', '),
                      entry.sourcePath,
                    ],
                  )
                  .toList(),
            ),
          ],
          if (trainingItems.isNotEmpty) ...[
            _pdfHeader('Trainings - full details'),
            for (final item in trainingItems) ...[
              pw.Header(
                level: 2,
                child: pw.Text(
                  '${_isoDate(item.dateInfo.date)} | ${_sport(item.note)} | ${item.note.frontmatter['time'] ?? ''}',
                ),
              ),
              _pdfTable(const ['Field', 'Value'], _trainingFields(item)),
              if (_trainingNotes(item.note).isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'Notes',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(_trainingNotes(item.note)),
              ],
              pw.SizedBox(height: 8),
            ],
          ],
          if (reportData != null && reportData.tasks.isNotEmpty) ...[
            _pdfHeader('Tasks'),
            _pdfTable(
              const [
                'Status',
                'Date',
                'Task',
                'Projects',
                'Hours',
                'Type',
                'Source',
              ],
              reportData.tasks
                  .map(
                    (item) => [
                      item.completed ? 'Completed' : 'Open',
                      _isoDate(item.dateInfo.date),
                      item.name,
                      item.projects.join(', '),
                      _value(item.hours),
                      item.kind,
                      item.note.document.path,
                    ],
                  )
                  .toList(),
            ),
          ],
          if (reportData != null && reportData.notes.isNotEmpty) ...[
            _pdfHeader('New notes'),
            _pdfTable(
              const ['Date', 'Title', 'Area', 'Date source', 'Path'],
              reportData.notes
                  .map(
                    (item) => [
                      _isoDate(item.dateInfo.date),
                      item.note.title,
                      item.area,
                      '${item.dateInfo.source}${item.dateInfo.fallback ? ' (fallback)' : ''}',
                      item.note.document.path,
                    ],
                  )
                  .toList(),
            ),
          ],
          if (totals.isNotEmpty) ...[
            _pdfHeader('Project totals'),
            _pdfTable(
              const ['Project', 'Hours'],
              totals.entries
                  .map((entry) => [entry.key, _value(entry.value)])
                  .toList(),
            ),
          ],
          if (reportData != null &&
              (reportData.missingSteps > 0 ||
                  reportData.missingSleep > 0 ||
                  reportData.missingCalories > 0 ||
                  reportData.fallbackNotes > 0)) ...[
            _pdfHeader('Data quality'),
            pw.Bullet(text: 'Missing steps: ${reportData.missingSteps} days'),
            pw.Bullet(text: 'Missing sleep: ${reportData.missingSleep} days'),
            pw.Bullet(
              text:
                  'Missing daily calories: ${reportData.missingCalories} days',
            ),
            pw.Bullet(
              text: 'Notes with fallback date: ${reportData.fallbackNotes}',
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  String markdown(
    List<WorkEntry> entries,
    ReportPeriod period, {
    List<ParsedNote> trainings = const [],
    PeriodReportData? reportData,
  }) {
    final totals = _projectTotals(entries);
    final workLines = entries.map(
      (entry) =>
          '| ${_displayDate(entry.date)} | ${_md(entry.description)} | ${entry.hours} | ${_md(entry.projects.join(', '))} |',
    );
    final dailyLines = (reportData?.dailies ?? const <DailyReportItem>[]).map(
      (item) =>
          '| ${_displayDate(item.dateInfo.date)} | ${_md(item.note.title)} | ${_value(item.steps)} | ${_value(item.sleep)} | ${_value(item.calories)} | ${item.doneCount} |',
    );
    final trainingItems =
        reportData?.trainings ??
        trainings
            .map(
              (note) => TrainingReportItem(
                note: note,
                dateInfo: ReportDateInfo(
                  date: note.date ?? note.document.modifiedAt,
                  source: note.date == null ? 'file.mtime' : 'date',
                  fallback: note.date == null,
                ),
              ),
            )
            .toList(growable: false);
    final trainingLines = trainingItems.map((item) {
      final note = item.note;
      final metrics = _map(note.frontmatter['metrics']);
      final assessment = _map(note.frontmatter['assessment']);
      return '| ${_displayDate(item.dateInfo.date)} | ${_md(_sport(note))} | ${_value(metrics['duration'])} | ${_value(metrics['avg_hr'])} | ${_value(metrics['max_hr'])} | ${_value(metrics['calories'])} | ${_value(metrics['aerobic_te'])} | ${_value(metrics['anaerobic_te'])} | ${_value(assessment['trimp'])} | ${_value(assessment['load'])} | ${_value(assessment['recovery_hours'])} |';
    });
    return '''---
type: period-report
report_type: ${period.type}
period_start: ${_isoDate(period.start)}
period_end: ${_isoDate(period.end)}
created: ${_isoDate(DateTime.now())}
tags: [Отчёт, Ежедневник]
---

# Отчёт ${_displayDate(period.start)} — ${_displayDate(period.end)}

## Показатели дня

| Дата | Заметка | Шаги | Сон, ч | Калории | Сделано |
|---|---|---:|---:|---:|---:|
${dailyLines.join('\n')}

## Что было сделано

| Дата | Работа | Часы | Проекты |
|---|---|---:|---|
${workLines.join('\n')}

## Итого по проектам

${totals.entries.map((entry) => '- **${entry.key}**: ${entry.value} ч').join('\n')}

## 🏋️ Тренировки

| Дата | Вид | Мин | Пульс ср. | Пульс макс. | Ккал | Aerobic TE | Anaerobic TE | TRIMP | Нагрузка | Восстановление, ч |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
${trainingLines.join('\n')}

```dataviewjs
await dv.view("Resources/Scripts/reports/dashboard", {
  start: dv.current().period_start,
  end: dv.current().period_end,
  periodType: dv.current().report_type
});
```
''';
  }

  List<List<String>> _trainingFields(TrainingReportItem item) {
    final note = item.note;
    final metrics = _map(note.frontmatter['metrics']);
    final assessment = _map(note.frontmatter['assessment']);
    final rows = <List<String>>[
      ['Date', _isoDate(item.dateInfo.date)],
      ['Time', _value(note.frontmatter['time'])],
      ['Sport', _sport(note)],
      ['Mood', _value(note.frontmatter['mood'])],
    ];
    for (final entry in metrics.entries) {
      rows.add([_fieldLabel(entry.key), _value(entry.value)]);
    }
    for (final entry in assessment.entries) {
      rows.add([_fieldLabel(entry.key), _value(entry.value)]);
    }
    rows.add(['Source', note.document.path]);
    return rows;
  }

  String _trainingNotes(ParsedNote note) => note.body
      .replaceAll(
        RegExp(r'```dataview(?:js)?\s*[\s\S]*?```', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .trim();

  pw.Widget _pdfHeader(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
    child: pw.Header(level: 1, child: pw.Text(text)),
  );

  pw.Widget _pdfTable(List<String> headers, List<List<String>> data) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        cellStyle: const pw.TextStyle(fontSize: 7),
        cellPadding: const pw.EdgeInsets.all(3),
      );

  Map<String, double> _projectTotals(List<WorkEntry> entries) {
    final totals = <String, double>{};
    for (final entry in entries) {
      for (final project in entry.projects) {
        totals[project] = (totals[project] ?? 0) + entry.hours;
      }
    }
    return totals;
  }

  Future<(pw.Font, pw.Font)> _unicodeFonts() async {
    final regularPaths = <String>[
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/usr/share/fonts/TTF/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      if (Platform.environment['WINDIR'] case final windir?)
        '$windir/Fonts/arial.ttf',
    ];
    final boldPaths = <String>[
      '/system/fonts/Roboto-Bold.ttf',
      '/system/fonts/NotoSans-Bold.ttf',
      '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      if (Platform.environment['WINDIR'] case final windir?)
        '$windir/Fonts/arialbd.ttf',
    ];
    final regular = await _firstFont(regularPaths);
    final bold = await _firstFont(boldPaths);
    return (
      regular ?? pw.Font.helvetica(),
      bold ?? regular ?? pw.Font.helveticaBold(),
    );
  }

  Future<pw.Font?> _firstFont(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      return pw.Font.ttf(bytes.buffer.asByteData());
    }
    return null;
  }

  String _fieldLabel(String key) =>
      const {
        'duration': 'Duration, min',
        'distance': 'Distance, km',
        'avg_speed': 'Average speed, km/h',
        'avg_hr': 'Average HR',
        'max_hr': 'Maximum HR',
        'calories': 'Calories',
        'aerobic_te': 'Aerobic TE',
        'anaerobic_te': 'Anaerobic TE',
        'trimp': 'TRIMP',
        'load': 'Load',
        'recovery_hours': 'Recovery, h',
        'joint_risk': 'Joint risk',
        'cardio': 'Cardio state',
        'strokes': 'Strokes',
        'stroke_rate': 'Stroke rate',
        'stroke_avg_time': 'Average stroke time',
        'jumps': 'Jumps',
        'best_series': 'Best series',
        'games': 'Games',
      }[key] ??
      key;

  static String _csv(String value) => '"${value.replaceAll('"', '""')}"';
  static String _md(String value) => value.replaceAll('|', r'\|');
  static String _value(Object? value) =>
      value == null || value.toString().trim().isEmpty ? '—' : value.toString();
  static String _isoDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);
  static String _compactDate(DateTime value) =>
      DateFormat('yyyyMMdd').format(value);
  static String _displayDate(DateTime value) =>
      DateFormat('dd.MM.yyyy').format(value);

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : const {};

  static String _sport(ParsedNote training) {
    final value = training.frontmatter['sport'];
    return value is List && value.isNotEmpty
        ? value.first.toString()
        : value?.toString() ??
              training.frontmatter['sport_key']?.toString() ??
              'Training';
  }
}
