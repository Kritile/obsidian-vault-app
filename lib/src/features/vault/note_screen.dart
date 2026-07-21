import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/providers.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/obsidian_markdown_view.dart';
import '../reports/reports_screen.dart';
import '../../core/vault/period_report_data.dart';
import '../../core/vault/training_yaml.dart';

class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({required this.note, super.key});
  final ParsedNote note;
  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  var _editing = false;
  var _saving = false;
  late ParsedNote _note;
  late final TextEditingController _source;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _source = TextEditingController(text: _note.document.text);
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_note.title),
      actions: [
        if (_note.type == VaultEntityType.training && !_editing)
          IconButton(
            tooltip: 'Скопировать YAML тренировки',
            onPressed: _copyTrainingYaml,
            icon: const Icon(Icons.content_copy),
          ),
        IconButton(
          onPressed: () => setState(() => _editing = !_editing),
          icon: Icon(_editing ? Icons.visibility : Icons.edit_outlined),
        ),
        if (_editing)
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.save_outlined),
          ),
      ],
    ),
    body: _editing
        ? TextField(
            controller: _source,
            expands: true,
            maxLines: null,
            minLines: null,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(20),
            ),
          )
        : _reportPeriod == null
        ? Column(
            children: [
              if (_isNative(_note.document.path)) _NativeSummary(note: _note),
              Expanded(
                child: ObsidianMarkdownView(
                  source: _note.body,
                  notePath: _note.document.path,
                ),
              ),
            ],
          )
        : PeriodReportView(period: _reportPeriod!),
  );

  ReportPeriod? get _reportPeriod =>
      const ReportPeriodResolver().fromNote(_note);

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = ref.read(appControllerProvider);
    try {
      await controller.saveNote(_note.document.path, _source.text);
      if (!mounted) return;
      setState(() {
        _note = controller.index.byPath(_note.document.path) ?? _note;
        _editing = false;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    }
  }

  Future<void> _copyTrainingYaml() async {
    await Clipboard.setData(ClipboardData(text: trainingYaml(_note)));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('YAML тренировки скопирован')));
  }

  bool _isNative(String path) =>
      path.startsWith('Areas/Книги/') ||
      path.startsWith('Areas/Recipes/') ||
      path.startsWith('Areas/Растения/') ||
      path.startsWith('Areas/Чай/') ||
      path.startsWith('Areas/Аптечка/');
}

class _NativeSummary extends StatelessWidget {
  const _NativeSummary({required this.note});
  final ParsedNote note;

  @override
  Widget build(BuildContext context) {
    final fields = note.frontmatter.entries
        .where(
          (entry) =>
              entry.value != null &&
              entry.value.toString().isNotEmpty &&
              !const {
                'tags',
                'title',
                'created',
                'updated',
              }.contains(entry.key),
        )
        .take(8);
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: fields
            .map(
              (entry) => Chip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(
                  '${entry.key}: ${_value(entry.value)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  String _value(Object? value) {
    if (value is List) return value.join(', ');
    if (value is Map) return '${value.length} полей';
    return value.toString();
  }
}
