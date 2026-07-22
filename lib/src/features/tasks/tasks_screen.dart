import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/task_controller.dart';
import '../../core/tasks/task_models.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/page_scaffold.dart';
import '../projects/project_forms.dart';
import '../vault/note_screen.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  var _view = TaskView.inbox;
  var _mode = 'list';
  var _calendarDay = DateTime.now();
  String? _kanbanProject;

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultControllerProvider);
    final controller = ref.watch(taskControllerProvider);
    final projects = vault.index.projects
        .where((note) => note.frontmatter['archived'] != true)
        .map((note) => note.frontmatter['project']?.toString() ?? note.title)
        .toList(growable: false);
    _kanbanProject ??= projects.firstOrNull;
    return PageScaffold(
      title: 'Задачи',
      subtitle: '${controller.select(TaskView.all).length} открытых · ${controller.embedded.where((item) => !item.task.completed).length} чекбоксов',
      actions: [
        IconButton(
          tooltip: 'Новая задача',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateTaskScreen(projects: projects),
            ),
          ),
          icon: const Icon(Icons.add_task),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'list', label: Text('Список'), icon: Icon(Icons.list)),
                  ButtonSegment(value: 'calendar', label: Text('Календарь'), icon: Icon(Icons.calendar_month)),
                  ButtonSegment(value: 'kanban', label: Text('Kanban'), icon: Icon(Icons.view_kanban)),
                ],
                selected: {_mode},
                onSelectionChanged: (value) => setState(() => _mode = value.first),
              ),
            ),
          ),
          Expanded(
            child: switch (_mode) {
              'calendar' => _calendar(controller),
              'kanban' => _kanban(controller, projects),
              _ => _list(controller, projects),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(TaskController controller, List<String> projects) {
    final tasks = controller.select(_view);
    final embedded = controller.embedded;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in TaskView.values)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(_viewLabel(item)),
                    selected: _view == item,
                    onSelected: (_) => setState(() => _view = item),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 28),
            children: [
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('В этом представлении задач нет')),
                ),
              for (final task in tasks) _TaskTile(task: task, projects: projects),
              if (_view == TaskView.inbox && embedded.any((item) => !item.task.completed)) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 20, 8, 8),
                  child: Text('Чекбоксы в заметках', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final item in embedded.where((item) => !item.task.completed))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_box_outline_blank),
                      title: Text(item.task.text),
                      subtitle: Text(item.note.title),
                      trailing: TextButton(
                        onPressed: () => ref.read(taskControllerProvider).convertEmbedded(item),
                        child: const Text('В задачу'),
                      ),
                      onTap: () => _open(item.note),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _calendar(TaskController controller) {
    final tasks = controller.tasks.where((task) {
      final date = task.scheduled ?? task.due;
      return date != null && taskDay(date) == taskDay(_calendarDay);
    }).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final calendar = CalendarDatePicker(
          initialDate: _calendarDay,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          onDateChanged: (value) => setState(() => _calendarDay = value),
        );
        final list = ListView(
          padding: const EdgeInsets.all(10),
          children: [
            Text(DateFormat('d MMMM yyyy', 'ru').format(_calendarDay), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (tasks.isEmpty) const Card(child: ListTile(title: Text('Задач на эту дату нет'))),
            for (final task in tasks) _TaskTile(task: task, projects: const []),
          ],
        );
        return constraints.maxWidth >= 760
            ? Row(children: [Expanded(child: calendar), Expanded(child: list)])
            : Column(children: [calendar, Expanded(child: list)]);
      },
    );
  }

  Widget _kanban(TaskController controller, List<String> projects) {
    if (projects.isEmpty) return const Center(child: Text('Сначала создайте проект'));
    final selected = _kanbanProject ?? projects.first;
    final projectNote = ref
        .read(vaultControllerProvider)
        .index
        .projects
        .where(
          (note) =>
              (note.frontmatter['project']?.toString() ?? note.title) == selected,
        )
        .firstOrNull;
    final tasks = controller.tasks
        .where((task) => task.project == selected)
        .toList();
    final columns = _kanbanColumns(projectNote);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Проект'),
                  items: projects.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                  onChanged: (value) => setState(() => _kanbanProject = value),
                ),
              ),
              IconButton(
                tooltip: 'Настроить колонки',
                onPressed: projectNote == null
                    ? null
                    : () => _editKanban(controller, projectNote, columns),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            children: [
              for (final column in columns)
                DragTarget<TaskDefinition>(
                  onAcceptWithDetails: (details) => controller.setStatusId(details.data, column.id),
                  builder: (context, candidates, _) => Container(
                    width: 290,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: candidates.isEmpty
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListView(
                      children: [
                        Text(column.title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final task in tasks.where((item) => item.statusId == column.id))
                          LongPressDraggable<TaskDefinition>(
                            data: task,
                            feedback: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(width: 260, child: _KanbanCard(task: task)),
                            ),
                            childWhenDragging: Opacity(opacity: .35, child: _KanbanCard(task: task)),
                            child: _KanbanCard(task: task),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<({String id, String title})> _kanbanColumns(ParsedNote? project) {
    final raw = project?.frontmatter['kanban_columns'];
    if (raw is List) {
      final parsed = raw.whereType<Map>().map((item) {
        final map = Map<String, Object?>.from(item);
        return (
          id: map['id']?.toString() ?? '',
          title: map['title']?.toString() ?? '',
        );
      }).where((item) => item.id.isNotEmpty && item.title.isNotEmpty).toList();
      if (parsed.isNotEmpty) return parsed;
    }
    return const [
      (id: 'todo', title: 'Запланировано'),
      (id: 'in-progress', title: 'В работе'),
      (id: 'blocked', title: 'Заблокировано'),
      (id: 'done', title: 'Готово'),
    ];
  }

  Future<void> _editKanban(
    TaskController controller,
    ParsedNote project,
    List<({String id, String title})> current,
  ) async {
    final editors = current
        .map((item) => (id: item.id, text: TextEditingController(text: item.title)))
        .toList();
    final result = await showDialog<List<({String id, String title})>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Колонки Kanban'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final editor in editors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: editor.text,
                    decoration: InputDecoration(labelText: editor.id),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              editors
                  .map((item) => (id: item.id, title: item.text.text.trim()))
                  .where((item) => item.title.isNotEmpty)
                  .toList(),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    for (final editor in editors) {
      editor.text.dispose();
    }
    if (result != null) await controller.setKanbanColumns(project, result);
  }

  void _open(ParsedNote note) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => NoteScreen(note: note)),
  );
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.projects});
  final TaskDefinition task;
  final List<String> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(taskControllerProvider);
    final blocked = controller.isBlocked(task);
    final date = task.scheduled ?? task.due;
    return Card(
      child: ListTile(
        leading: Checkbox(
          value: task.completed,
          onChanged: (value) async {
            try {
              await controller.setComplete(task, value ?? false);
            } on StateError {
              if (!context.mounted) return;
              final force = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Есть незавершённые зависимости'),
                  content: const Text('Завершить задачу принудительно?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Завершить')),
                  ],
                ),
              );
              if (force == true) await controller.setComplete(task, true, force: true);
            }
          },
        ),
        title: Text(task.title, style: task.completed ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Text([
          task.project ?? 'Inbox',
          if (date != null) DateFormat('d MMM', 'ru').format(date),
          if (blocked) 'заблокирована',
          if (task.recurrence != null) 'повторяется',
        ].join(' · ')),
        trailing: projects.isEmpty
            ? const Icon(Icons.chevron_right)
            : PopupMenuButton<String>(
                tooltip: 'Назначить проект',
                onSelected: (value) => controller.assignProject(task, value),
                itemBuilder: (_) => [
                  for (final project in projects) PopupMenuItem(value: project, child: Text(project)),
                ],
              ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteScreen(note: task.note))),
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.task});
  final TaskDefinition task;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(task.due == null ? task.priority : '${task.priority} · ${DateFormat('d MMM', 'ru').format(task.due!)}'),
        ],
      ),
    ),
  );
}

String _viewLabel(TaskView view) => switch (view) {
  TaskView.inbox => 'Inbox',
  TaskView.today => 'Сегодня',
  TaskView.overdue => 'Просрочено',
  TaskView.week => 'На неделе',
  TaskView.all => 'Все',
  TaskView.completed => 'Завершённые',
};

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
