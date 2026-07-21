import 'package:intl/intl.dart';

import 'vault_models.dart';

class ReportPeriodResolver {
  const ReportPeriodResolver();

  ReportPeriod? fromNote(ParsedNote note) {
    final path = note.document.path;
    if (note.type != VaultEntityType.periodReport &&
        !path.startsWith('Resources/Reports/')) {
      return null;
    }

    final explicitStart = _date(note.frontmatter['period_start']);
    final explicitEnd = _date(note.frontmatter['period_end']);
    if (explicitStart != null && explicitEnd != null) {
      return _period(explicitStart, explicitEnd, _type(note));
    }

    final range = RegExp(
      r'(\d{1,2})\.(\d{1,2})\.(\d{4})\s*[—–-]\s*'
      r'(\d{1,2})\.(\d{1,2})\.(\d{4})',
    ).firstMatch(note.frontmatter['period']?.toString() ?? note.body);
    if (range != null) {
      return _period(
        DateTime(
          int.parse(range.group(3)!),
          int.parse(range.group(2)!),
          int.parse(range.group(1)!),
        ),
        DateTime(
          int.parse(range.group(6)!),
          int.parse(range.group(5)!),
          int.parse(range.group(4)!),
        ),
        _type(note),
      );
    }

    final scriptDates = RegExp(
      r'dv\.date\(["\x27](\d{4}-\d{2}-\d{2})["\x27]\)',
    ).allMatches(note.body).map((match) => DateTime.parse(match.group(1)!));
    final dates = scriptDates.take(2).toList(growable: false);
    if (dates.length == 2) return _period(dates[0], dates[1], _type(note));

    final year = int.tryParse(
      note.frontmatter['year']?.toString() ??
          RegExp(r'Year/(\d{4})\.md$').firstMatch(path)?.group(1) ??
          '',
    );
    if (year != null) {
      return ReportPeriod(
        start: DateTime(year),
        end: DateTime(year + 1).subtract(const Duration(milliseconds: 1)),
        type: 'yearly',
      );
    }
    return null;
  }

  ReportPeriod _period(DateTime start, DateTime end, String type) =>
      ReportPeriod(
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
        type: type,
      );

  String _type(ParsedNote note) {
    final value = note.frontmatter['report_type']?.toString();
    if (const {'weekly', 'monthly', 'yearly'}.contains(value)) return value!;
    final path = note.document.path;
    if (path.contains('/Weekly/')) return 'weekly';
    if (path.contains('/Year/')) return 'yearly';
    return 'monthly';
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final iso = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(text);
    return DateTime.tryParse(iso?.group(1) ?? text);
  }
}

class ReportDateInfo {
  const ReportDateInfo({
    required this.date,
    required this.source,
    required this.fallback,
  });
  final DateTime date;
  final String source;
  final bool fallback;
}

class DailyReportItem {
  const DailyReportItem({
    required this.note,
    required this.dateInfo,
    required this.steps,
    required this.sleep,
    required this.calories,
    required this.doneCount,
  });
  final ParsedNote note;
  final ReportDateInfo dateInfo;
  final double? steps;
  final double? sleep;
  final double? calories;
  final int doneCount;
}

class TrainingReportItem {
  const TrainingReportItem({required this.note, required this.dateInfo});
  final ParsedNote note;
  final ReportDateInfo dateInfo;
}

class DoneReportItem {
  const DoneReportItem({
    required this.note,
    required this.date,
    required this.text,
  });
  final ParsedNote note;
  final DateTime date;
  final String text;
}

class HabitReportItem {
  const HabitReportItem({
    required this.name,
    required this.completed,
    required this.date,
  });
  final String name;
  final bool completed;
  final DateTime date;
}

class TaskReportItem {
  const TaskReportItem({
    required this.kind,
    required this.note,
    required this.name,
    required this.dateInfo,
    required this.completed,
    required this.projects,
    required this.hours,
  });
  final String kind;
  final ParsedNote note;
  final String name;
  final ReportDateInfo dateInfo;
  final bool completed;
  final List<String> projects;
  final double hours;
}

class ContentNoteReportItem {
  const ContentNoteReportItem({
    required this.note,
    required this.dateInfo,
    required this.area,
  });
  final ParsedNote note;
  final ReportDateInfo dateInfo;
  final String area;
}

class ReportBucket {
  const ReportBucket({
    required this.label,
    required this.start,
    required this.end,
  });
  final String label;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) =>
      !value.isBefore(start) && !value.isAfter(end);
}

class PeriodReportData {
  const PeriodReportData({
    required this.period,
    required this.dailies,
    required this.trainings,
    required this.tasks,
    required this.notes,
    required this.doneItems,
    required this.habits,
    required this.buckets,
  });
  final ReportPeriod period;
  final List<DailyReportItem> dailies;
  final List<TrainingReportItem> trainings;
  final List<TaskReportItem> tasks;
  final List<ContentNoteReportItem> notes;
  final List<DoneReportItem> doneItems;
  final List<HabitReportItem> habits;
  final List<ReportBucket> buckets;

  int get periodDays =>
      DateTime(period.end.year, period.end.month, period.end.day)
          .difference(
            DateTime(period.start.year, period.start.month, period.start.day),
          )
          .inDays +
      1;
  double get steps => _sum(dailies.map((item) => item.steps));
  double? get averageSteps => _average(dailies.map((item) => item.steps));
  double? get averageSleep => _average(dailies.map((item) => item.sleep));
  double? get calories {
    final values = dailies.map((item) => item.calories).whereType<double>();
    return values.isEmpty
        ? null
        : values.fold<double>(0, (sum, item) => sum + item);
  }

  double? get averageCalories => _average(dailies.map((item) => item.calories));
  double get trainingDuration => _sum(
    trainings.map(
      (item) => _number(_map(item.note.frontmatter['metrics'])['duration']),
    ),
  );
  int get completedTasks => tasks.where((item) => item.completed).length;
  int get fallbackNotes => notes.where((item) => item.dateInfo.fallback).length;
  int get missingSteps => dailies.where((item) => item.steps == null).length;
  int get missingSleep => dailies.where((item) => item.sleep == null).length;
  int get missingCalories =>
      dailies.where((item) => item.calories == null).length;

  static double _sum(Iterable<Object?> values) =>
      values.fold<double>(0, (total, value) => total + (_number(value) ?? 0));

  static double? _average(Iterable<Object?> values) {
    final valid = values.map(_number).whereType<double>().toList();
    return valid.isEmpty
        ? null
        : valid.fold<double>(0, (sum, value) => sum + value) / valid.length;
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : const {};

  static double? _number(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    final match = RegExp(
      r'-?\d+(?:[.,]\d+)?',
    ).firstMatch(value.toString().replaceAll(',', '.'));
    return match == null ? null : double.tryParse(match.group(0)!);
  }
}

class PeriodReportDataBuilder {
  const PeriodReportDataBuilder();

  PeriodReportData build(Iterable<ParsedNote> allNotes, ReportPeriod period) {
    final notes = allNotes.toList(growable: false);
    final dailyEntries = <(ParsedNote, ReportDateInfo)>[];
    final trainingEntries = <(ParsedNote, ReportDateInfo)>[];
    for (final note in notes) {
      final dateInfo = _effectiveDate(note, allowModified: false);
      if (dateInfo == null || !_inPeriod(dateInfo.date, period)) continue;
      if (_isDaily(note)) dailyEntries.add((note, dateInfo));
      if (_isTraining(note)) trainingEntries.add((note, dateInfo));
    }
    dailyEntries.sort((a, b) => a.$2.date.compareTo(b.$2.date));
    trainingEntries.sort((a, b) => a.$2.date.compareTo(b.$2.date));

    final doneItems = <DoneReportItem>[];
    final habits = <HabitReportItem>[];
    final dailies = <DailyReportItem>[];
    for (final entry in dailyEntries) {
      final noteDone = _listItemsInSection(entry.$1.body, 'что было сделано')
          .map(
            (text) =>
                DoneReportItem(note: entry.$1, date: entry.$2.date, text: text),
          )
          .toList(growable: false);
      doneItems.addAll(noteDone);
      for (final task in _tasksWithSections(entry.$1)) {
        if (task.section.contains('привычк')) {
          habits.add(
            HabitReportItem(
              name: task.task.text,
              completed: task.task.completed,
              date: entry.$2.date,
            ),
          );
        }
      }
      dailies.add(
        DailyReportItem(
          note: entry.$1,
          dateInfo: entry.$2,
          steps: _number(entry.$1.frontmatter['step']),
          sleep: _number(entry.$1.frontmatter['sleep']),
          calories: _number(entry.$1.frontmatter['calories']),
          doneCount: noteDone.length,
        ),
      );
    }

    return PeriodReportData(
      period: period,
      dailies: dailies,
      trainings: trainingEntries
          .map(
            (entry) => TrainingReportItem(note: entry.$1, dateInfo: entry.$2),
          )
          .toList(growable: false),
      tasks: _collectTasks(notes, period),
      notes: _collectContentNotes(notes, period),
      doneItems: doneItems,
      habits: habits,
      buckets: _buckets(period),
    );
  }

  List<TaskReportItem> _collectTasks(
    List<ParsedNote> notes,
    ReportPeriod period,
  ) {
    final result = <TaskReportItem>[];
    for (final note in notes) {
      final standalone =
          _isStandaloneTask(note) && !_isProjectIndex(note.document.path);
      if (standalone) {
        final dateInfo = _effectiveDate(note, allowModified: false);
        if (dateInfo == null || !_inPeriod(dateInfo.date, period)) continue;
        final status =
            note.frontmatter['status']?.toString().toLowerCase() ?? '';
        result.add(
          TaskReportItem(
            kind: 'Файл',
            note: note,
            name: note.title,
            dateInfo: dateInfo,
            completed:
                note.frontmatter['complete'] == true ||
                {
                  'done',
                  'complete',
                  'completed',
                  'готово',
                  'выполнено',
                }.contains(status),
            projects: _projectsOf(note),
            hours: _number(note.frontmatter['hours']) ?? 0,
          ),
        );
        continue;
      }
      if (_isExcludedPath(note.document.path)) continue;
      final dateInfo = _effectiveDate(note, allowModified: false);
      if (dateInfo == null || !_inPeriod(dateInfo.date, period)) continue;
      for (final task in _tasksWithSections(note)) {
        if (task.section.contains('привычк')) continue;
        result.add(
          TaskReportItem(
            kind: 'Чекбокс',
            note: note,
            name: task.task.text.replaceAll(_tagPattern, '').trim(),
            dateInfo: dateInfo,
            completed: task.task.completed,
            projects: _projectsOf(note, task.task.text),
            hours: _hoursFromText(task.task.text),
          ),
        );
      }
    }
    result.sort(
      (a, b) => a.dateInfo.date.compareTo(b.dateInfo.date) != 0
          ? a.dateInfo.date.compareTo(b.dateInfo.date)
          : (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0),
    );
    return result;
  }

  List<ContentNoteReportItem> _collectContentNotes(
    List<ParsedNote> notes,
    ReportPeriod period,
  ) {
    final result = <ContentNoteReportItem>[];
    for (final note in notes.where(_isContentNote)) {
      final dateInfo = _effectiveDate(note, allowModified: true);
      if (dateInfo == null || !_inPeriod(dateInfo.date, period)) continue;
      result.add(
        ContentNoteReportItem(
          note: note,
          dateInfo: dateInfo,
          area: _noteArea(note.document.path),
        ),
      );
    }
    result.sort((a, b) => a.dateInfo.date.compareTo(b.dateInfo.date));
    return result;
  }

  ReportDateInfo? _effectiveDate(
    ParsedNote note, {
    required bool allowModified,
  }) {
    for (final field in const ['created', 'date', 'added']) {
      final value = _date(note.frontmatter[field]);
      if (value != null) {
        return ReportDateInfo(
          date: value,
          source: field,
          fallback: field != 'created',
        );
      }
    }
    if (!allowModified) return null;
    return ReportDateInfo(
      date: _day(note.document.modifiedAt.toLocal()),
      source: 'file.ctime',
      fallback: true,
    );
  }

  List<ReportBucket> _buckets(ReportPeriod period) {
    final result = <ReportBucket>[];
    if (period.type == 'yearly') {
      var cursor = DateTime(period.start.year, period.start.month);
      while (!cursor.isAfter(period.end)) {
        final end = DateTime(
          cursor.year,
          cursor.month + 1,
        ).subtract(const Duration(milliseconds: 1));
        result.add(
          ReportBucket(
            label: DateFormat('LLL', 'ru').format(cursor),
            start: cursor,
            end: end,
          ),
        );
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
      return result;
    }
    var cursor = _day(period.start);
    while (!cursor.isAfter(period.end)) {
      result.add(
        ReportBucket(
          label: DateFormat('dd LLL', 'ru').format(cursor),
          start: cursor,
          end: cursor
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1)),
        ),
      );
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  List<_TaskWithSection> _tasksWithSections(ParsedNote note) {
    final lines = note.body.split(RegExp(r'\r?\n'));
    final headings = <int, String>{};
    var section = '';
    for (var index = 0; index < lines.length; index++) {
      final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(lines[index]);
      if (heading != null) section = heading.group(1)!.trim().toLowerCase();
      headings[index] = section;
    }
    return note.tasks
        .map(
          (task) =>
              _TaskWithSection(task: task, section: headings[task.line] ?? ''),
        )
        .toList(growable: false);
  }

  List<String> _listItemsInSection(String body, String sectionName) {
    final result = <String>[];
    var section = '';
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (heading != null) {
        section = heading.group(1)!.trim().toLowerCase();
        continue;
      }
      if (!section.contains(sectionName)) continue;
      final item = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
      if (item != null) result.add(item.group(1)!.trim());
    }
    return result;
  }

  List<String> _projectsOf(ParsedNote note, [String text = '']) {
    final values = <String>{};
    final raw = note.frontmatter['project'];
    if (raw is List) {
      values.addAll(raw.map((item) => item.toString()));
    } else if (raw != null && raw.toString().trim().isNotEmpty) {
      values.add(raw.toString());
    }
    values.addAll(
      _tagPattern.allMatches(text).map((match) => match.group(0)!.substring(1)),
    );
    return values.where((item) => item.isNotEmpty).toList(growable: false);
  }

  bool _isDaily(ParsedNote note) =>
      note.document.path.startsWith('Daily/') ||
      note.document.path.contains('/Daily/');

  bool _isTraining(ParsedNote note) =>
      note.type == VaultEntityType.training ||
      note.document.path.contains('/Health/Traning/');

  bool _isStandaloneTask(ParsedNote note) =>
      note.tags.map((item) => item.toLowerCase()).contains('task') ||
      note.document.path.startsWith('Tasks/') ||
      note.document.path.contains('/Tasks/');

  bool _isProjectIndex(String path) =>
      RegExp(r'(^|/)_(?:Project|Projects)\.md$').hasMatch(path);

  bool _isExcludedPath(String path) =>
      _isProjectIndex(path) ||
      path.startsWith('Templates/') ||
      path.startsWith('settings/') ||
      path.startsWith('Resources/Reports/') ||
      path.startsWith('Resources/Scripts/') ||
      path.contains('/Daily/') ||
      path.startsWith('Daily/') ||
      path.contains('/Tasks/') ||
      path.startsWith('Tasks/') ||
      path.contains('/Health/Traning/') ||
      path.contains('/Health/Health control/');

  bool _isContentNote(ParsedNote note) {
    final path = note.document.path;
    if (_isExcludedPath(path) ||
        note.type == VaultEntityType.periodReport ||
        note.type == VaultEntityType.training ||
        _isStandaloneTask(note)) {
      return false;
    }
    return const [
      'Projects',
      'Areas',
      'Resources',
      'Входящие',
    ].any((root) => path.startsWith('$root/') || path.contains('/$root/'));
  }

  String _noteArea(String path) {
    if (path.startsWith('Входящие/') || path.contains('/Входящие/')) {
      return 'Входящие';
    }
    for (final area in const ['Projects', 'Areas', 'Resources']) {
      if (path.startsWith('$area/') || path.contains('/$area/')) return area;
    }
    return 'Другое';
  }

  bool _inPeriod(DateTime value, ReportPeriod period) =>
      !value.isBefore(period.start) && !value.isAfter(period.end);

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime? _date(Object? value) {
    if (value is DateTime) return _day(value);
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final dotted = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(text);
    if (dotted != null) {
      return DateTime(
        int.parse(dotted.group(3)!),
        int.parse(dotted.group(2)!),
        int.parse(dotted.group(1)!),
      );
    }
    final iso = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(text);
    return DateTime.tryParse(iso?.group(1) ?? text);
  }

  double _hoursFromText(String text) {
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*ч',
      caseSensitive: false,
    ).firstMatch(text);
    return _number(match?.group(1)) ?? 0;
  }

  double? _number(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(value.toString());
    return match == null
        ? null
        : double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }

  static final _tagPattern = RegExp(r'#[\p{L}\p{N}_-]+', unicode: true);
}

class _TaskWithSection {
  const _TaskWithSection({required this.task, required this.section});
  final MarkdownTask task;
  final String section;
}
