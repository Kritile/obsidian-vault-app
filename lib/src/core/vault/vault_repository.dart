import 'vault_models.dart';

abstract interface class VaultRepository {
  Future<List<VaultDocument>> list();
  Future<VaultDocument?> read(String path);
  Future<void> write(VaultDocument document, {String? expectedEtag});
  Future<void> move(String from, String to, {String? expectedEtag});
  Future<void> delete(String path, {String? expectedEtag});
}

abstract interface class BatchableVaultRepository {
  Future<void> beginBatch();
  Future<void> endBatch();
}
