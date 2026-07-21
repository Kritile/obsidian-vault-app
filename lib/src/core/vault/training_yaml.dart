import 'vault_models.dart';

String trainingYaml(ParsedNote note) {
  final source = note.document.text;
  final match = RegExp(
    r'^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)',
  ).firstMatch(source);
  if (match != null) return match.group(1)!.trimRight();
  return note.frontmatter.entries
      .map((entry) => '${entry.key}: ${_yamlValue(entry.value)}')
      .join('\n');
}

String _yamlValue(Object? value, [int depth = 0]) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  if (value is List) {
    if (value.isEmpty) return '[]';
    return '\n${value.map((item) => '${'  ' * (depth + 1)}- ${_yamlValue(item, depth + 1)}').join('\n')}';
  }
  if (value is Map) {
    if (value.isEmpty) return '{}';
    return '\n${value.entries.map((entry) => '${'  ' * (depth + 1)}${entry.key}: ${_yamlValue(entry.value, depth + 1)}').join('\n')}';
  }
  final text = value.toString();
  if (RegExp(r'^[\p{L}\p{N}_./ -]+$', unicode: true).hasMatch(text) &&
      !const {
        'null',
        'true',
        'false',
        'yes',
        'no',
      }.contains(text.toLowerCase())) {
    return text;
  }
  return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
