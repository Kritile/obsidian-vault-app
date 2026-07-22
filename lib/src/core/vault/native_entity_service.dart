import 'native_entity.dart';
import 'vault_creation_support.dart';

final class NativeEntityService extends VaultCreationService {
  NativeEntityService(super.vault, super.writeNote);

  Future<String> create(
    NativeEntityKind kind,
    Map<String, Object?> values,
  ) async {
    final definition = nativeEntityDefinitions.firstWhere(
      (item) => item.kind == kind,
    );
    final title = values['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      throw ArgumentError('Название обязательно');
    }
    final path = await uniquePath(definition.folder, safeFileName(title));
    await writeNote(path, NativeEntityTemplate().build(kind, values));
    return path;
  }
}
