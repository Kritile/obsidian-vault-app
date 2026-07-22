import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/vault/vault_models.dart';
import '../../core/editor/note_editing_controller.dart';
import '../../shared/obsidian_markdown_view.dart';
import '../reports/reports_screen.dart';
import '../../core/vault/period_report_data.dart';
import '../../core/vault/training_yaml.dart';
import '../../shared/rich_clipboard.dart';

class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({required this.note, super.key});
  final ParsedNote note;
  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen>
    with WidgetsBindingObserver {
  var _editing = false;
  var _saving = false;
  late ParsedNote _note;
  late final NoteEditingController _editor;
  final _search = TextEditingController();
  final _replacement = TextEditingController();
  var _searching = false;

  TextEditingController get _source => _editor.text;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.note;
    final vault = ref.read(vaultControllerProvider);
    _editor = NoteEditingController(
      path: _note.document.path,
      source: _note.document.text,
      baseHash: _note.document.contentHash,
      store: vault.ready ? vault.store : null,
    )..addListener(_editorChanged);
    unawaited(_loadDraft());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor
      ..removeListener(_editorChanged)
      ..dispose();
    _search.dispose();
    _replacement.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_editor.saveDraft());
    }
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
        if (_editing) ...[
          IconButton(
            tooltip: 'Отменить',
            onPressed: _editor.canUndo ? _editor.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Повторить',
            onPressed: _editor.canRedo ? _editor.redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Поиск и замена',
            onPressed: () => setState(() => _searching = !_searching),
            icon: const Icon(Icons.find_replace),
          ),
          IconButton(
            tooltip: 'Свойства YAML',
            onPressed: _editProperties,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Вставить вложение',
            onPressed: _insertAttachment,
            icon: const Icon(Icons.attach_file),
          ),
        ],
        IconButton(
          onPressed: () => setState(() => _editing = !_editing),
          icon: Icon(_editing ? Icons.visibility : Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Переименовать или переместить',
          onPressed: _moveNote,
          icon: const Icon(Icons.drive_file_move_outline),
        ),
        IconButton(
          tooltip: 'Удалить заметку',
          onPressed: _deleteNote,
          icon: const Icon(Icons.delete_outline),
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
        ? Column(
            children: [
              if (_searching) _buildSearchBar(),
              ?_buildSuggestions(),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyZ,
                      control: true,
                    ): _editor.undo,
                    const SingleActivator(
                      LogicalKeyboardKey.keyY,
                      control: true,
                    ): _editor.redo,
                    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                        _editor.undo,
                    const SingleActivator(
                      LogicalKeyboardKey.keyZ,
                      meta: true,
                      shift: true,
                    ): _editor.redo,
                  },
                  child: TextField(
                    controller: _source,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(20),
                    ),
                    contextMenuBuilder: (context, editableTextState) {
                      final items = editableTextState.contextMenuButtonItems
                          .map(
                            (item) => item.type != ContextMenuButtonType.paste
                                ? item
                                : ContextMenuButtonItem(
                                    type: item.type,
                                    label: item.label,
                                    onPressed: () {
                                      editableTextState.hideToolbar();
                                      RichClipboard.pasteInto(_source);
                                    },
                                  ),
                          )
                          .toList(growable: false);
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: items,
                      );
                    },
                  ),
                ),
              ),
            ],
          )
        : _reportPeriod == null
        ? Column(
            children: [
              if (_isNative(_note.document.path)) _NativeSummary(note: _note),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ObsidianMarkdownView(
                        source: _note.body,
                        notePath: _note.document.path,
                        onWikiLink: _openWikiLink,
                        onToggleTask: _toggleTask,
                      ),
                    ),
                    _Connections(
                      backlinks: ref
                          .read(vaultControllerProvider)
                          .index
                          .backlinks(_note),
                      related: ref
                          .read(vaultControllerProvider)
                          .index
                          .related(_note),
                      onOpen: _openNote,
                    ),
                  ],
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
    final sync = ref.read(syncControllerProvider);
    final vault = ref.read(vaultControllerProvider);
    try {
      await sync.saveNote(_note.document.path, _source.text);
      await _editor.markSaved();
      if (!mounted) return;
      setState(() {
        _note = vault.index.byPath(_note.document.path) ?? _note;
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

  void _editorChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDraft() async {
    await _editor.initialize();
    if (!mounted || _editor.recoveredSource == null) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Найден автосохранённый черновик'),
        content: const Text(
          'Восстановить изменения, не сохранённые в заметку?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Удалить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    if (restore == true) {
      _editor.recoverDraft();
      setState(() => _editing = true);
    } else {
      _editor.discardRecoveredDraft();
    }
  }

  Widget _buildSearchBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 210,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Найти',
                isDense: true,
              ),
              onSubmitted: (value) => _editor.findNext(value),
            ),
          ),
          SizedBox(
            width: 210,
            child: TextField(
              controller: _replacement,
              decoration: const InputDecoration(
                labelText: 'Заменить',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующее совпадение',
            onPressed: () => _editor.findNext(_search.text),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          TextButton(
            onPressed: () =>
                _editor.replaceCurrent(_search.text, _replacement.text),
            child: const Text('Заменить'),
          ),
          TextButton(
            onPressed: () =>
                _editor.replaceAll(_search.text, _replacement.text),
            child: const Text('Заменить все'),
          ),
        ],
      ),
    ),
  );

  Widget? _buildSuggestions() {
    final vault = ref.read(vaultControllerProvider);
    final wiki = _editor.wikiQuery;
    final tag = _editor.tagQuery;
    Iterable<String> values;
    ValueChanged<String> complete;
    if (wiki != null) {
      values = vault.index.notes
          .where((note) => note.document.path != _note.document.path)
          .where(
            (note) =>
                note.title.toLowerCase().contains(wiki.toLowerCase()) ||
                note.document.path.toLowerCase().contains(wiki.toLowerCase()),
          )
          .map((note) => note.document.path.replaceFirst(RegExp(r'\.md$'), ''));
      complete = _editor.completeWiki;
    } else if (tag != null) {
      values = vault.index.notes
          .expand((note) => note.tags)
          .toSet()
          .where((value) => value.toLowerCase().contains(tag.toLowerCase()));
      complete = _editor.completeTag;
    } else {
      return null;
    }
    final suggestions = values.take(8).toList(growable: false);
    if (suggestions.isEmpty) return null;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final value in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(value),
                onPressed: () => complete(value),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _insertAttachment() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final settings = ref.read(settingsControllerProvider);
    final vault = ref.read(vaultControllerProvider);
    final sync = ref.read(syncControllerProvider);
    final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var path = p.posix.join(settings.attachmentFolder, safeName);
    var suffix = 2;
    while (await vault.read(path) != null) {
      path = p.posix.join(
        settings.attachmentFolder,
        '${p.basenameWithoutExtension(safeName)}-$suffix${p.extension(safeName)}',
      );
      suffix++;
    }
    await sync.saveAttachment(path, bytes);
    final image = RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|svg)$',
      caseSensitive: false,
    ).hasMatch(path);
    _insertText('${image ? '!' : ''}[[$path]]');
  }

  void _insertText(String value) {
    final selection = _source.selection;
    final start = selection.isValid ? selection.start : _source.text.length;
    final end = selection.isValid ? selection.end : start;
    final source = _source.text.replaceRange(start, end, value);
    _editor.replaceValue(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: start + value.length),
      ),
    );
  }

  Future<void> _editProperties() async {
    final parser = ref.read(vaultControllerProvider).parser;
    final current = parser.parse(
      VaultDocument(
        path: _note.document.path,
        bytes: parser.encode(_source.text),
        modifiedAt: DateTime.now(),
      ),
    );
    final controllers = {
      for (final entry in current.frontmatter.entries)
        entry.key: TextEditingController(text: _propertyText(entry.value)),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Свойства YAML'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: entry.value,
                    decoration: InputDecoration(labelText: entry.key),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    if (saved == true) {
      var source = _source.text;
      for (final entry in controllers.entries) {
        source = parser.updateFrontmatter(source, [
          entry.key,
        ], _propertyValue(entry.value.text, current.frontmatter[entry.key]));
      }
      _editor.replaceValue(TextEditingValue(text: source));
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  String _propertyText(Object? value) => value is Map || value is List
      ? jsonEncode(value)
      : value?.toString() ?? '';

  Object? _propertyValue(String value, Object? original) {
    if (original is bool) return value.toLowerCase() == 'true';
    if (original is int) return int.tryParse(value) ?? original;
    if (original is double) return double.tryParse(value) ?? original;
    if (original is Map || original is List) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return original;
      }
    }
    return value;
  }

  Future<void> _toggleTask(int index, bool checked) async {
    var seen = 0;
    final source = _note.document.text.replaceAllMapped(
      RegExp(r'^(\s*-\s+\[)([ xX-])(\])', multiLine: true),
      (match) {
        if (seen++ != index) return match.group(0)!;
        return '${match.group(1)}${checked ? 'x' : ' '}${match.group(3)}';
      },
    );
    await ref
        .read(syncControllerProvider)
        .saveNote(_note.document.path, source);
    final updated = ref
        .read(vaultControllerProvider)
        .index
        .byPath(_note.document.path);
    if (mounted && updated != null) {
      setState(() {
        _note = updated;
        _editor.replaceValue(TextEditingValue(text: source), recordUndo: true);
      });
      await _editor.markSaved();
    }
  }

  void _openWikiLink(String target) {
    final index = ref.read(vaultControllerProvider).index;
    final note = index.resolveLink(target, fromPath: _note.document.path);
    if (note != null) _openNote(note);
  }

  void _openNote(ParsedNote note) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => NoteScreen(note: note)));
  }

  Future<void> _moveNote() async {
    final controller = TextEditingController(text: _note.document.path);
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать или переместить'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Путь внутри vault'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Переместить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (path == null || path.isEmpty || path == _note.document.path) return;
    try {
      await ref
          .read(syncControllerProvider)
          .moveNote(_note.document.path, path);
      if (!mounted) return;
      final moved = ref
          .read(vaultControllerProvider)
          .index
          .byPath(path.toLowerCase().endsWith('.md') ? path : '$path.md');
      if (moved != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => NoteScreen(note: moved)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переместить заметку: $error')),
      );
    }
  }

  Future<void> _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: Text(
          '${_note.document.path}\n\nУдаление сохранится локально и будет повторено на WebDAV после восстановления сети.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncControllerProvider).deleteNote(_note.document.path);
    if (mounted) Navigator.of(context).pop();
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

class _Connections extends StatelessWidget {
  const _Connections({
    required this.backlinks,
    required this.related,
    required this.onOpen,
  });

  final List<ParsedNote> backlinks;
  final List<ParsedNote> related;
  final ValueChanged<ParsedNote> onOpen;

  @override
  Widget build(BuildContext context) {
    if (backlinks.isEmpty && related.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 132),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: ListView(
        children: [
          if (backlinks.isNotEmpty) ...[
            Text(
              'Обратные ссылки',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final note in backlinks)
                  ActionChip(
                    avatar: const Icon(Icons.reply, size: 16),
                    label: Text(note.title),
                    onPressed: () => onOpen(note),
                  ),
              ],
            ),
          ],
          if (related.isNotEmpty) ...[
            Text(
              'Связанные заметки',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final note in related)
                  ActionChip(
                    avatar: const Icon(Icons.hub_outlined, size: 16),
                    label: Text(note.title),
                    onPressed: () => onOpen(note),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
