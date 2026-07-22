import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/vault/training_definition.dart';
import '../../shared/duration_input_field.dart';

class TrainingFormScreen extends ConsumerStatefulWidget {
  const TrainingFormScreen({required this.date, super.key});
  final DateTime date;
  @override
  ConsumerState<TrainingFormScreen> createState() => _TrainingFormScreenState();
}

class _TrainingFormScreenState extends ConsumerState<TrainingFormScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _metrics = {};
  final _analysis = TextEditingController();
  var _sportKey = 'bike';
  var _mood = 'good';
  late TimeOfDay _time = TimeOfDay.now();

  TrainingDefinition get _sport => trainingDefinition(_sportKey);

  @override
  void initState() {
    super.initState();
    for (final definition in trainingDefinitions) {
      for (final metric in definition.metrics) {
        _metrics.putIfAbsent(metric.key, TextEditingController.new);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _metrics.values) {
      controller.dispose();
    }
    _analysis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'Тренировка · ${widget.date.day.toString().padLeft(2, '0')}.${widget.date.month.toString().padLeft(2, '0')}.${widget.date.year}',
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'Вид тренировки',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: trainingDefinitions
                  .map(
                    (sport) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Text(sport.icon),
                        label: Text(sport.name),
                        selected: _sportKey == sport.key,
                        onSelected: (_) =>
                            setState(() => _sportKey = sport.key),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _mood,
                  decoration: const InputDecoration(labelText: 'Самочувствие'),
                  items: const [
                    DropdownMenuItem(value: 'good', child: Text('Хорошее')),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Text('Нормальное'),
                    ),
                    DropdownMenuItem(value: 'tired', child: Text('Усталость')),
                    DropdownMenuItem(value: 'bad', child: Text('Плохое')),
                  ],
                  onChanged: (value) => _mood = value ?? _mood,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _selectTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Время'),
                    child: Text(_time.format(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '${_sport.icon} Показатели · ${_sport.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Chip(label: Text('Риск: ${_sport.jointRisk}')),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _sport.metrics
                    .map(
                      (metric) => SizedBox(
                        width: fieldWidth,
                        child: metric.key == 'duration'
                            ? DurationInputField(
                                key: ValueKey('${_sport.key}-${metric.key}'),
                                controller: _metrics[metric.key]!,
                                label: metric.label,
                                unit: DurationValueUnit.minutes,
                                required: metric.required,
                              )
                            : TextFormField(
                                key: ValueKey('${_sport.key}-${metric.key}'),
                                controller: _metrics[metric.key],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: metric.label,
                                  suffixText: metric.unit.isEmpty
                                      ? null
                                      : metric.unit,
                                ),
                                validator: metric.required
                                    ? (value) =>
                                          _number(value) == null ||
                                              _number(value)! <= 0
                                          ? 'Введите значение больше нуля'
                                          : null
                                    : (value) =>
                                          value != null &&
                                              value.trim().isNotEmpty &&
                                              _number(value) == null
                                          ? 'Требуется число'
                                          : null,
                              ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _analysis,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Анализ и самочувствие после тренировки',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Text('Сохранить тренировку'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _selectTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  double? _number(String? value) => value == null || value.trim().isEmpty
      ? null
      : double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final date = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      _time.hour,
      _time.minute,
    );
    await ref
        .read(trainingServiceProvider)
        .create(
          date: date,
          sportKey: _sportKey,
          metrics: {
            for (final metric in _sport.metrics)
              metric.key: _number(_metrics[metric.key]!.text),
          },
          mood: _mood,
          analysis: _analysis.text,
        );
    if (mounted) Navigator.pop(context);
  }
}
