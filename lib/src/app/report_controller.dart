import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../core/vault/period_report_data.dart';
import '../core/vault/report_layout.dart';
import '../core/vault/vault_models.dart';
import '../core/vault/report_service.dart';
import '../shared/app_log.dart';
import 'vault_controller.dart';

typedef NoteWriter = Future<void> Function(String path, String source);

class ReportController extends ChangeNotifier {
  ReportController(this._vault);

  final VaultController _vault;
  NoteWriter? noteWriter;
  ReportLayoutConfig layout = ReportLayoutConfig.defaults();
  final _builder = const PeriodReportDataBuilder();
  final _service = ReportService();
  bool _creatingPeriodicReports = false;

  PeriodReportData build(ReportPeriod period) =>
      _builder.build(_vault.index.notes, period);

  ReportPeriod comparisonPeriod(
    ReportPeriod period,
    ReportComparison comparison,
  ) {
    if (comparison == ReportComparison.previousYear) {
      return ReportPeriod(
        start: DateTime(
          period.start.year - 1,
          period.start.month,
          period.start.day,
        ),
        end: DateTime(
          period.end.year - 1,
          period.end.month,
          period.end.day,
          period.end.hour,
          period.end.minute,
          period.end.second,
        ),
        type: period.type,
      );
    }
    final end = period.start.subtract(const Duration(milliseconds: 1));
    if (period.type == 'monthly') {
      return ReportPeriod(
        start: DateTime(period.start.year, period.start.month - 1),
        end: end,
        type: period.type,
      );
    }
    if (period.type == 'yearly') {
      return ReportPeriod(
        start: DateTime(period.start.year - 1),
        end: end,
        type: period.type,
      );
    }
    final length = period.end.difference(period.start) + const Duration(milliseconds: 1);
    return ReportPeriod(
      start: period.start.subtract(length),
      end: end,
      type: period.type,
    );
  }

  List<WorkEntry> workEntries(ReportPeriod period) =>
      _vault.index.workEntries(period);

  Future<void> refresh() async {
    final document = _vault.documents
        .where((item) => item.path == ReportLayoutConfig.path)
        .firstOrNull;
    if (document == null) {
      layout = ReportLayoutConfig.defaults();
      notifyListeners();
      return;
    }
    try {
      layout = ReportLayoutConfig.decode(document.text);
    } catch (error, stackTrace) {
      layout = ReportLayoutConfig.defaults();
      AppLog.error(
        'Reports',
        'Конфигурация блоков повреждена; используется стандартная',
        error,
        stackTrace,
      );
    }
    notifyListeners();
  }

  Future<void> saveLayout(ReportLayoutConfig value) async {
    final writer = noteWriter;
    if (writer == null) throw StateError('Note writer is not configured');
    layout = value;
    notifyListeners();
    await writer(ReportLayoutConfig.path, value.encode());
  }

  Future<String> exportTemplate(String name) async {
    final writer = noteWriter;
    if (writer == null) throw StateError('Note writer is not configured');
    final safeName = name
        .trim()
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    final path = 'Templates/Reports/${safeName.isEmpty ? 'Report' : safeName}.md';
    final source = '''---
type: report-template
layout_version: ${layout.version}
created: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}
tags: [report-template]
---

# ${safeName.isEmpty ? 'Шаблон отчёта' : safeName}

```vellum-report
${layout.encode()}
```
''';
    await writer(path, source);
    return path;
  }

  Future<void> importTemplate(ParsedNote note) async {
    final match = RegExp(
      r'```vellum-report\s*\n([\s\S]*?)\n```',
    ).firstMatch(note.body);
    if (match == null) throw const FormatException('В шаблоне нет vellum-report');
    await saveLayout(ReportLayoutConfig.decode(match.group(1)!));
  }

  Future<void> ensurePeriodicReports({DateTime? now}) async {
    if (_creatingPeriodicReports || noteWriter == null || !_vault.ready) return;
    _creatingPeriodicReports = true;
    try {
      final today = DateTime(now?.year ?? DateTime.now().year, now?.month ?? DateTime.now().month, now?.day ?? DateTime.now().day);
      final thisWeek = today.subtract(Duration(days: today.weekday - 1));
      final previousWeek = ReportPeriod(
        start: thisWeek.subtract(const Duration(days: 7)),
        end: thisWeek.subtract(const Duration(milliseconds: 1)),
        type: 'weekly',
      );
      final thisMonth = DateTime(today.year, today.month);
      final previousMonth = ReportPeriod(
        start: DateTime(today.year, today.month - 1),
        end: thisMonth.subtract(const Duration(milliseconds: 1)),
        type: 'monthly',
      );
      for (final period in [previousWeek, previousMonth]) {
        if (_hasReport(period)) continue;
        final data = build(period);
        final entries = workEntries(period);
        final folder = period.type == 'weekly' ? 'Weekly' : 'Month';
        final name = period.type == 'weekly'
            ? 'Week-${DateFormat('yyyyMMdd').format(period.start)}'
            : DateFormat('MMMM yyyy', 'en').format(period.start);
        await noteWriter!(
          'Resources/Reports/$folder/$name.md',
          _service.markdown(
            entries,
            period,
            trainings: data.trainings.map((item) => item.note).toList(),
            reportData: data,
          ),
        );
      }
    } finally {
      _creatingPeriodicReports = false;
    }
  }

  bool _hasReport(ReportPeriod period) {
    const resolver = ReportPeriodResolver();
    return _vault.index.notes.any((note) {
      final current = resolver.fromNote(note);
      return current != null &&
          current.type == period.type &&
          current.start == period.start &&
          current.end.year == period.end.year &&
          current.end.month == period.end.month &&
          current.end.day == period.end.day;
    });
  }

  ReportMetricSnapshot evaluateMetric(
    ReportBlockDefinition block,
    ReportPeriod period,
  ) {
    final current = _metricRows(block, build(period));
    final comparison = block.comparison == ReportComparison.none
        ? const <Map<String, Object?>>[]
        : _metricRows(
            block,
            build(comparisonPeriod(period, block.comparison)),
          );
    final raw = _aggregateMetric(current, block);
    final previous = _aggregateMetric(comparison, block);
    var value = raw;
    final formula = block.metricFormula?.trim();
    if (formula != null && formula.isNotEmpty) {
      try {
        value = ReportFormula(formula).evaluate({
          'value': raw,
          'previous': previous,
          'delta': raw - previous,
        });
      } on FormatException {
        value = raw;
      }
    }
    final missing = current
        .where(
          (row) => block.requiredFields.any(
            (field) =>
                row[field] == null || row[field]?.toString().trim().isEmpty == true,
          ),
        )
        .length;
    return ReportMetricSnapshot(
      value: value,
      previous: previous,
      missingRows: missing,
    );
  }

  List<Map<String, Object?>> _metricRows(
    ReportBlockDefinition block,
    PeriodReportData data,
  ) {
    final rows = switch (block.source ?? ReportDataSource.daily) {
      ReportDataSource.daily => data.dailies
          .map(
            (item) => <String, Object?>{
              'steps': item.steps,
              'sleep': item.sleep,
              'calories': item.calories,
              'done': item.doneCount,
            },
          )
          .toList(),
      ReportDataSource.training => data.trainings
          .map(
            (item) => <String, Object?>{
              'duration': _number(
                _map(item.note.frontmatter['metrics'])['duration'],
              ),
              'load': _number(
                _map(item.note.frontmatter['assessment'])['load'],
              ),
              ...item.note.frontmatter,
            },
          )
          .toList(),
      ReportDataSource.task => data.tasks
          .map(
            (item) => <String, Object?>{
              'hours': item.hours,
              'completed': item.completed,
              'project': item.projects.join(', '),
            },
          )
          .toList(),
      ReportDataSource.note => data.notes
          .map(
            (item) => <String, Object?>{'area': item.area, 'title': item.note.title},
          )
          .toList(),
      ReportDataSource.habit => data.habits
          .map(
            (item) => <String, Object?>{
              'name': item.name,
              'completed': item.completed,
            },
          )
          .toList(),
      ReportDataSource.done => data.doneItems
          .map((item) => <String, Object?>{'text': item.text})
          .toList(),
    };
    return rows.where((row) {
      return block.filters.every((filter) {
        final left = row[filter.field];
        final right = filter.value;
        return switch (filter.operator) {
          'notEquals' => left?.toString() != right?.toString(),
          'contains' => left
              .toString()
              .toLowerCase()
              .contains(right.toString().toLowerCase()),
          'greater' => (_number(left) ?? 0) > (_number(right) ?? 0),
          'less' => (_number(left) ?? 0) < (_number(right) ?? 0),
          _ => left?.toString() == right?.toString(),
        };
      });
    }).map((row) {
      final formula = block.rowFormula?.trim();
      if (formula == null || formula.isEmpty) return row;
      try {
        return {...row, '_formula': ReportFormula(formula).evaluate(row)};
      } on FormatException {
        return {...row, '_formula': 0.0};
      }
    }).toList(growable: false);
  }

  double _aggregateMetric(
    List<Map<String, Object?>> rows,
    ReportBlockDefinition block,
  ) {
    if (block.aggregation == ReportAggregation.count) return rows.length.toDouble();
    final field = block.rowFormula?.trim().isNotEmpty == true
        ? '_formula'
        : block.valueField;
    final values = rows
        .map((row) => _number(row[field]))
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) return 0;
    return switch (block.aggregation) {
      ReportAggregation.count => rows.length.toDouble(),
      ReportAggregation.sum => values.fold<double>(0, (sum, item) => sum + item),
      ReportAggregation.average =>
        values.fold<double>(0, (sum, item) => sum + item) / values.length,
      ReportAggregation.minimum => values.reduce((a, b) => a < b ? a : b),
      ReportAggregation.maximum => values.reduce((a, b) => a > b ? a : b),
    };
  }

  Map<String, Object?> _map(Object? value) => value is Map
      ? Map<String, Object?>.from(value)
      : const <String, Object?>{};

  double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
}

class ReportMetricSnapshot {
  const ReportMetricSnapshot({
    required this.value,
    required this.previous,
    required this.missingRows,
  });

  final double value;
  final double previous;
  final int missingRows;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
