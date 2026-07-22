import 'package:flutter/material.dart';

enum DurationValueUnit { hours, minutes }

class DurationInputField extends StatefulWidget {
  const DurationInputField({
    required this.controller,
    required this.label,
    required this.unit,
    this.required = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final DurationValueUnit unit;
  final bool required;

  @override
  State<DurationInputField> createState() => _DurationInputFieldState();
}

class _DurationInputFieldState extends State<DurationInputField> {
  late final TextEditingController _display;

  @override
  void initState() {
    super.initState();
    _display = TextEditingController(text: _format(widget.controller.text));
  }

  @override
  void dispose() {
    _display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _display,
    readOnly: true,
    onTap: _pick,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.unit == DurationValueUnit.hours
          ? 'Выберите часы и минуты'
          : 'Выберите минуты и секунды',
      suffixIcon: const Icon(Icons.timer_outlined),
    ),
    validator: (_) {
      final value = double.tryParse(widget.controller.text);
      if (widget.required && (value == null || value <= 0)) {
        return 'Укажите длительность';
      }
      return null;
    },
  );

  Future<void> _pick() async {
    final current = _parts(widget.controller.text);
    final major = TextEditingController(text: current.$1.toString());
    final minor = TextEditingController(text: current.$2.toString());
    final form = GlobalKey<FormState>();
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: Form(
          key: form,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: major,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.unit == DurationValueUnit.hours
                        ? 'Часы'
                        : 'Минуты',
                  ),
                  validator: (value) => _wholeNumber(value, max: 999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: minor,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.unit == DurationValueUnit.hours
                        ? 'Минуты'
                        : 'Секунды',
                  ),
                  validator: (value) => _wholeNumber(value, max: 59),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.controller.text.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, (0, 0)),
              child: const Text('Очистить'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, (
                int.parse(major.text),
                int.parse(minor.text),
              ));
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    major.dispose();
    minor.dispose();
    if (result == null || !mounted) return;
    if (result.$1 == 0 && result.$2 == 0) {
      widget.controller.clear();
      _display.clear();
      return;
    }
    final value = result.$1 + result.$2 / 60;
    widget.controller.text = _decimal(value);
    _display.text = _format(widget.controller.text);
  }

  String? _wholeNumber(String? source, {required int max}) {
    final value = int.tryParse(source ?? '');
    if (value == null || value < 0 || value > max) return '0–$max';
    return null;
  }

  (int, int) _parts(String source) {
    final value = double.tryParse(source.replaceAll(',', '.')) ?? 0;
    var major = value.floor();
    var minor = ((value - major) * 60).round();
    if (minor == 60) {
      major++;
      minor = 0;
    }
    return (major, minor);
  }

  String _format(String source) {
    if (source.trim().isEmpty) return '';
    final parts = _parts(source);
    if (widget.unit == DurationValueUnit.hours) {
      return '${parts.$1} ч ${parts.$2} мин';
    }
    return '${parts.$1} мин ${parts.$2} сек';
  }

  String _decimal(double value) {
    final fixed = value.toStringAsFixed(6);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
