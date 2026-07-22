import '../../app/report_controller.dart';
import '../../app/vault_controller.dart';

abstract base class VaultCreationService {
  VaultCreationService(this.vault, this.writeNote);

  final VaultController vault;
  final NoteWriter writeNote;

  Future<String> uniquePath(String folder, String name) async {
    var path = '$folder/$name.md';
    var suffix = 2;
    while (await vault.read(path) != null) {
      path = '$folder/$name-${suffix++}.md';
    }
    return path;
  }

  String safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'Без названия' : cleaned;
  }

  String yamlScalar(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
