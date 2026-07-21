import 'dart:io';
import 'dart:typed_data';

import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments.isEmpty ? '..' : arguments.first);
  if (!await root.exists()) {
    stderr.writeln('Vault does not exist: ${root.path}');
    exitCode = 2;
    return;
  }
  final parser = ObsidianParser();
  var markdown = 0;
  var parsed = 0;
  var malformed = 0;
  final types = <VaultEntityType, int>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.path.contains('${Platform.pathSeparator}.git${Platform.pathSeparator}') ||
        entity.path.contains('${Platform.pathSeparator}pavel_vault_app${Platform.pathSeparator}')) {
      continue;
    }
    markdown++;
    try {
      final bytes = Uint8List.fromList(await entity.readAsBytes());
      final relative = entity.path.substring(root.path.length).replaceFirst(RegExp(r'^[/\\]'), '').replaceAll('\\', '/');
      final note = parser.parse(VaultDocument(
        path: relative,
        bytes: bytes,
        modifiedAt: await entity.lastModified(),
      ));
      parsed++;
      types[note.type] = (types[note.type] ?? 0) + 1;
    } catch (error) {
      malformed++;
      stderr.writeln('${entity.path}: $error');
    }
  }
  stdout.writeln('Markdown files: $markdown');
  stdout.writeln('Parsed: $parsed');
  stdout.writeln('Errors: $malformed');
  for (final entry in types.entries) {
    stdout.writeln('${entry.key.name}: ${entry.value}');
  }
  if (malformed > 0 || parsed != markdown) exitCode = 1;
}

