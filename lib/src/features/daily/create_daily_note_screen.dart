import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../vault/note_screen.dart';

class CreateDailyNoteScreen extends ConsumerStatefulWidget {
  const CreateDailyNoteScreen({required this.date, super.key});
  final DateTime date;

  @override
  ConsumerState<CreateDailyNoteScreen> createState() =>
      _CreateDailyNoteScreenState();
}

class _CreateDailyNoteScreenState extends ConsumerState<CreateDailyNoteScreen> {
  final _form = GlobalKey<FormState>();
  final _steps = TextEditingController();
  final _sleep = TextEditingController();
  final _calories = TextEditingController();
  final _completed = TextEditingController();
  final _tomorrow = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _steps.dispose();
    _sleep.dispose();
    _calories.dispose();
    _completed.dispose();
    _tomorrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Новая ежедневная заметка')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.today)),
              title: Text(
                _capitalized(
                  DateFormat('EEEE, d MMMM yyyy', 'ru').format(widget.date),
                ),
              ),
              subtitle: const Text(
                'После создания заметка будет отправлена в WebDAV',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Показатели дня',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      controller: _steps,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Шаги',
                        suffixText: 'шагов',
                      ),
                      validator: (value) => _optionalInteger(value),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      controller: _sleep,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Сон',
                        suffixText: 'часов',
                      ),
                      validator: (value) => _optionalNumber(value),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      controller: _calories,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Калории',
                        suffixText: 'ккал',
                      ),
                      validator: (value) => _optionalInteger(value),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _completed,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Что было сделано',
              hintText: '- Описание - 1ч - #Проект',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tomorrow,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Что нужно сделать завтра',
              hintText: '- Задача',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.note_add_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Text('Создать заметку'),
            ),
          ),
        ],
      ),
    ),
  );

  String? _optionalInteger(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    return number == null || number < 0 ? 'Введите целое число' : null;
  }

  String? _optionalNumber(String? value) {
    final text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) return null;
    final number = double.tryParse(text);
    return number == null || number < 0 ? 'Введите число' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(appControllerProvider);
    try {
      final path = await controller.createDailyNote(
        date: widget.date,
        steps: _steps.text,
        sleep: _sleep.text.replaceAll(',', '.'),
        calories: _calories.text,
        completed: _completed.text,
        tomorrow: _tomorrow.text,
      );
      final note = controller.index.byPath(path);
      if (!mounted) return;
      if (note == null) {
        throw StateError('Созданная заметка не найдена в индексе');
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => NoteScreen(note: note)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось создать: $error')));
    }
  }

  String _capitalized(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
