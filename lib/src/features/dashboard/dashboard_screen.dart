import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/vault/vault_models.dart';
import '../daily/create_daily_note_screen.dart';
import '../daily/daily_note_calendar.dart';
import '../daily/training_form_screen.dart';
import '../projects/project_forms.dart';
import '../vault/note_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final index = controller.index;
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final activeProjects = index.projects
        .where(
          (note) => [
            'active',
            'on-hold',
            'paused',
          ].contains(note.frontmatter['status']?.toString() ?? 'active'),
        )
        .toList(growable: false);
    final tasks =
        index.tasks
            .where(
              (note) =>
                  note.frontmatter['complete'] != true &&
                  note.frontmatter['status'] != 'done',
            )
            .toList()
          ..sort(_compareTasks);
    final focusTasks = <_FocusTask>[
      for (final task in tasks)
        _FocusTask(
          title: task.title,
          project: task.frontmatter['project']?.toString() ?? 'Без проекта',
          note: task,
          due: DateTime.tryParse(task.frontmatter['due']?.toString() ?? ''),
          priority: task.frontmatter['priority']?.toString() ?? '',
        ),
      for (final note in index.projectNotes)
        for (final task in note.tasks.where((item) => !item.completed))
          _FocusTask(
            title: task.text,
            project: note.frontmatter['project']?.toString() ?? 'Без проекта',
            note: note,
          ),
    ]..sort(_compareFocusTasks);
    final recentTrainings = index.trainings
        .where((note) => note.date != null && !note.date!.isBefore(start))
        .toList(growable: false);
    final recentDailies = index.dailies
        .where((note) => note.date != null && !note.date!.isBefore(start))
        .length;
    final inbox = index.documents
        .where((file) => file.path.startsWith('Входящие/'))
        .toList(growable: false);
    final reports =
        index.notes
            .where((note) => note.type == VaultEntityType.periodReport)
            .toList()
          ..sort(
            (a, b) => b.document.modifiedAt.compareTo(a.document.modifiedAt),
          );
    final recentNotes =
        index.notes
            .where(
              (note) =>
                  !{
                    VaultEntityType.project,
                    VaultEntityType.periodReport,
                  }.contains(note.type) &&
                  !note.document.path.startsWith('Templates/'),
            )
            .toList()
          ..sort(
            (a, b) => b.document.modifiedAt.compareTo(a.document.modifiedAt),
          );
    final trainingMinutes = recentTrainings.fold<double>(
      0,
      (sum, note) =>
          sum + (_number(_map(note.frontmatter['metrics'])['duration']) ?? 0),
    );
    final trainingLoad = recentTrainings.fold<double>(
      0,
      (sum, note) =>
          sum + (_number(_map(note.frontmatter['assessment'])['load']) ?? 0),
    );
    final projectNames = index.projects
        .map(_projectName)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;
        final padding = narrow ? 10.0 : 20.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(padding, 12, padding, 30),
          children: [
            _Reveal(
              index: 0,
              child: _Hero(
                date: DateFormat('EEEE, d MMMM', 'ru').format(now),
                greeting: _greeting(now.hour),
                onDaily: () => _openDaily(context, ref),
                onProject: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateProjectScreen(),
                  ),
                ),
                onTask: projectNames.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateTaskScreen(projects: projectNames),
                        ),
                      ),
                onTraining: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TrainingFormScreen(date: now),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Reveal(
              index: 1,
              child: _KpiGrid(
                items: [
                  _Kpi(
                    Icons.work_outline,
                    'Активные проекты',
                    activeProjects.length,
                    '${index.projects.length} всего',
                  ),
                  _Kpi(
                    Icons.task_alt,
                    'Открытые задачи',
                    focusTasks.length,
                    'по всему хранилищу',
                  ),
                  _Kpi(
                    Icons.fitness_center,
                    'Тренировки',
                    recentTrainings.length,
                    'за последние 7 дней',
                  ),
                  _Kpi(
                    Icons.inbox_outlined,
                    'Входящие',
                    inbox.length,
                    inbox.isEmpty ? 'всё разобрано' : 'ждут обработки',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ResponsivePair(
              left: _Reveal(
                index: 2,
                child: _Panel(
                  eyebrow: 'Фокус',
                  title: 'Ближайшие задачи',
                  child: focusTasks.isEmpty
                      ? const _Empty('Открытых задач нет.')
                      : Column(
                          children: focusTasks
                              .take(8)
                              .map(
                                (task) => _DashboardRow(
                                  title: task.title,
                                  subtitle: task.project,
                                  meta: task.due == null
                                      ? 'Без срока'
                                      : DateFormat(
                                          'd MMM',
                                          'ru',
                                        ).format(task.due!),
                                  overdue: task.overdue,
                                  onTap: () => _openNote(context, task.note),
                                ),
                              )
                              .toList(growable: false),
                        ),
                ),
              ),
              right: _Reveal(
                index: 3,
                child: _Panel(
                  eyebrow: 'Быстрый доступ',
                  title: 'Рабочие разделы',
                  child: Column(
                    children: [
                      _AccessRow(
                        icon: Icons.work_outline,
                        title: 'Центр проектов',
                        subtitle: '${activeProjects.length} в работе',
                        onTap: () => _openPath(
                          context,
                          index.notes,
                          'Projects/_Projects.md',
                        ),
                      ),
                      _AccessRow(
                        icon: Icons.insights_outlined,
                        title: 'Отчёты',
                        subtitle: reports.isEmpty
                            ? 'Отчётов пока нет'
                            : reports.first.title,
                        onTap: reports.isEmpty
                            ? null
                            : () => _openNote(context, reports.first),
                      ),
                      _AccessRow(
                        icon: Icons.favorite_outline,
                        title: 'Здоровье',
                        subtitle: '${recentTrainings.length} тренировок',
                        onTap: recentTrainings.isEmpty
                            ? null
                            : () => _openNote(context, recentTrainings.last),
                      ),
                      _AccessRow(
                        icon: Icons.inbox_outlined,
                        title: 'Входящие',
                        subtitle: inbox.isEmpty
                            ? 'Папка пуста'
                            : 'Неразобрано: ${inbox.length}',
                        onTap: () => _openFirstInbox(context, index.notes),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Reveal(
              index: 4,
              child: _Panel(
                eyebrow: 'Работа',
                title: 'Проекты в движении',
                child: activeProjects.isEmpty
                    ? const _Empty('Активных проектов пока нет.')
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth < 480
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 8) / 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: activeProjects
                                .take(6)
                                .map(
                                  (project) => SizedBox(
                                    width: width,
                                    child: _ProjectTile(
                                      project: project,
                                      tasks: index.tasks,
                                      notes: index.projectNotes,
                                      onTap: () => _openNote(context, project),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _Reveal(
              index: 5,
              child: _Panel(
                eyebrow: 'Самочувствие',
                title: 'Последние 7 дней',
                child: Column(
                  children: [
                    _HealthSummary(
                      values: [
                        ('${recentTrainings.length}', 'тренировок'),
                        (trainingMinutes.toStringAsFixed(0), 'минут'),
                        (trainingLoad.toStringAsFixed(0), 'нагрузка'),
                        ('$recentDailies', 'ежедневных заметок'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _WeekBars(trainings: recentTrainings, start: start),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ResponsivePair(
              left: _Reveal(
                index: 6,
                child: _Panel(
                  eyebrow: 'Аналитика',
                  title: 'Последние отчёты',
                  child: reports.isEmpty
                      ? const _Empty('Отчётов пока нет.')
                      : Column(
                          children: reports
                              .take(5)
                              .map(
                                (note) => _DashboardRow(
                                  title: note.title,
                                  subtitle: _reportType(note),
                                  meta: DateFormat(
                                    'dd.MM',
                                  ).format(note.document.modifiedAt.toLocal()),
                                  onTap: () => _openNote(context, note),
                                ),
                              )
                              .toList(growable: false),
                        ),
                ),
              ),
              right: _Reveal(
                index: 7,
                child: _Panel(
                  eyebrow: 'Контекст',
                  title: 'Недавние заметки',
                  child: Column(
                    children: recentNotes
                        .take(5)
                        .map(
                          (note) => _DashboardRow(
                            title: note.title,
                            subtitle: note.document.path,
                            meta: _relative(note.document.modifiedAt),
                            onTap: () => _openNote(context, note),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(controller.error!),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static int _compareTasks(ParsedNote a, ParsedNote b) {
    final aDue = DateTime.tryParse(a.frontmatter['due']?.toString() ?? '');
    final bDue = DateTime.tryParse(b.frontmatter['due']?.toString() ?? '');
    if (aDue == null && bDue == null) {
      return b.document.modifiedAt.compareTo(a.document.modifiedAt);
    }
    if (aDue == null) return 1;
    if (bDue == null) return -1;
    return aDue.compareTo(bDue);
  }

  static int _compareFocusTasks(_FocusTask a, _FocusTask b) {
    if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
    if (a.due == null && b.due != null) return 1;
    if (a.due != null && b.due == null) return -1;
    if (a.due != null && b.due != null) {
      final result = a.due!.compareTo(b.due!);
      if (result != 0) return result;
    }
    const priority = {'high': 0, 'medium': 1, 'low': 2};
    return (priority[a.priority] ?? 3).compareTo(priority[b.priority] ?? 3);
  }

  static String _projectName(ParsedNote note) =>
      note.frontmatter['project']?.toString() ?? note.title;

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : const {};

  static double? _number(Object? value) =>
      double.tryParse(value?.toString().replaceAll(',', '.') ?? '');

  static String _greeting(int hour) => hour < 6
      ? 'Спокойной ночи'
      : hour < 12
      ? 'Доброе утро'
      : hour < 18
      ? 'Добрый день'
      : 'Добрый вечер';

  static String _reportType(ParsedNote note) =>
      switch (note.frontmatter['report_type']?.toString()) {
        'weekly' => 'Неделя',
        'monthly' => 'Месяц',
        'yearly' => 'Год',
        _ => 'Отчёт',
      };

  static String _relative(DateTime date) {
    final days = DateTime.now().difference(date.toLocal()).inDays;
    if (days <= 0) return 'сегодня';
    if (days == 1) return 'вчера';
    return '$days дн. назад';
  }

  static void _openNote(BuildContext context, ParsedNote note) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteScreen(note: note)));

  static void _openPath(
    BuildContext context,
    Iterable<ParsedNote> notes,
    String path,
  ) {
    for (final note in notes) {
      if (note.document.path == path) {
        _openNote(context, note);
        return;
      }
    }
  }

  static void _openFirstInbox(
    BuildContext context,
    Iterable<ParsedNote> notes,
  ) {
    for (final note in notes) {
      if (note.document.path.startsWith('Входящие/')) {
        _openNote(context, note);
        return;
      }
    }
  }

  static Future<void> _openDaily(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(appControllerProvider);
    final selection = await showDailyNoteCalendar(
      context,
      notes: controller.index.dailies,
    );
    if (selection == null || !context.mounted) return;
    final destination = selection.note == null
        ? CreateDailyNoteScreen(date: selection.date)
        : NoteScreen(note: selection.note!);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => destination));
  }
}

class _FocusTask {
  const _FocusTask({
    required this.title,
    required this.project,
    required this.note,
    this.due,
    this.priority = '',
  });
  final String title;
  final String project;
  final ParsedNote note;
  final DateTime? due;
  final String priority;

  bool get overdue {
    final now = DateTime.now();
    return due != null && due!.isBefore(DateTime(now.year, now.month, now.day));
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.date,
    required this.greeting,
    required this.onDaily,
    required this.onProject,
    required this.onTask,
    required this.onTraining,
  });
  final String date;
  final String greeting;
  final VoidCallback onDaily;
  final VoidCallback onProject;
  final VoidCallback? onTask;
  final VoidCallback onTraining;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.primaryContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                date.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Короткий обзор хранилища и быстрый переход к текущей работе.',
              ),
            ],
          );
          final actions = Wrap(
            alignment: wide ? WrapAlignment.end : WrapAlignment.start,
            spacing: 7,
            runSpacing: 7,
            children: [
              FilledButton.icon(
                onPressed: onDaily,
                icon: const Icon(Icons.today),
                label: const Text('Сегодня'),
              ),
              FilledButton.tonalIcon(
                onPressed: onProject,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Проект'),
              ),
              FilledButton.tonalIcon(
                onPressed: onTask,
                icon: const Icon(Icons.add_task),
                label: const Text('Задача'),
              ),
              FilledButton.tonalIcon(
                onPressed: onTraining,
                icon: const Icon(Icons.fitness_center),
                label: const Text('Тренировка'),
              ),
            ],
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 18), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 20),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.icon, this.label, this.value, this.hint);
  final IconData icon;
  final String label;
  final int value;
  final String hint;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 380
          ? constraints.maxWidth
          : constraints.maxWidth < 760
          ? (constraints.maxWidth - 8) / 2
          : (constraints.maxWidth - 24) / 4;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map(
              (item) => SizedBox(
                width: width,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(child: Icon(item.icon)),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.value}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(item.label),
                              Text(
                                item.hint,
                                style: Theme.of(context).textTheme.labelSmall,
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
  );
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 720
        ? Column(children: [left, const SizedBox(height: 12), right])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right),
            ],
          ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.eyebrow,
    required this.title,
    required this.child,
  });
  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 3),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _DashboardRow extends StatelessWidget {
  const _DashboardRow({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onTap,
    this.overdue = false,
  });
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onTap;
  final bool overdue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                meta,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccessRow extends StatelessWidget {
  const _AccessRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.arrow_forward),
    enabled: onTap != null,
    onTap: onTap,
  );
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.tasks,
    required this.notes,
    required this.onTap,
  });
  final ParsedNote project;
  final List<ParsedNote> tasks;
  final List<ParsedNote> notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = DashboardScreen._projectName(project);
    final taskPages = tasks
        .where(
          (task) =>
              task.frontmatter['project']?.toString() == name &&
              task.frontmatter['complete'] != true &&
              task.frontmatter['status'] != 'done',
        )
        .length;
    final relatedNotes = notes
        .where((note) => note.frontmatter['project']?.toString() == name)
        .toList(growable: false);
    final taskCount =
        taskPages +
        relatedNotes.fold<int>(
          0,
          (sum, note) =>
              sum + note.tasks.where((task) => !task.completed).length,
        );
    final noteCount = relatedNotes.length;
    final color =
        _color(project.frontmatter['color']?.toString()) ??
        Theme.of(context).colorScheme.primary;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .3),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$taskCount задач · $noteCount материалов',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color? _color(String? value) {
    final raw = value?.replaceFirst('#', '');
    if (raw == null || raw.length != 6) return null;
    final parsed = int.tryParse(raw, radix: 16);
    return parsed == null ? null : Color(0xff000000 | parsed);
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.values});
  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 360
          ? (constraints.maxWidth - 8) / 2
          : (constraints.maxWidth - 24) / 4;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map(
              (item) => SizedBox(
                width: width,
                child: Column(
                  children: [
                    Text(
                      item.$1,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      item.$2,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.trainings, required this.start});
  final List<ParsedNote> trainings;
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final values = List<double>.generate(7, (index) {
      final day = start.add(Duration(days: index));
      return trainings
          .where(
            (note) =>
                note.date?.year == day.year &&
                note.date?.month == day.month &&
                note.date?.day == day.day,
          )
          .fold<double>(
            0,
            (sum, note) =>
                sum +
                (DashboardScreen._number(
                      DashboardScreen._map(
                        note.frontmatter['metrics'],
                      )['duration'],
                    ) ??
                    0),
          );
    });
    final max = values.fold<double>(
      1,
      (value, item) => item > value ? item : value,
    );
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < 7; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: values[index] / max),
                      duration: Duration(milliseconds: 420 + index * 45),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Container(
                        height: 75 * value,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat(
                        'EE',
                        'ru',
                      ).format(start.add(Duration(days: index))),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 300 + index * 55),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(message),
  );
}
