import '../vault/vault_models.dart';

class WorkEntryCodec {
  static final _hours = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:ч|h)(?:\b|\s|$)', caseSensitive: false);
  static final _tag = RegExp(r'#[\p{L}\p{N}_-]+', unicode: true);

  WorkEntry? parse(String line, {required String path, required DateTime date}) {
    final trimmed = line.trim().replaceFirst(RegExp(r'^-\s*'), '');
    final hoursMatch = _hours.firstMatch(trimmed);
    if (hoursMatch == null) return null;
    final hours = double.tryParse(hoursMatch.group(1)!.replaceAll(',', '.'));
    if (hours == null) return null;
    final projects = _tag
        .allMatches(trimmed)
        .map((match) => match.group(0)!.substring(1))
        .toList(growable: false);
    final description = trimmed
        .replaceAll(_hours, '')
        .replaceAll(_tag, '')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim()
        .replaceFirst(RegExp(r'\s*-\s*$'), '')
        .trim();
    return WorkEntry(
      description: description,
      hours: hours,
      projects: projects,
      sourcePath: path,
      date: date,
    );
  }

  String encode(String description, double hours, Iterable<String> projects) {
    final value = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    final tags = projects.map((project) => '#${project.replaceAll(' ', '-') }').join(' ');
    return '- ${description.trim()} - $valueч${tags.isEmpty ? '' : ' - $tags'}';
  }
}
