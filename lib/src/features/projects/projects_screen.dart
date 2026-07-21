import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/vault/project_note_definition.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/page_scaffold.dart';
import '../vault/note_screen.dart';
import 'project_forms.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  var _filter = 'active';
  var _sort = 'status';
  var _view = 'projects';

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final all = [...controller.index.projects];
    final projects = all
        .where(
          (project) => switch (_filter) {
            'active' => !_archived(project),
            'archived' => _archived(project),
            _ => true,
          },
        )
        .toList();
    projects.sort(
      (a, b) => switch (_sort) {
        'name' => _name(a).compareTo(_name(b)),
        'recent' => b.document.modifiedAt.compareTo(a.document.modifiedAt),
        _ =>
          _archived(a) == _archived(b)
              ? _name(a).compareTo(_name(b))
              : (_archived(a) ? 1 : -1),
      },
    );
    final projectNames = all.map(_name).toList(growable: false);
    final tasks = [...controller.index.tasks]
      ..sort((a, b) {
        final aDone =
            a.frontmatter['complete'] == true ||
            a.frontmatter['status'] == 'done';
        final bDone =
            b.frontmatter['complete'] == true ||
            b.frontmatter['status'] == 'done';
        return aDone == bDone
            ? b.document.modifiedAt.compareTo(a.document.modifiedAt)
            : (aDone ? 1 : -1);
      });
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return PageScaffold(
      title: 'Проекты',
      subtitle:
          '${all.where((item) => !_archived(item)).length} активных · ${all.where(_archived).length} в архиве',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Добавить',
          onSelected: (value) => _create(value, projectNames),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'project',
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('Проект'),
              ),
            ),
            const PopupMenuItem(
              value: 'task',
              child: ListTile(
                leading: Icon(Icons.add_task),
                title: Text('Задача'),
              ),
            ),
            const PopupMenuDivider(),
            for (final definition in projectNoteDefinitions)
              PopupMenuItem(
                value: 'note:${definition.key}',
                child: ListTile(
                  leading: Icon(definition.icon),
                  title: Text(definition.label),
                ),
              ),
          ],
        ),
      ],
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 20),
              child: _ProjectFilters(
                view: _view,
                filter: _filter,
                sort: _sort,
                onView: (value) => setState(() => _view = value),
                onFilter: (value) => setState(() => _filter = value),
                onSort: (value) => setState(() => _sort = value),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_view == 'tasks')
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 8 : 16,
                0,
                narrow ? 8 : 16,
                28,
              ),
              sliver: SliverList.builder(
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final complete =
                      task.frontmatter['complete'] == true ||
                      task.frontmatter['status'] == 'done';
                  return Card(
                    child: ListTile(
                      leading: Checkbox(
                        value: complete,
                        onChanged: (value) =>
                            controller.setTaskComplete(task, value ?? false),
                      ),
                      title: Text(
                        task.title,
                        style: complete
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        '${task.frontmatter['project'] ?? 'Без проекта'} · ${task.frontmatter['priority'] ?? 'medium'}${task.frontmatter['due'] == null ? '' : ' · до ${task.frontmatter['due']}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NoteScreen(note: task),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else if (_view == 'materials')
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 8 : 16,
                0,
                narrow ? 8 : 16,
                28,
              ),
              sliver: SliverList.builder(
                itemCount: controller.index.projectNotes.length,
                itemBuilder: (context, index) {
                  final notes = [...controller.index.projectNotes]
                    ..sort(
                      (a, b) => b.document.modifiedAt.compareTo(
                        a.document.modifiedAt,
                      ),
                    );
                  final note = notes[index];
                  final definition = projectNoteDefinition(
                    note.frontmatter['note_type']?.toString() ?? 'general',
                  );
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: definition.color.withValues(
                          alpha: .16,
                        ),
                        child: Icon(definition.icon, color: definition.color),
                      ),
                      title: Text(note.title),
                      subtitle: Text(
                        '${note.frontmatter['project'] ?? 'Без проекта'} · ${definition.label}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NoteScreen(note: note),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else if (projects.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Проектов с таким статусом нет')),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 8 : 16,
                0,
                narrow ? 8 : 16,
                28,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: narrow ? 500 : 420,
                  mainAxisExtent: 205,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: projects.length,
                itemBuilder: (context, index) => _ProjectCard(
                  project: projects[index],
                  tasks: controller.index.tasks
                      .where(
                        (task) =>
                            task.frontmatter['project']?.toString() ==
                            _name(projects[index]),
                      )
                      .toList(),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NoteScreen(note: projects[index]),
                    ),
                  ),
                  onTask: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateTaskScreen(
                        projects: projectNames,
                        initialProject: _name(projects[index]),
                      ),
                    ),
                  ),
                  onNote: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateProjectNoteScreen(
                        projects: projectNames,
                        initialProject: _name(projects[index]),
                      ),
                    ),
                  ),
                  onArchive: () => controller.setProjectArchived(
                    projects[index],
                    !_archived(projects[index]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _archived(ParsedNote note) =>
      note.frontmatter['archived'] == true ||
      note.frontmatter['status'] == 'archived' ||
      note.document.path.startsWith('Archive/');
  String _name(ParsedNote note) =>
      note.frontmatter['project']?.toString() ?? note.title;

  void _create(String value, List<String> projects) {
    final screen = value == 'project'
        ? const CreateProjectScreen()
        : value == 'task'
        ? CreateTaskScreen(projects: projects)
        : CreateProjectNoteScreen(
            projects: projects,
            initialType: value.replaceFirst('note:', ''),
          );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _ProjectFilters extends StatelessWidget {
  const _ProjectFilters({
    required this.view,
    required this.filter,
    required this.sort,
    required this.onView,
    required this.onFilter,
    required this.onSort,
  });
  final String view;
  final String filter;
  final String sort;
  final ValueChanged<String> onView;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onSort;

  static const _segments = [
    ButtonSegment(
      value: 'projects',
      label: Text('Проекты'),
      icon: Icon(Icons.work_outline),
    ),
    ButtonSegment(
      value: 'tasks',
      label: Text('Задачи'),
      icon: Icon(Icons.task_alt),
    ),
    ButtonSegment(
      value: 'materials',
      label: Text('Материалы'),
      icon: Icon(Icons.description_outlined),
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewSelector = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: _segments,
          selected: {view},
          onSelectionChanged: (value) => onView(value.first),
        ),
      );
      if (constraints.maxWidth < 500) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            viewSelector,
            if (view == 'projects') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ProjectStatusStrip(
                      value: filter,
                      onSelected: onFilter,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ProjectSortButton(value: sort, onSelected: onSort),
                ],
              ),
            ],
          ],
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            viewSelector,
            if (view == 'projects') ...[
              const SizedBox(width: 12),
              _ProjectStatusStrip(value: filter, onSelected: onFilter),
              const SizedBox(width: 8),
              _ProjectSortButton(
                value: sort,
                onSelected: onSort,
                showLabel: true,
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _ProjectStatusStrip extends StatelessWidget {
  const _ProjectStatusStrip({required this.value, required this.onSelected});
  final String value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final item in const [
          ('active', 'Активные'),
          ('archived', 'Архив'),
          ('all', 'Все'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(item.$2),
              selected: value == item.$1,
              onSelected: (_) => onSelected(item.$1),
            ),
          ),
      ],
    ),
  );
}

class _ProjectSortButton extends StatelessWidget {
  const _ProjectSortButton({
    required this.value,
    required this.onSelected,
    this.showLabel = false,
  });
  final String value;
  final ValueChanged<String> onSelected;
  final bool showLabel;

  String get label => switch (value) {
    'name' => 'По имени',
    'recent' => 'Недавние',
    _ => 'По статусу',
  };

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Сортировка проектов',
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'status', child: Text('По статусу')),
      PopupMenuItem(value: 'name', child: Text('По имени')),
      PopupMenuItem(value: 'recent', child: Text('Недавние')),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 20),
          if (showLabel) ...[const SizedBox(width: 7), Text(label)],
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.tasks,
    required this.onOpen,
    required this.onTask,
    required this.onNote,
    required this.onArchive,
  });
  final ParsedNote project;
  final List<ParsedNote> tasks;
  final VoidCallback onOpen;
  final VoidCallback onTask;
  final VoidCallback onNote;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final archived =
        project.frontmatter['archived'] == true ||
        project.frontmatter['status'] == 'archived' ||
        project.document.path.startsWith('Archive/');
    final done = tasks
        .where(
          (task) =>
              task.frontmatter['complete'] == true ||
              task.frontmatter['status'] == 'done',
        )
        .length;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Icon(
                      archived
                          ? Icons.inventory_2_outlined
                          : Icons.work_outline,
                    ),
                  ),
                  const Spacer(),
                  Chip(
                    label: Text(
                      archived
                          ? 'Архив'
                          : project.frontmatter['status']?.toString() ??
                                'Активный',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                project.frontmatter['project']?.toString() ?? project.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text('Задачи: ${tasks.length} · готово: $done'),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: tasks.isEmpty ? 0 : done / tasks.length,
              ),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Добавить задачу',
                    onPressed: onTask,
                    icon: const Icon(Icons.add_task),
                  ),
                  IconButton(
                    tooltip: 'Добавить материал',
                    onPressed: onNote,
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                  const Spacer(),
                  if (!archived)
                    IconButton(
                      tooltip: 'Архивировать',
                      onPressed: onArchive,
                      icon: const Icon(Icons.archive_outlined),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
