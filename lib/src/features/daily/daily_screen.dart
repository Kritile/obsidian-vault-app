import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/page_scaffold.dart';
import '../vault/note_screen.dart';
import 'training_form_screen.dart';

class DailyScreen extends ConsumerStatefulWidget {
  const DailyScreen({super.key});
  @override
  ConsumerState<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends ConsumerState<DailyScreen> {
  late DateTime _selected = _day(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vaultControllerProvider);
    final end = _selected
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    final entries = controller.index.workEntries(
      ReportPeriod(start: _selected, end: end, type: 'daily'),
    );
    final trainings =
        controller.index.trainings
            .where((note) => _sameDay(note.date, _selected))
            .toList()
          ..sort(
            (a, b) => (a.frontmatter['time']?.toString() ?? '').compareTo(
              b.frontmatter['time']?.toString() ?? '',
            ),
          );
    final isToday = _sameDay(_selected, DateTime.now());
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return PageScaffold(
      title: isToday ? 'Сегодня' : DateFormat('EEEE', 'ru').format(_selected),
      subtitle: DateFormat('d MMMM yyyy', 'ru').format(_selected),
      actions: [
        FilledButton.tonalIcon(
          onPressed: _addTraining,
          icon: const Icon(Icons.fitness_center),
          label: const Text('Тренировка'),
        ),
        FilledButton.icon(
          onPressed: _addWork,
          icon: const Icon(Icons.add),
          label: const Text('Работа'),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 8 : 20, 0, narrow ? 8 : 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Предыдущий день',
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        DateFormat('EEE, d MMM', 'ru').format(_selected),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!isToday)
                    IconButton(
                      tooltip: 'Сегодня',
                      onPressed: () =>
                          setState(() => _selected = _day(DateTime.now())),
                      icon: const Icon(Icons.today),
                    ),
                  IconButton(
                    tooltip: 'Следующий день',
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Выполненная работа',
            icon: Icons.task_alt,
            empty: 'За этот день записей пока нет',
            children: entries
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        entry.hours.toStringAsFixed(
                          entry.hours % 1 == 0 ? 0 : 1,
                        ),
                      ),
                    ),
                    title: Text(entry.description),
                    subtitle: Text(
                      entry.projects.map((item) => '#$item').join(' '),
                    ),
                    trailing: const Text('ч'),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Тренировки',
            icon: Icons.fitness_center,
            empty: 'Тренировок за этот день нет',
            trailing: IconButton(
              onPressed: _addTraining,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Добавить тренировку',
            ),
            children: trainings
                .map((training) {
                  final metrics =
                      training.frontmatter['metrics']
                          as Map<String, Object?>? ??
                      const {};
                  final assessment =
                      training.frontmatter['assessment']
                          as Map<String, Object?>? ??
                      const {};
                  final sport = _sportName(training);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        _sportIcon(
                          training.frontmatter['sport_key']?.toString(),
                        ),
                      ),
                    ),
                    title: Text(
                      '$sport${training.frontmatter['time'] == null ? '' : ' · ${training.frontmatter['time']}'}',
                    ),
                    subtitle: Text(
                      [
                        if (metrics['duration'] != null)
                          '${metrics['duration']} мин',
                        if (metrics['distance'] != null)
                          '${metrics['distance']} км',
                        if (metrics['avg_hr'] != null)
                          'пульс ${metrics['avg_hr']}',
                        if (assessment['load'] != null)
                          'нагрузка ${assessment['load']}',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NoteScreen(note: training),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  void _shift(int days) =>
      setState(() => _selected = _selected.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => _selected = _day(value));
  }

  Future<void> _addWork() async {
    final description = TextEditingController();
    final hours = TextEditingController();
    final projects = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Работа · ${DateFormat('dd.MM.yyyy').format(_selected)}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: description,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Что сделано'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hours,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Часы'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: projects,
                  decoration: const InputDecoration(
                    labelText: 'Проекты через запятую',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    final parsedHours = double.tryParse(hours.text.replaceAll(',', '.'));
    if (saved == true &&
        description.text.trim().isNotEmpty &&
        parsedHours != null) {
      await ref
          .read(dailyNoteServiceProvider)
          .addWorkEntry(
            date: _selected,
            description: description.text,
            hours: parsedHours,
            projects: projects.text
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
          );
    }
  }

  void _addTraining() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TrainingFormScreen(date: _selected)),
  );

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  bool _sameDay(DateTime? left, DateTime right) =>
      left != null &&
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  String _sportName(ParsedNote note) {
    final value = note.frontmatter['sport'];
    return value is List && value.isNotEmpty
        ? value.first.toString()
        : value?.toString() ?? 'Тренировка';
  }

  String _sportIcon(String? key) => switch (key) {
    'rowing' => '🚣',
    'bike' => '🚴',
    'rope' => '🪢',
    'tennis' => '🏓',
    _ => '🏃',
  };
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.empty,
    required this.children,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final String empty;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(empty),
            )
          else
            ...children,
        ],
      ),
    ),
  );
}
