// Public named constructor arguments intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../crypto/encrypted_object_store.dart';

class NoteEditingController extends ChangeNotifier {
  NoteEditingController({
    required this.path,
    required String source,
    required this.baseHash,
    required EncryptedObjectStore? store,
  }) : text = TextEditingController(text: source),
       _savedSource = source,
       _lastValue = TextEditingValue(text: source),
       _store = store {
    text.addListener(_changed);
  }

  final String path;
  final String? baseHash;
  final EncryptedObjectStore? _store;
  final TextEditingController text;
  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  late TextEditingValue _lastValue;
  String _savedSource;
  Timer? _draftTimer;
  bool _applying = false;
  String? recoveredSource;
  int _searchOffset = -1;

  String get _draftKey => '__draft_v1__:$path';
  bool get dirty => text.text != _savedSource;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> initialize() async {
    final bytes = await _store?.read(_draftKey);
    if (bytes == null) return;
    try {
      final data = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      final draft = data['source']?.toString();
      if (draft != null && draft != _savedSource) recoveredSource = draft;
    } catch (_) {
      await _store?.remove(_draftKey);
    }
  }

  void recoverDraft() {
    final source = recoveredSource;
    if (source == null) return;
    replaceValue(TextEditingValue(text: source), recordUndo: true);
    recoveredSource = null;
  }

  void discardRecoveredDraft() {
    recoveredSource = null;
    final store = _store;
    if (store != null) unawaited(store.remove(_draftKey));
  }

  void _changed() {
    if (_applying) return;
    final current = text.value;
    if (current == _lastValue) return;
    _undo.add(_lastValue);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    _lastValue = current;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 750), saveDraft);
    notifyListeners();
  }

  void replaceValue(TextEditingValue value, {bool recordUndo = true}) {
    if (recordUndo) {
      _undo.add(text.value);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _applying = true;
    text.value = value;
    _lastValue = value;
    _applying = false;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 750), saveDraft);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final value = _undo.removeLast();
    _redo.add(text.value);
    replaceValue(value, recordUndo: false);
  }

  void redo() {
    if (_redo.isEmpty) return;
    final value = _redo.removeLast();
    _undo.add(text.value);
    replaceValue(value, recordUndo: false);
  }

  int findNext(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return -1;
    final source = caseSensitive ? text.text : text.text.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    var offset = source.indexOf(needle, _searchOffset + 1);
    if (offset < 0) offset = source.indexOf(needle);
    if (offset >= 0) {
      _searchOffset = offset;
      text.selection = TextSelection(
        baseOffset: offset,
        extentOffset: offset + query.length,
      );
    }
    return offset;
  }

  bool replaceCurrent(String query, String replacement) {
    final selection = text.selection;
    if (!selection.isValid || selection.isCollapsed) return false;
    final selected = selection.textInside(text.text);
    if (selected.toLowerCase() != query.toLowerCase()) return false;
    final source = text.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    replaceValue(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(
          offset: selection.start + replacement.length,
        ),
      ),
    );
    return true;
  }

  int replaceAll(
    String query,
    String replacement, {
    bool caseSensitive = false,
  }) {
    if (query.isEmpty) return 0;
    final expression = RegExp(
      RegExp.escape(query),
      caseSensitive: caseSensitive,
    );
    final count = expression.allMatches(text.text).length;
    if (count > 0) {
      replaceValue(
        TextEditingValue(text: text.text.replaceAll(expression, replacement)),
      );
    }
    return count;
  }

  String? get wikiQuery {
    final offset = text.selection.baseOffset;
    if (offset < 0) return null;
    final before = text.text.substring(0, offset);
    final start = before.lastIndexOf('[[');
    if (start < 0 || before.lastIndexOf(']]') > start) return null;
    return before.substring(start + 2);
  }

  String? get tagQuery {
    final offset = text.selection.baseOffset;
    if (offset < 0) return null;
    final before = text.text.substring(0, offset);
    final match = RegExp(
      r'(?:^|\s)#([\p{L}\p{N}_/-]*)$',
      unicode: true,
    ).firstMatch(before);
    return match?.group(1);
  }

  void completeWiki(String target) => _replaceCurrentToken('[[', '$target]]');
  void completeTag(String tag) => _replaceCurrentToken('#', '$tag ');

  void _replaceCurrentToken(String marker, String replacement) {
    final offset = text.selection.baseOffset;
    final start = text.text.substring(0, offset).lastIndexOf(marker);
    if (start < 0) return;
    final source = text.text.replaceRange(
      start + marker.length,
      offset,
      replacement,
    );
    replaceValue(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(
          offset: start + marker.length + replacement.length,
        ),
      ),
    );
  }

  Future<void> saveDraft() async {
    final store = _store;
    if (!dirty || store == null) return;
    await store.write(
      _draftKey,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'formatVersion': 1,
            'path': path,
            'baseHash': baseHash,
            'source': text.text,
            'selection': text.selection.baseOffset,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      ),
    );
  }

  Future<void> markSaved() async {
    _savedSource = text.text;
    _draftTimer?.cancel();
    await _store?.remove(_draftKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (dirty) unawaited(saveDraft());
    text.removeListener(_changed);
    text.dispose();
    super.dispose();
  }
}
