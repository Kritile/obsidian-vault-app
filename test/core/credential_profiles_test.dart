import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/crypto/credential_store.dart';
import 'package:pavel_vault/src/core/sync/webdav_profile.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'legacy single WebDAV connection migrates to an active profile',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'webdav.url': 'https://cloud.example/vault/',
        'webdav.username': 'pavel',
        'webdav.password': 'secret',
      });
      final store = CredentialStore();

      final profiles = await store.readProfiles();

      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'cloud.example');
      expect(await store.readActiveProfileId(), profiles.single.id);
      expect((await store.readWebDav())?.username, 'pavel');
    },
  );

  test('profiles can be saved, selected and removed independently', () async {
    final store = CredentialStore();
    final first = WebDavProfile(
      id: 'first',
      name: 'Основное',
      baseUrl: Uri.parse('https://one.example/vault/'),
      username: 'one',
      password: 'a',
    );
    final second = WebDavProfile(
      id: 'second',
      name: 'Архив',
      baseUrl: Uri.parse('https://two.example/vault/'),
      username: 'two',
      password: 'b',
    );

    await store.saveProfile(first);
    await store.saveProfile(second);
    await store.setActiveProfile(second.id);
    expect(await store.readProfiles(), hasLength(2));
    expect((await store.readWebDav())?.baseUrl.host, 'two.example');

    await store.deleteProfile(first.id);
    expect((await store.readProfiles()).single.id, second.id);
  });
}
