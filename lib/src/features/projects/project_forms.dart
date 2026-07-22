import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/vault/project_note_definition.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});
  @override
  ConsumerState<CreateProjectScreen> createState() =>
      _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  var _status = 'active';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Новый проект')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите название'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Статус'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Активный')),
              DropdownMenuItem(value: 'on-hold', child: Text('На паузе')),
              DropdownMenuItem(value: 'done', child: Text('Завершён')),
              DropdownMenuItem(
                value: 'archived',
                child: Text('Архивированный'),
              ),
            ],
            onChanged: (value) => _status = value ?? _status,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Описание',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Создать проект'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(projectServiceProvider)
        .createProject(
          title: _title.text.trim(),
          status: _status,
          description: _description.text.trim(),
        );
    if (mounted) Navigator.pop(context);
  }
}

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({
    required this.projects,
    this.initialProject,
    this.initialTitle,
    this.source,
    super.key,
  });
  final List<String> projects;
  final String? initialProject;
  final String? initialTitle;
  final String? source;
  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  final _description = TextEditingController();
  late String? _project = widget.initialProject;
  var _priority = 'medium';
  DateTime? _due;
  DateTime? _scheduled;
  DateTime? _remindAt;
  String? _recurrence;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Новая задача')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _project,
            decoration: const InputDecoration(labelText: 'Проект'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Inbox — без проекта'),
              ),
              ...widget.projects.map(
                (project) =>
                    DropdownMenuItem(value: project, child: Text(project)),
              ),
            ],
            onChanged: (value) => setState(() => _project = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Задача'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите название'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Приоритет'),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Низкий')),
              DropdownMenuItem(value: 'medium', child: Text('Средний')),
              DropdownMenuItem(value: 'high', child: Text('Высокий')),
            ],
            onChanged: (value) => _priority = value ?? _priority,
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            title: Text(
              _due == null
                  ? 'Без срока'
                  : '${_due!.day.toString().padLeft(2, '0')}.${_due!.month.toString().padLeft(2, '0')}.${_due!.year}',
            ),
            leading: const Icon(Icons.event_outlined),
            trailing: _due == null
                ? null
                : IconButton(
                    onPressed: () => setState(() => _due = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
                initialDate: _due ?? DateTime.now(),
              );
              if (value != null) setState(() => _due = value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              _scheduled == null
                  ? 'Не запланирована'
                  : 'Запланирована: ${_dateLabel(_scheduled!)}',
            ),
            trailing: _scheduled == null
                ? null
                : IconButton(
                    onPressed: () => setState(() => _scheduled = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: () => _pickDate(_scheduled, (value) {
              setState(() => _scheduled = value);
            }),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(
              _remindAt == null
                  ? 'Без напоминания'
                  : 'Напомнить: ${_dateLabel(_remindAt!)} ${TimeOfDay.fromDateTime(_remindAt!).format(context)}',
            ),
            trailing: _remindAt == null
                ? null
                : IconButton(
                    onPressed: () => setState(() => _remindAt = null),
                    icon: const Icon(Icons.clear),
                  ),
            onTap: _pickReminder,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _recurrence,
            decoration: const InputDecoration(
              labelText: 'Повторение',
              prefixIcon: Icon(Icons.repeat),
            ),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Не повторять')),
              DropdownMenuItem(value: 'FREQ=DAILY', child: Text('Каждый день')),
              DropdownMenuItem(value: 'FREQ=WEEKLY', child: Text('Каждую неделю')),
              DropdownMenuItem(value: 'FREQ=MONTHLY', child: Text('Каждый месяц')),
            ],
            onChanged: (value) => setState(() => _recurrence = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Описание',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.add_task),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Создать задачу'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(taskControllerProvider)
        .create(
          project: _project,
          title: _title.text.trim(),
          priority: _priority,
          due: _due,
          scheduled: _scheduled,
          remindAt: _remindAt,
          recurrence: _recurrence,
          description: _description.text.trim(),
          source: widget.source,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate(
    DateTime? initial,
    ValueChanged<DateTime> onSelected,
  ) async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: initial ?? DateTime.now(),
    );
    if (value != null) onSelected(value);
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _remindAt ?? _due ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _remindAt ?? DateTime(date.year, date.month, date.day, 9),
      ),
    );
    if (time != null) {
      setState(
        () => _remindAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class CreateProjectNoteScreen extends ConsumerStatefulWidget {
  const CreateProjectNoteScreen({
    required this.projects,
    this.initialProject,
    this.initialType = 'general',
    super.key,
  });
  final List<String> projects;
  final String? initialProject;
  final String initialType;

  @override
  ConsumerState<CreateProjectNoteScreen> createState() =>
      _CreateProjectNoteScreenState();
}

class _CreateProjectNoteScreenState
    extends ConsumerState<CreateProjectNoteScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final Map<String, TextEditingController> _sections = {};
  late String? _project = widget.initialProject ?? widget.projects.firstOrNull;
  late String _type = widget.initialType;
  var _saving = false;

  ProjectNoteDefinition get _definition => projectNoteDefinition(_type);

  @override
  void initState() {
    super.initState();
    for (final definition in projectNoteDefinitions) {
      for (final section in definition.sections) {
        _sections.putIfAbsent(section.heading, TextEditingController.new);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final controller in _sections.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Новый материал · ${_definition.label}')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text('Тип заметки', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: projectNoteDefinitions
                  .map(
                    (definition) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(definition.icon, size: 18),
                        label: Text(definition.label),
                        selected: _type == definition.key,
                        onSelected: (_) =>
                            setState(() => _type = definition.key),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _project,
            decoration: const InputDecoration(labelText: 'Проект'),
            items: widget.projects
                .map(
                  (project) =>
                      DropdownMenuItem(value: project, child: Text(project)),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _project = value),
            validator: (value) => value == null ? 'Выберите проект' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите название'
                : null,
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: Column(
              key: ValueKey(_type),
              children: _definition.sections
                  .map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _sections[section.heading],
                        minLines: section.lines,
                        maxLines: section.lines + 5,
                        decoration: InputDecoration(
                          labelText: section.heading,
                          hintText: section.hint,
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(_definition.icon),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Создать · ${_definition.label}'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(projectServiceProvider)
          .createNote(
            project: _project!,
            title: _title.text.trim(),
            noteType: _type,
            sections: {
              for (final section in _definition.sections)
                section.heading: _sections[section.heading]!.text,
            },
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось создать: $error')));
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
