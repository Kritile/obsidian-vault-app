import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/vault/period_report_data.dart';
import '../../core/vault/report_layout.dart';
import '../../core/vault/report_service.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/page_scaffold.dart';
import '../../shared/app_motion.dart';
import '../vault/note_screen.dart';
import 'report_layout_editor_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class PeriodReportView extends ConsumerWidget {
  const PeriodReportView({required this.period, super.key});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportControllerProvider);
    final data = reports.build(period);
    void open(ParsedNote note) => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteScreen(note: note)));
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 380 ? 10 : 20,
        12,
        MediaQuery.sizeOf(context).width < 380 ? 10 : 20,
        30,
      ),
      children: [
        _ReportLayoutContent(
          data: data,
          blocks: reports.layout.blocks,
          onOpen: open,
        ),
      ],
    );
  }
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _type = 'monthly';
  DateTime _anchor = DateTime.now();
  final _service = ReportService();

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportControllerProvider);
    final period = _period();
    final data = reports.build(period);
    final workEntries = reports.workEntries(period);
    return PageScaffold(
      title: 'Отчёты',
      subtitle:
          '${DateFormat('dd.MM.yyyy').format(period.start)} — '
          '${DateFormat('dd.MM.yyyy').format(period.end)}',
      actions: [
        IconButton(
          tooltip: 'Настроить блоки',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReportLayoutEditorScreen()),
          ),
          icon: const Icon(Icons.dashboard_customize_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'Экспорт',
          icon: const Icon(Icons.ios_share),
          onSelected: (value) => _export(value, workEntries, data, period),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'md',
              child: Text('Сохранить Markdown в vault'),
            ),
            PopupMenuItem(value: 'pdf', child: Text('Экспорт PDF')),
            PopupMenuItem(value: 'csv', child: Text('Экспорт CSV')),
          ],
        ),
      ],
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 380 ? 10 : 20,
          0,
          MediaQuery.sizeOf(context).width < 380 ? 10 : 20,
          30,
        ),
        children: [
          _PeriodControls(
            type: _type,
            onType: (value) => setState(() => _type = value),
            onPrevious: () => setState(() => _anchor = _shift(-1)),
            onToday: () => setState(() => _anchor = DateTime.now()),
            onNext: () => setState(() => _anchor = _shift(1)),
          ),
          const SizedBox(height: 18),
          _ReportLayoutContent(
            data: data,
            blocks: reports.layout.blocks,
            onOpen: _openNote,
          ),
        ],
      ),
    );
  }

  void _openNote(ParsedNote note) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteScreen(note: note)));

  Future<void> _export(
    String type,
    List<WorkEntry> entries,
    PeriodReportData data,
    ReportPeriod period,
  ) async {
    final trainings = data.trainings.map((item) => item.note).toList();
    String? result;
    if (type == 'csv') {
      result = await _service.exportCsv(
        entries,
        period,
        trainings: trainings,
        reportData: data,
      );
    }
    if (type == 'pdf') {
      result = await _service.exportPdf(
        entries,
        period,
        trainings: trainings,
        reportData: data,
      );
    }
    if (type == 'md') {
      final folder = switch (period.type) {
        'weekly' => 'Weekly',
        'yearly' => 'Year',
        _ => 'Month',
      };
      final name = switch (period.type) {
        'weekly' => 'Week-${DateFormat('yyyyMMdd').format(period.start)}',
        'yearly' => DateFormat('yyyy').format(period.start),
        _ => DateFormat('MMMM yyyy', 'en').format(period.start),
      };
      final path = 'Resources/Reports/$folder/$name.md';
      await ref
          .read(syncControllerProvider)
          .saveNote(
            path,
            _service.markdown(
              entries,
              period,
              trainings: trainings,
              reportData: data,
            ),
          );
      result = path;
    }
    if (mounted && result != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Сохранено: $result')));
    }
  }

  ReportPeriod _period() {
    if (_type == 'weekly') {
      final start = DateTime(
        _anchor.year,
        _anchor.month,
        _anchor.day,
      ).subtract(Duration(days: _anchor.weekday - 1));
      return ReportPeriod(
        start: start,
        end: start.add(const Duration(days: 6, hours: 23, minutes: 59)),
        type: _type,
      );
    }
    if (_type == 'yearly') {
      return ReportPeriod(
        start: DateTime(_anchor.year),
        end: DateTime(
          _anchor.year + 1,
        ).subtract(const Duration(milliseconds: 1)),
        type: _type,
      );
    }
    return ReportPeriod(
      start: DateTime(_anchor.year, _anchor.month),
      end: DateTime(
        _anchor.year,
        _anchor.month + 1,
      ).subtract(const Duration(milliseconds: 1)),
      type: _type,
    );
  }

  DateTime _shift(int direction) => switch (_type) {
    'weekly' => _anchor.add(Duration(days: 7 * direction)),
    'yearly' => DateTime(_anchor.year + direction, _anchor.month, 1),
    _ => DateTime(_anchor.year, _anchor.month + direction, 1),
  };
}

class _PeriodControls extends StatelessWidget {
  const _PeriodControls({
    required this.type,
    required this.onType,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
  });
  final String type;
  final ValueChanged<String> onType;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'weekly', label: Text('Неделя')),
            ButtonSegment(value: 'monthly', label: Text('Месяц')),
            ButtonSegment(value: 'yearly', label: Text('Год')),
          ],
          selected: {type},
          onSelectionChanged: (value) => onType(value.first),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Предыдущий период',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Текущий период',
          onPressed: onToday,
          icon: const Icon(Icons.today),
        ),
        IconButton(
          tooltip: 'Следующий период',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class _ReportLayoutContent extends StatelessWidget {
  const _ReportLayoutContent({
    required this.data,
    required this.blocks,
    required this.onOpen,
  });

  final PeriodReportData data;
  final List<ReportBlockDefinition> blocks;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = blocks.where((item) => item.visible).toList();
    final children = <Widget>[];
    for (var index = 0; index < visible.length; index++) {
      final block = visible[index];
      if (block.kind == 'quality' &&
          data.missingSteps == 0 &&
          data.missingSleep == 0 &&
          data.missingCalories == 0 &&
          data.fallbackNotes == 0) {
        continue;
      }
      final child = switch (block.kind) {
        'overview' => _Overview(data: data),
        'daily' => _DailySection(data: data, onOpen: onOpen),
        'sports' => _SportsSection(data: data, onOpen: onOpen),
        'tasks' => _TasksSection(data: data, onOpen: onOpen),
        'notes' => _NotesSection(data: data, onOpen: onOpen),
        'quality' => _DataQuality(data: data),
        _ => _CustomReportBlock(block: block, data: data, onOpen: onOpen),
      };
      children.add(_AnimatedReportSection(index: index, child: child));
      if (index != visible.length - 1) children.add(const SizedBox(height: 20));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _CustomReportBlock extends StatelessWidget {
  const _CustomReportBlock({
    required this.block,
    required this.data,
    required this.onOpen,
  });

  final ReportBlockDefinition block;
  final PeriodReportData data;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = _sourceRows(data, block.source ?? ReportDataSource.daily)
        .where((row) => block.filters.every((filter) => _matches(row, filter)))
        .map((row) {
          final formula = block.rowFormula?.trim();
          if (formula == null || formula.isEmpty) return row;
          try {
            return {...row, '_formula': ReportFormula(formula).evaluate(row)};
          } on FormatException {
            return {...row, '_formula': 0.0};
          }
        })
        .toList(growable: false);
    if (rows.isEmpty) {
      return _Section(
        title: block.title,
        child: const _Empty('По условиям блока данных не найдено.'),
      );
    }
    final fields = block.tableFields.isEmpty
        ? _defaultFields(block.source ?? ReportDataSource.daily)
        : block.tableFields;
    if (block.visualization == ReportVisualization.table) {
      return _Section(
        title: block.title,
        child: _ReportTable(
          columns: fields.map(_fieldLabel).toList(),
          rows: rows
              .map(
                (row) => fields
                    .map((field) => _displayField(row[field]))
                    .toList(growable: false),
              )
              .toList(growable: false),
          onRowTap: (index) {
            final note = rows[index]['_note'];
            if (note is ParsedNote) onOpen(note);
          },
        ),
      );
    }
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final raw = block.groupBy == null || block.groupBy!.isEmpty
          ? 'Все'
          : row[block.groupBy!];
      final key = raw is DateTime ? _date(raw) : _displayField(raw);
      grouped.putIfAbsent(key, () => []).add(row);
    }
    final values = <String, double>{
      for (final entry in grouped.entries)
        entry.key: _aggregate(entry.value, block),
    };
    if (block.visualization == ReportVisualization.kpi) {
      final total = _aggregate(rows, block);
      return _Section(
        title: block.title,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (context, value, _) => Text(
                _format(value, value % 1 == 0 ? 0 : 1),
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
          ),
        ),
      );
    }
    final labels = values.keys.toList();
    final series = _Series(
      block.title,
      values.values.map<double?>((item) => item).toList(),
      const Color(0xff6d5dfc),
    );
    final chart = switch (block.visualization) {
      ReportVisualization.line => _LineChartCard(
        title: block.title,
        labels: labels,
        series: [series],
      ),
      ReportVisualization.pie => _PieChartCard(
        title: block.title,
        values: values,
      ),
      _ => _BarChartCard(title: block.title, labels: labels, series: [series]),
    };
    return chart;
  }

  double _aggregate(
    List<Map<String, Object?>> rows,
    ReportBlockDefinition block,
  ) {
    if (block.aggregation == ReportAggregation.count) {
      return rows.length.toDouble();
    }
    final field = block.rowFormula?.trim().isNotEmpty == true
        ? '_formula'
        : block.valueField;
    final values = rows
        .map((row) => _number(field == null ? null : row[field]))
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    return switch (block.aggregation) {
      ReportAggregation.sum => values.fold<double>(
        0,
        (sum, item) => sum + item,
      ),
      ReportAggregation.average =>
        values.fold<double>(0, (sum, item) => sum + item) / values.length,
      ReportAggregation.minimum => values.reduce(math.min),
      ReportAggregation.maximum => values.reduce(math.max),
      ReportAggregation.count => rows.length.toDouble(),
    };
  }
}

List<Map<String, Object?>> _sourceRows(
  PeriodReportData data,
  ReportDataSource source,
) => switch (source) {
  ReportDataSource.daily =>
    data.dailies
        .map(
          (item) => <String, Object?>{
            'date': item.dateInfo.date,
            'title': item.note.title,
            'steps': item.steps,
            'sleep': item.sleep,
            'calories': item.calories,
            'done': item.doneCount,
            '_note': item.note,
          },
        )
        .toList(),
  ReportDataSource.training => data.trainings.map((item) {
    final metrics = _map(item.note.frontmatter['metrics']);
    final assessment = _map(item.note.frontmatter['assessment']);
    return <String, Object?>{
      'date': item.dateInfo.date,
      'title': item.note.title,
      'sport': _sportName(item.note),
      ...metrics,
      ...assessment,
      '_note': item.note,
    };
  }).toList(),
  ReportDataSource.task =>
    data.tasks
        .map(
          (item) => <String, Object?>{
            'date': item.dateInfo.date,
            'title': item.name,
            'completed': item.completed,
            'project': item.projects.join(', '),
            'hours': item.hours,
            'kind': item.kind,
            '_note': item.note,
          },
        )
        .toList(),
  ReportDataSource.note =>
    data.notes
        .map(
          (item) => <String, Object?>{
            'date': item.dateInfo.date,
            'title': item.note.title,
            'area': item.area,
            'date_source': item.dateInfo.source,
            '_note': item.note,
          },
        )
        .toList(),
  ReportDataSource.habit =>
    data.habits
        .map(
          (item) => <String, Object?>{
            'date': item.date,
            'title': item.name,
            'completed': item.completed,
          },
        )
        .toList(),
  ReportDataSource.done =>
    data.doneItems
        .map(
          (item) => <String, Object?>{
            'date': item.date,
            'title': item.text,
            '_note': item.note,
          },
        )
        .toList(),
};

List<String> _defaultFields(ReportDataSource source) => switch (source) {
  ReportDataSource.daily => const [
    'date',
    'title',
    'steps',
    'sleep',
    'calories',
    'done',
  ],
  ReportDataSource.training => const [
    'date',
    'sport',
    'duration',
    'avg_hr',
    'load',
  ],
  ReportDataSource.task => const [
    'date',
    'title',
    'completed',
    'project',
    'hours',
  ],
  ReportDataSource.note => const ['date', 'title', 'area', 'date_source'],
  ReportDataSource.habit => const ['date', 'title', 'completed'],
  ReportDataSource.done => const ['date', 'title'],
};

bool _matches(Map<String, Object?> row, ReportFilter filter) {
  final actual = row[filter.field];
  final expected = filter.value;
  return switch (filter.operator) {
    'notEquals' => actual?.toString() != expected?.toString(),
    'contains' => actual.toString().toLowerCase().contains(
      expected.toString().toLowerCase(),
    ),
    'greater' => (_number(actual) ?? 0) > (_number(expected) ?? 0),
    'less' => (_number(actual) ?? 0) < (_number(expected) ?? 0),
    'notEmpty' => actual != null && actual.toString().trim().isNotEmpty,
    _ => actual?.toString().toLowerCase() == expected?.toString().toLowerCase(),
  };
}

String _displayField(Object? value) {
  if (value == null || value.toString().isEmpty) return '—';
  if (value is DateTime) return _date(value);
  if (value is bool) return value ? 'Да' : 'Нет';
  return value.toString();
}

String _fieldLabel(String field) =>
    const {
      'date': 'Дата',
      'title': 'Название',
      'steps': 'Шаги',
      'sleep': 'Сон',
      'calories': 'Калории',
      'done': 'Сделано',
      'sport': 'Вид спорта',
      'duration': 'Минуты',
      'avg_hr': 'Средний пульс',
      'max_hr': 'Макс. пульс',
      'load': 'Нагрузка',
      'completed': 'Выполнено',
      'project': 'Проект',
      'hours': 'Часы',
      'area': 'Раздел',
      'date_source': 'Источник даты',
    }[field] ??
    field;

class _Overview extends StatelessWidget {
  const _Overview({required this.data});
  final PeriodReportData data;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'Заполнено дней',
        '${data.dailies.length}',
        '${data.periodDays} в периоде',
        Icons.calendar_month,
      ),
      (
        'Шаги',
        _format(data.steps, 0),
        'в среднем ${_format(data.averageSteps, 0)}',
        Icons.directions_walk,
      ),
      (
        'Средний сон',
        data.averageSleep == null ? '—' : '${_format(data.averageSleep, 1)} ч',
        '${data.dailies.where((item) => item.sleep != null).length} значений',
        Icons.bedtime_outlined,
      ),
      (
        'Сожжено калорий',
        data.calories == null ? '—' : '${_format(data.calories, 0)} ккал',
        'в среднем ${_format(data.averageCalories, 0)} ккал/день',
        Icons.local_fire_department_outlined,
      ),
      (
        'Тренировки',
        '${data.trainings.length}',
        '${_format(data.trainingDuration, 0)} мин',
        Icons.fitness_center,
      ),
      (
        'Задачи',
        '${data.completedTasks}/${data.tasks.length}',
        'выполнено / всего',
        Icons.task_alt,
      ),
      (
        'Новые заметки',
        '${data.notes.length}',
        '${data.fallbackNotes} с резервной датой',
        Icons.note_add_outlined,
      ),
    ];
    return _Section(
      title: 'Обзор',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 390
              ? constraints.maxWidth
              : constraints.maxWidth < 820
              ? (constraints.maxWidth - 10) / 2
              : (constraints.maxWidth - 30) / 4;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map(
                  (item) => SizedBox(
                    width: width,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            CircleAvatar(child: Icon(item.$4)),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  Text(item.$1),
                                  Text(
                                    item.$3,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class _DailySection extends StatelessWidget {
  const _DailySection({required this.data, required this.onOpen});
  final PeriodReportData data;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.dailies.isEmpty) {
      return const _Section(
        title: 'Ежедневники',
        child: _Empty('За период ежедневных заметок не найдено.'),
      );
    }
    final stepValues = [
      for (final bucket in data.buckets)
        _nullableSum(
          data.dailies
              .where((item) => bucket.contains(item.dateInfo.date))
              .map((item) => item.steps),
          zeroIsNull: true,
        ),
    ];
    final sleepValues = [
      for (final bucket in data.buckets)
        _average(
          data.dailies
              .where((item) => bucket.contains(item.dateInfo.date))
              .map((item) => item.sleep),
        ),
    ];
    final calorieValues = [
      for (final bucket in data.buckets)
        _nullableSum(
          data.dailies
              .where((item) => bucket.contains(item.dateInfo.date))
              .map((item) => item.calories),
        ),
    ];
    final habits = _groupBy(data.habits, (item) => item.name);
    return _Section(
      title: 'Ежедневники',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportTable(
            columns: const [
              'Дата',
              'Заметка',
              'Шаги',
              'Сон',
              'Сожжено, ккал',
              'Сделано',
            ],
            rows: data.dailies
                .map(
                  (item) => [
                    _date(item.dateInfo.date),
                    item.note.title,
                    _format(item.steps, 0),
                    item.sleep == null ? '—' : '${_format(item.sleep, 1)} ч',
                    _format(item.calories, 0),
                    '${item.doneCount}',
                  ],
                )
                .toList(growable: false),
            onRowTap: (index) => onOpen(data.dailies[index].note),
          ),
          const SizedBox(height: 12),
          _ResponsiveCharts(
            first: _LineChartCard(
              title: 'Шаги',
              labels: data.buckets.map((item) => item.label).toList(),
              series: [_Series('Шаги', stepValues, const Color(0xff4dabf7))],
            ),
            second: _LineChartCard(
              title: 'Сон, ч',
              labels: data.buckets.map((item) => item.label).toList(),
              series: [_Series('Сон, ч', sleepValues, const Color(0xff845ef7))],
            ),
          ),
          const SizedBox(height: 12),
          _BarChartCard(
            title: 'Сожжённые калории',
            labels: data.buckets.map((item) => item.label).toList(),
            series: [
              _Series('Сожжено, ккал', calorieValues, const Color(0xffff922b)),
            ],
          ),
          if (habits.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BarChartCard(
              title: 'Выполнение привычек, %',
              labels: habits.keys.toList(),
              maxY: 100,
              series: [
                _Series(
                  'Выполнение, %',
                  habits.values
                      .map(
                        (items) =>
                            items.where((item) => item.completed).length /
                            items.length *
                            100,
                      )
                      .map<double?>((value) => value)
                      .toList(),
                  const Color(0xff63e6be),
                ),
              ],
            ),
          ],
          if (data.doneItems.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Что было сделано · ${data.doneItems.length}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _ReportTable(
              columns: const ['Дата', 'Источник', 'Запись'],
              rows: data.doneItems
                  .map((item) => [_date(item.date), item.note.title, item.text])
                  .toList(growable: false),
              onRowTap: (index) => onOpen(data.doneItems[index].note),
            ),
          ],
        ],
      ),
    );
  }
}

class _SportsSection extends StatefulWidget {
  const _SportsSection({required this.data, required this.onOpen});
  final PeriodReportData data;
  final ValueChanged<ParsedNote> onOpen;

  @override
  State<_SportsSection> createState() => _SportsSectionState();
}

class _SportsSectionState extends State<_SportsSection> {
  var _sortColumnIndex = 0;
  var _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.trainings.isEmpty) {
      return const _Section(
        title: 'Спорт',
        child: _Empty('За период тренировок не найдено.'),
      );
    }
    final durationValues = <double?>[];
    final loadValues = <double?>[];
    for (final bucket in data.buckets) {
      final entries = data.trainings.where(
        (item) => bucket.contains(item.dateInfo.date),
      );
      durationValues.add(
        _sum(
          entries.map(
            (item) =>
                _number(_map(item.note.frontmatter['metrics'])['duration']),
          ),
        ),
      );
      loadValues.add(
        _sum(
          entries.map(
            (item) =>
                _number(_map(item.note.frontmatter['assessment'])['load']),
          ),
        ),
      );
    }
    final bySport = _groupBy(data.trainings, (item) => _sportName(item.note));
    final trainings = [...data.trainings]..sort(_compareTrainings);
    return _Section(
      title: 'Спорт',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            onSort: (columnIndex, ascending) => setState(() {
              _sortColumnIndex = columnIndex;
              _sortAscending = ascending;
            }),
            columns: const [
              'Дата',
              'Тренировка',
              'Вид',
              'Мин',
              'Нагрузка',
              'Пульс',
              'Ккал',
              'Aerobic TE',
              'Anaerobic TE',
              'TRIMP',
              'Восстановление',
              'Дополнительно',
            ],
            rows: trainings
                .map((item) {
                  final note = item.note;
                  final metrics = _map(note.frontmatter['metrics']);
                  final assessment = _map(note.frontmatter['assessment']);
                  final avg = _number(metrics['avg_hr']);
                  final max = _number(metrics['max_hr']);
                  return [
                    _date(item.dateInfo.date),
                    note.title,
                    _sportName(note),
                    _format(_number(metrics['duration']), 1),
                    _format(_number(assessment['load']), 0),
                    avg == null && max == null
                        ? '—'
                        : '${_format(avg, 0)}/${_format(max, 0)}',
                    _format(_number(metrics['calories']), 0),
                    _format(_number(metrics['aerobic_te']), 1),
                    _format(_number(metrics['anaerobic_te']), 1),
                    _format(_number(assessment['trimp']), 1),
                    assessment['recovery_hours'] == null
                        ? '—'
                        : '${_format(_number(assessment['recovery_hours']), 0)} ч',
                    _sportDetails(note),
                  ];
                })
                .toList(growable: false),
            onRowTap: (index) => widget.onOpen(trainings[index].note),
          ),
          const SizedBox(height: 12),
          _BarChartCard(
            title: 'Длительность и нагрузка',
            labels: data.buckets.map((item) => item.label).toList(),
            series: [
              _Series(
                'Длительность, мин',
                durationValues,
                const Color(0xff4dabf7),
              ),
              _Series('Нагрузка', loadValues, const Color(0xffff6b6b)),
            ],
          ),
          const SizedBox(height: 12),
          _PieChartCard(
            title: 'Распределение времени по видам спорта',
            values: {
              for (final entry in bySport.entries)
                entry.key: _sum(
                  entry.value.map(
                    (item) => _number(
                      _map(item.note.frontmatter['metrics'])['duration'],
                    ),
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }

  int _compareTrainings(TrainingReportItem a, TrainingReportItem b) {
    final left = _sortValue(a, _sortColumnIndex);
    final right = _sortValue(b, _sortColumnIndex);
    final result = switch ((left, right)) {
      (final num l, final num r) => l.compareTo(r),
      (final DateTime l, final DateTime r) => l.compareTo(r),
      _ => left.toString().toLowerCase().compareTo(
        right.toString().toLowerCase(),
      ),
    };
    return _sortAscending ? result : -result;
  }

  Object _sortValue(TrainingReportItem item, int column) {
    final note = item.note;
    final metrics = _map(note.frontmatter['metrics']);
    final assessment = _map(note.frontmatter['assessment']);
    return switch (column) {
      0 => item.dateInfo.date,
      1 => note.title,
      2 => _sportName(note),
      3 => _number(metrics['duration']) ?? -1,
      4 => _number(assessment['load']) ?? -1,
      5 => _number(metrics['avg_hr']) ?? -1,
      6 => _number(metrics['calories']) ?? -1,
      7 => _number(metrics['aerobic_te']) ?? -1,
      8 => _number(metrics['anaerobic_te']) ?? -1,
      9 => _number(assessment['trimp']) ?? -1,
      10 => _number(assessment['recovery_hours']) ?? -1,
      _ => _sportDetails(note),
    };
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({required this.data, required this.onOpen});
  final PeriodReportData data;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.tasks.isEmpty) {
      return const _Section(
        title: 'Задачи',
        child: _Empty('За период задач не найдено.'),
      );
    }
    final projects = <String, (double, double)>{};
    for (final task in data.tasks) {
      for (final project
          in task.projects.isEmpty ? const ['Без проекта'] : task.projects) {
        final current = projects[project] ?? (0, 0);
        projects[project] = (current.$1 + 1, current.$2 + task.hours);
      }
    }
    final names = projects.keys.toList()
      ..sort(
        (a, b) => projects[b]!.$2.compareTo(projects[a]!.$2) != 0
            ? projects[b]!.$2.compareTo(projects[a]!.$2)
            : projects[b]!.$1.compareTo(projects[a]!.$1),
      );
    return _Section(
      title: 'Задачи',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportTable(
            columns: const [
              'Статус',
              'Дата',
              'Задача',
              'Проект',
              'Часы',
              'Тип',
            ],
            rows: data.tasks
                .map(
                  (task) => [
                    task.completed ? '✅' : '⬜',
                    _date(task.dateInfo.date),
                    task.name,
                    task.projects.isEmpty ? '—' : task.projects.join(', '),
                    task.hours == 0 ? '—' : _format(task.hours, 1),
                    task.kind,
                  ],
                )
                .toList(growable: false),
            onRowTap: (index) => onOpen(data.tasks[index].note),
          ),
          const SizedBox(height: 12),
          _ResponsiveCharts(
            first: _PieChartCard(
              title: 'Текущий статус задач',
              values: {
                'Выполнено': data.completedTasks.toDouble(),
                'Открыто': (data.tasks.length - data.completedTasks).toDouble(),
              },
            ),
            second: _BarChartCard(
              title: 'Задачи и часы по проектам',
              labels: names,
              series: [
                _Series(
                  'Задачи',
                  names.map<double?>((name) => projects[name]!.$1).toList(),
                  const Color(0xffffd43b),
                ),
                _Series(
                  'Часы',
                  names.map<double?>((name) => projects[name]!.$2).toList(),
                  const Color(0xff845ef7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Статус чекбоксов показан на момент открытия отчёта: '
            'в исторических заметках дата завершения не хранится.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.data, required this.onOpen});
  final PeriodReportData data;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    if (data.notes.isEmpty) {
      return const _Section(
        title: 'Новые заметки',
        child: _Empty('За период новых содержательных заметок не найдено.'),
      );
    }
    final byArea = _groupBy(data.notes, (item) => item.area);
    return _Section(
      title: 'Новые заметки',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportTable(
            columns: const ['Дата', 'Заметка', 'Раздел', 'Источник даты'],
            rows: data.notes
                .map(
                  (item) => [
                    _date(item.dateInfo.date),
                    item.note.title,
                    item.area,
                    '${item.dateInfo.source}${item.dateInfo.fallback ? ' ⚠️' : ''}',
                  ],
                )
                .toList(growable: false),
            onRowTap: (index) => onOpen(data.notes[index].note),
          ),
          const SizedBox(height: 12),
          _ResponsiveCharts(
            first: _BarChartCard(
              title: 'Новые заметки по времени',
              labels: data.buckets.map((item) => item.label).toList(),
              series: [
                _Series(
                  'Новые заметки',
                  data.buckets
                      .map<double?>(
                        (bucket) => data.notes
                            .where(
                              (item) => bucket.contains(item.dateInfo.date),
                            )
                            .length
                            .toDouble(),
                      )
                      .toList(),
                  const Color(0xff4dabf7),
                ),
              ],
            ),
            second: _PieChartCard(
              title: 'Новые заметки по разделам',
              values: {
                for (final entry in byArea.entries)
                  entry.key: entry.value.length.toDouble(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DataQuality extends StatelessWidget {
  const _DataQuality({required this.data});
  final PeriodReportData data;

  @override
  Widget build(BuildContext context) {
    final messages = [
      if (data.missingSteps > 0) 'Нет шагов: ${data.missingSteps} дн.',
      if (data.missingSleep > 0) 'Нет сна: ${data.missingSleep} дн.',
      if (data.missingCalories > 0)
        'Нет сожжённых калорий: ${data.missingCalories} дн.',
      if (data.fallbackNotes > 0)
        'Резервная дата date/added/file.ctime: ${data.fallbackNotes} заметок.',
    ];
    return _Section(
      title: 'Качество данных',
      child: Card(
        margin: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('⚠️ ${messages.join(' · ')}'),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
  });
  final List<String> columns;
  final List<List<String>> rows;
  final ValueChanged<int>? onRowTap;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending)? onSort;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        sortColumnIndex: sortColumnIndex,
        sortAscending: sortAscending,
        showCheckboxColumn: false,
        columns: columns.indexed
            .map(
              (entry) => DataColumn(
                label: Text(entry.$2),
                onSort: onSort == null
                    ? null
                    : (_, ascending) => onSort!(entry.$1, ascending),
              ),
            )
            .toList(growable: false),
        rows: [
          for (var index = 0; index < rows.length; index++)
            DataRow(
              cells: rows[index]
                  .map(
                    (value) => DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          value,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onTap: onRowTap == null ? null : () => onRowTap!(index),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    ),
  );
}

class _ResponsiveCharts extends StatelessWidget {
  const _ResponsiveCharts({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 760
        ? Column(children: [first, const SizedBox(height: 12), second])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          ),
  );
}

class _Series {
  const _Series(this.label, this.values, this.color);
  final String label;
  final List<double?> values;
  final Color color;
}

class _LineChartCard extends StatelessWidget {
  const _LineChartCard({
    required this.title,
    required this.labels,
    required this.series,
  });
  final String title;
  final List<String> labels;
  final List<_Series> series;

  @override
  Widget build(BuildContext context) => _ChartFrame(
    title: title,
    legend: series,
    child: LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(0, labels.length - 1).toDouble(),
        minY: 0,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true),
        titlesData: _titles(labels),
        lineBarsData: series
            .map(
              (item) => LineChartBarData(
                spots: [
                  for (var index = 0; index < item.values.length; index++)
                    if (item.values[index] != null)
                      FlSpot(index.toDouble(), item.values[index]!),
                ],
                color: item.color,
                barWidth: 3,
                isCurved: true,
                curveSmoothness: .25,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: item.color.withValues(alpha: .12),
                ),
              ),
            )
            .toList(growable: false),
      ),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    ),
  );
}

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({
    required this.title,
    required this.labels,
    required this.series,
    this.maxY,
  });
  final String title;
  final List<String> labels;
  final List<_Series> series;
  final double? maxY;

  @override
  Widget build(BuildContext context) => _ChartFrame(
    title: title,
    legend: series,
    child: BarChart(
      BarChartData(
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true),
        titlesData: _titles(labels),
        barGroups: [
          for (var index = 0; index < labels.length; index++)
            BarChartGroupData(
              x: index,
              barsSpace: 3,
              barRods: [
                for (final item in series)
                  BarChartRodData(
                    toY: item.values.length > index
                        ? item.values[index] ?? 0
                        : 0,
                    color: item.color,
                    width: math
                        .max(4, math.min(16, 28 / math.max(1, series.length)))
                        .toDouble(),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    ),
  );
}

class _PieChartCard extends StatelessWidget {
  const _PieChartCard({required this.title, required this.values});
  final String title;
  final Map<String, double> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((item) => item.value > 0).toList();
    final total = entries.fold<double>(0, (sum, item) => sum + item.value);
    final series = [
      for (var index = 0; index < entries.length; index++)
        _Series(
          entries[index].key,
          const [],
          _palette[index % _palette.length],
        ),
    ];
    return _ChartFrame(
      title: title,
      legend: series,
      child: entries.isEmpty
          ? const Center(child: Text('Нет данных'))
          : PieChart(
              PieChartData(
                centerSpaceRadius: 42,
                sectionsSpace: 2,
                sections: [
                  for (var index = 0; index < entries.length; index++)
                    PieChartSectionData(
                      value: entries[index].value,
                      color: _palette[index % _palette.length],
                      radius: 48,
                      title: '${(entries[index].value / total * 100).round()}%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            ),
    );
  }
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({
    required this.title,
    required this.legend,
    required this.child,
  });
  final String title;
  final List<_Series> legend;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: legend
                  .map(
                    (item) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: item.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(height: 230, child: child),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(20), child: Text(message)),
  );
}

class _AnimatedReportSection extends ConsumerWidget {
  const _AnimatedReportSection({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motionDuration(
          context,
          ref.watch(settingsControllerProvider).motionPreference,
          expressive: 380 + index * 80,
          balanced: 240 + index * 35,
        ),
        curve: motionCurve(
          ref.read(settingsControllerProvider).motionPreference,
        ),
        builder: (context, value, child) => Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value.clamp(0, 1))),
            child: child,
          ),
        ),
        child: child,
      );
}

FlTitlesData _titles(List<String> labels) {
  final interval = math.max(1, (labels.length / 6).ceil());
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: true, reservedSize: 42),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 34,
        interval: interval.toDouble(),
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 || index >= labels.length || index % interval != 0) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Transform.rotate(
              angle: labels.length > 10 ? -.45 : 0,
              child: Text(labels[index], style: const TextStyle(fontSize: 9)),
            ),
          );
        },
      ),
    ),
  );
}

Map<K, List<T>> _groupBy<T, K>(Iterable<T> items, K Function(T) keyOf) {
  final result = <K, List<T>>{};
  for (final item in items) {
    result.putIfAbsent(keyOf(item), () => []).add(item);
  }
  return result;
}

double? _average(Iterable<double?> values) {
  final valid = values.whereType<double>().toList();
  return valid.isEmpty
      ? null
      : valid.fold<double>(0, (sum, value) => sum + value) / valid.length;
}

double _sum(Iterable<Object?> values) =>
    values.fold<double>(0, (sum, value) => sum + (_number(value) ?? 0));

double? _nullableSum(Iterable<double?> values, {bool zeroIsNull = false}) {
  final valid = values.whereType<double>().toList();
  if (valid.isEmpty) return null;
  final result = valid.fold<double>(0, (sum, value) => sum + value);
  return zeroIsNull && result == 0 ? null : result;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

double? _number(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(value.toString());
  return match == null
      ? null
      : double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

String _format(double? value, [int digits = 1]) =>
    value == null ? '—' : value.toStringAsFixed(digits);

String _date(DateTime value) => DateFormat('dd LLL yyyy', 'ru').format(value);

String _sportName(ParsedNote note) {
  final sport = note.frontmatter['sport'];
  if (sport is List && sport.isNotEmpty) return sport.first.toString();
  const names = {
    'rowing': 'Гребной тренажёр',
    'bike': 'Велосипед',
    'rope': 'Скакалка',
    'tennis': 'Настольный теннис',
  };
  final key = note.frontmatter['sport_key']?.toString();
  return names[key] ?? key ?? 'Тренировка';
}

String _sportDetails(ParsedNote note) {
  final metrics = _map(note.frontmatter['metrics']);
  final key = note.frontmatter['sport_key']?.toString();
  final value = switch (key) {
    'bike' => (_number(metrics['distance']), 'км'),
    'rowing' => (_number(metrics['strokes']), 'гребков'),
    'rope' => (_number(metrics['jumps']), 'прыжков'),
    'tennis' => (_number(metrics['games']), 'партий'),
    _ => (null, ''),
  };
  return value.$1 == null
      ? '—'
      : '${_format(value.$1, key == 'bike' ? 1 : 0)} ${value.$2}';
}

const _palette = [
  Color(0xff4dabf7),
  Color(0xff845ef7),
  Color(0xff63e6be),
  Color(0xffffd43b),
  Color(0xffff6b6b),
  Color(0xffffa94d),
  Color(0xff22b8cf),
  Color(0xfff06595),
];
