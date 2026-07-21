import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/vault/vault_models.dart';

class DailyDateSelection {
  const DailyDateSelection({required this.date, this.note});
  final DateTime date;
  final ParsedNote? note;
}

Future<DailyDateSelection?> showDailyNoteCalendar(
  BuildContext context, {
  required Iterable<ParsedNote> notes,
}) {
  return showDialog<DailyDateSelection>(
    context: context,
    builder: (_) => _DailyNoteCalendarDialog(notes: notes),
  );
}

class _DailyNoteCalendarDialog extends StatefulWidget {
  const _DailyNoteCalendarDialog({required this.notes});
  final Iterable<ParsedNote> notes;

  @override
  State<_DailyNoteCalendarDialog> createState() =>
      _DailyNoteCalendarDialogState();
}

class _DailyNoteCalendarDialogState extends State<_DailyNoteCalendarDialog> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late final Map<String, ParsedNote> _notes = _indexNotes();

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_month.year, _month.month);
    final leading = firstDay.weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Предыдущий месяц',
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _capitalized(
                        DateFormat('LLLL yyyy', 'ru').format(_month),
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий месяц',
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                    Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 44,
                ),
                itemCount: cells,
                itemBuilder: (context, index) {
                  final dayNumber = index - leading + 1;
                  if (dayNumber < 1 || dayNumber > days) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(_month.year, _month.month, dayNumber);
                  final note = _notes[_key(date)];
                  final today = _sameDate(date, DateTime.now());
                  return Tooltip(
                    message: note == null
                        ? 'Создать заметку'
                        : 'Открыть существующую заметку',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(
                        context,
                        DailyDateSelection(date: date, note: note),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: today ? colors.secondaryContainer : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontWeight: today || note != null
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                            if (note != null)
                              Positioned(
                                bottom: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox(width: 5, height: 5),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _month = DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                      ),
                    ),
                    icon: const Icon(Icons.today, size: 18),
                    label: const Text('Сегодня'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, ParsedNote> _indexNotes() {
    final result = <String, ParsedNote>{};
    for (final note in widget.notes) {
      final date = note.date;
      if (date == null) continue;
      final key = _key(date);
      if (!result.containsKey(key) || note.document.path.startsWith('Daily/')) {
        result[key] = note;
      }
    }
    return result;
  }

  void _shiftMonth(int offset) =>
      setState(() => _month = DateTime(_month.year, _month.month + offset));

  String _key(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  String _capitalized(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
