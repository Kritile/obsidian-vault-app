import '../markdown/obsidian_parser.dart';
import '../markdown/work_entry_codec.dart';
import 'vault_models.dart';
import '../../shared/app_log.dart';

class VaultIndex {
  VaultIndex(this._parser, this._workCodec);
  final ObsidianParser _parser;
  final WorkEntryCodec _workCodec;
  final List<ParsedNote> notes = [];
  final List<VaultDocument> documents = [];

  void rebuild(Iterable<VaultDocument> documents) {
    this.documents
      ..clear()
      ..addAll(documents);
    notes
      ..clear()
      ..addAll(
        documents
            .where((file) => file.isMarkdown || file.isBase)
            .map(_parser.parse),
      );
    this.documents.sort((a, b) => a.path.compareTo(b.path));
    notes.sort((a, b) => a.document.path.compareTo(b.document.path));
    AppLog.info(
      'Index',
      'Индекс перестроен: ${this.documents.length} файлов, ${notes.length} заметок/баз',
    );
  }

  List<ParsedNote> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return List.unmodifiable(notes);
    return notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(normalized) ||
              note.body.toLowerCase().contains(normalized) ||
              note.tags.any((tag) => tag.toLowerCase().contains(normalized)),
        )
        .toList(growable: false);
  }

  List<VaultDocument> searchFiles(String query) {
    final normalized = query.trim().toLowerCase();
    return documents
        .where((file) => !file.isMarkdown && !file.isBase)
        .where((file) => !file.path.startsWith('.pavel-vault/'))
        .where(
          (file) =>
              normalized.isEmpty ||
              file.path.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  List<ParsedNote> get projects => notes
      .where((note) => note.type == VaultEntityType.project)
      .toList(growable: false);
  List<ParsedNote> get tasks => notes
      .where((note) => note.type == VaultEntityType.task)
      .toList(growable: false);
  List<ParsedNote> get projectNotes => notes
      .where((note) => note.type == VaultEntityType.projectNote)
      .toList(growable: false);
  List<ParsedNote> get trainings => notes
      .where((note) => note.type == VaultEntityType.training)
      .toList(growable: false);
  List<ParsedNote> get dailies => notes
      .where((note) => note.type == VaultEntityType.daily)
      .toList(growable: false);

  List<WorkEntry> workEntries(ReportPeriod period) {
    final result = <WorkEntry>[];
    for (final note in notes.where(
      (note) => note.type == VaultEntityType.daily,
    )) {
      final date = note.date;
      if (date == null ||
          date.isBefore(period.start) ||
          date.isAfter(period.end)) {
        continue;
      }
      final section = _section(note.body, 'Что было сделано');
      for (final line
          in section
              .split('\n')
              .where((line) => line.trimLeft().startsWith('-'))) {
        final entry = _workCodec.parse(
          line,
          path: note.document.path,
          date: date,
        );
        if (entry != null) result.add(entry);
      }
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  ParsedNote? byPath(String path) =>
      notes.where((note) => note.document.path == path).firstOrNull;

  ParsedNote? resolveLink(String target, {required String fromPath}) {
    var clean = target.split('#').first.trim().replaceAll('\\', '/');
    if (clean.isEmpty) return byPath(fromPath);
    if (!clean.toLowerCase().endsWith('.md')) clean = '$clean.md';
    final folder = fromPath.contains('/')
        ? fromPath.substring(0, fromPath.lastIndexOf('/'))
        : '';
    final candidates = <ParsedNote>{};
    for (final note in notes) {
      final path = note.document.path;
      final basename = path.split('/').last;
      if (path == clean ||
          path == (folder.isEmpty ? clean : '$folder/$clean') ||
          basename.toLowerCase() == clean.split('/').last.toLowerCase() ||
          note.title.toLowerCase() ==
              clean.replaceFirst(RegExp(r'\.md$'), '').toLowerCase() ||
          note.aliases.any(
            (alias) =>
                alias.toLowerCase() ==
                clean.replaceFirst(RegExp(r'\.md$'), '').toLowerCase(),
          )) {
        candidates.add(note);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  List<ParsedNote> backlinks(ParsedNote target) => notes
      .where((note) => note.document.path != target.document.path)
      .where(
        (note) => note.links.any(
          (link) =>
              resolveLink(
                link.target,
                fromPath: note.document.path,
              )?.document.path ==
              target.document.path,
        ),
      )
      .toList(growable: false);

  List<ParsedNote> related(ParsedNote target, {int limit = 12}) {
    final incoming = backlinks(
      target,
    ).map((note) => note.document.path).toSet();
    final outgoing = target.links
        .map((link) => resolveLink(link.target, fromPath: target.document.path))
        .whereType<ParsedNote>()
        .map((note) => note.document.path)
        .toSet();
    final values =
        notes
            .where((note) => note.document.path != target.document.path)
            .map((note) {
              final direct =
                  incoming.contains(note.document.path) ||
                  outgoing.contains(note.document.path);
              final sharedTags = note.tags
                  .toSet()
                  .intersection(target.tags.toSet())
                  .length;
              final sameProject =
                  note.frontmatter['project'] != null &&
                  note.frontmatter['project'] == target.frontmatter['project'];
              return (
                note: note,
                score:
                    (direct ? 1000 : 0) +
                    (sameProject ? 100 : 0) +
                    sharedTags * 10,
              );
            })
            .where((item) => item.score > 0)
            .toList()
          ..sort((a, b) {
            final score = b.score.compareTo(a.score);
            return score != 0 ? score : a.note.title.compareTo(b.note.title);
          });
    return values.take(limit).map((item) => item.note).toList(growable: false);
  }

  String _section(String body, String name) {
    final match = RegExp(
      '^#{1,6}\\s+${RegExp.escape(name)}\\s*\\r?\\n([\\s\\S]*?)(?=^#{1,6}\\s+|\\z)',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(body);
    return match?.group(1) ?? '';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
