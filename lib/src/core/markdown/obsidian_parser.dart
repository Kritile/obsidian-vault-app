import 'dart:convert';
import 'dart:typed_data';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../vault/vault_models.dart';

class ObsidianParser {
  static final _frontmatter = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)');
  static final _wikiLink = RegExp(
    r'(!)?\[\[([^\]|#]+(?:#[^\]|]+)?)(?:\|([^\]]+))?\]\]',
  );
  static final _task = RegExp(r'^\s*-\s+\[([ xX-])\]\s+(.+)$');

  ParsedNote parse(VaultDocument document) {
    final text = utf8.decode(document.bytes, allowMalformed: true);
    final match = _frontmatter.firstMatch(text);
    final yamlText = match?.group(1) ?? '';
    final body = match == null ? text : text.substring(match.end);
    final frontmatter = _yamlMap(yamlText);
    final tags = {
      ..._tags(frontmatter['tags']),
      ...RegExp(
        r'(?:^|\s)#([\p{L}\p{N}_/-]+)',
        unicode: true,
      ).allMatches(body).map((match) => match.group(1)!),
    }.toList(growable: false);
    final links = _wikiLink
        .allMatches(body)
        .map(
          (match) => WikiLink(
            target: match.group(2)!.trim(),
            alias: match.group(3)?.trim(),
            embedded: match.group(1) != null,
          ),
        )
        .toList(growable: false);
    final tasks = <MarkdownTask>[];
    final lines = const LineSplitter().convert(body);
    for (var index = 0; index < lines.length; index++) {
      final taskMatch = _task.firstMatch(lines[index]);
      if (taskMatch != null) {
        tasks.add(
          MarkdownTask(
            line: index,
            text: taskMatch.group(2)!.trim(),
            completed: taskMatch.group(1)!.toLowerCase() == 'x',
          ),
        );
      }
    }
    return ParsedNote(
      document: document,
      frontmatter: frontmatter,
      body: body,
      type: _type(document.path, frontmatter),
      tags: tags,
      links: links,
      tasks: tasks,
    );
  }

  String updateFrontmatter(String source, List<Object> path, Object? value) {
    final match = _frontmatter.firstMatch(source);
    if (match == null) {
      final editor = YamlEditor('{}')..update(path, value);
      return '---\n${editor.toString()}\n---\n\n$source';
    }
    final editor = YamlEditor(match.group(1)!)..update(path, value);
    return source.replaceRange(match.start, match.end, '---\n$editor\n---\n');
  }

  String replaceSection(String source, String heading, String content) {
    final escaped = RegExp.escape(heading.trim());
    final section = RegExp(
      '^(#{1,6})\\s+$escaped\\s*\\r?\\n([\\s\\S]*?)(?=^#{1,6}\\s+|\\z)',
      multiLine: true,
    );
    final match = section.firstMatch(source);
    final normalized = content.trimRight();
    if (match == null) {
      return '${source.trimRight()}\n\n### $heading\n\n$normalized\n';
    }
    return source.replaceRange(
      match.start,
      match.end,
      '${match.group(1)} $heading\n\n$normalized\n\n',
    );
  }

  Map<String, Object?> _yamlMap(String source) {
    if (source.trim().isEmpty) return <String, Object?>{};
    try {
      final node = loadYaml(source);
      return node is YamlMap
          ? Map<String, Object?>.from(_plain(node)! as Map)
          : <String, Object?>{};
    } on YamlException {
      return <String, Object?>{};
    }
  }

  Object? _plain(Object? value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _plain(entry.value),
      };
    }
    if (value is YamlList) return value.map(_plain).toList(growable: false);
    return value;
  }

  List<String> _tags(Object? value) {
    if (value is List) {
      return value.map((tag) => tag.toString()).toList(growable: false);
    }
    if (value is String) {
      return value
          .replaceAll(RegExp(r'^\[|\]$'), '')
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  VaultEntityType _type(String path, Map<String, Object?> yaml) {
    final type = yaml['type']?.toString();
    return switch (type) {
      'project' => VaultEntityType.project,
      'task' => VaultEntityType.task,
      'project-note' => VaultEntityType.projectNote,
      'training-log' => VaultEntityType.training,
      'health-log' => VaultEntityType.health,
      'period-report' => VaultEntityType.periodReport,
      _ when path.startsWith('Daily/') || path.contains('/Daily/') =>
        VaultEntityType.daily,
      _ when path.endsWith('.base') => VaultEntityType.base,
      _ => VaultEntityType.note,
    };
  }

  Uint8List encode(String value) => Uint8List.fromList(utf8.encode(value));
}
