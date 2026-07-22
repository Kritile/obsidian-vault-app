import 'dart:convert';
import 'dart:typed_data';

enum VaultEntityType {
  note,
  daily,
  project,
  task,
  projectNote,
  training,
  health,
  periodReport,
  base,
  attachment,
}

class VaultDocument {
  const VaultDocument({
    required this.path,
    required this.bytes,
    required this.modifiedAt,
    this.etag,
    this.contentHash,
  });

  final String path;
  final Uint8List bytes;
  final DateTime modifiedAt;
  final String? etag;
  final String? contentHash;

  bool get isMarkdown => path.toLowerCase().endsWith('.md');
  bool get isBase => path.toLowerCase().endsWith('.base');

  /// Markdown and Obsidian metadata are stored as UTF-8 on disk and WebDAV.
  /// Decoding bytes as Unicode code points corrupts every multibyte character
  /// in the source editor even though the parsed preview remains correct.
  String get text => utf8.decode(bytes, allowMalformed: true);

  VaultDocument copyWith({
    Uint8List? bytes,
    DateTime? modifiedAt,
    String? etag,
    String? contentHash,
  }) => VaultDocument(
    path: path,
    bytes: bytes ?? this.bytes,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    etag: etag ?? this.etag,
    contentHash: contentHash ?? this.contentHash,
  );
}

class ParsedNote {
  const ParsedNote({
    required this.document,
    required this.frontmatter,
    required this.body,
    required this.type,
    required this.tags,
    required this.links,
    required this.tasks,
  });

  final VaultDocument document;
  final Map<String, Object?> frontmatter;
  final String body;
  final VaultEntityType type;
  final List<String> tags;
  final List<WikiLink> links;
  final List<MarkdownTask> tasks;

  String get title {
    final heading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(body);
    return heading?.group(1)?.trim() ??
        document.path.split('/').last.replaceFirst(RegExp(r'\.md$'), '');
  }

  DateTime? get date => _asDate(frontmatter['date'] ?? frontmatter['created']);

  static DateTime? _asDate(Object? value) {
    if (value is DateTime) return value;
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
  }
}

class WikiLink {
  const WikiLink({required this.target, this.alias, this.embedded = false});
  final String target;
  final String? alias;
  final bool embedded;
}

class MarkdownTask {
  const MarkdownTask({
    required this.line,
    required this.text,
    required this.completed,
  });
  final int line;
  final String text;
  final bool completed;
}

class WorkEntry {
  const WorkEntry({
    required this.description,
    required this.hours,
    required this.projects,
    required this.sourcePath,
    required this.date,
  });
  final String description;
  final double hours;
  final List<String> projects;
  final String sourcePath;
  final DateTime date;
}

class TrainingLog {
  const TrainingLog({
    required this.note,
    required this.sportKey,
    required this.sport,
    required this.metrics,
    required this.assessment,
  });
  final ParsedNote note;
  final String sportKey;
  final String sport;
  final Map<String, double?> metrics;
  final Map<String, Object?> assessment;
}

class ReportPeriod {
  const ReportPeriod({
    required this.start,
    required this.end,
    required this.type,
  });
  final DateTime start;
  final DateTime end;
  final String type;
}
