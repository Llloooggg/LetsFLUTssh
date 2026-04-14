import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/providers/key_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('keyStoreProvider', () {
    test('returns KeyStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider);
      expect(store, isA<KeyStore>());
    });
  });

  group('sshKeysProvider', () {
    test('returns empty list when no keys stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(keyStoreProvider).setDatabase(db);
      final keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);
    });

    test('returns keys sorted by createdAt descending', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider)..setDatabase(db);

      final olderKey = SshKeyEntry(
        id: 'older',
        label: 'Old Key',
        privateKey: 'pk-old',
        publicKey: 'ssh-ed25519 AAAA old',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2024, 1, 1),
      );
      final newerKey = SshKeyEntry(
        id: 'newer',
        label: 'New Key',
        privateKey: 'pk-new',
        publicKey: 'ssh-ed25519 AAAA new',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025, 1, 1),
      );

      await store.save(olderKey);
      await store.save(newerKey);

      container.invalidate(sshKeysProvider);
      final keys = await container.read(sshKeysProvider.future);

      expect(keys, hasLength(2));
      expect(keys[0].id, 'newer');
      expect(keys[1].id, 'older');
    });

    test('reloads after invalidation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider)..setDatabase(db);

      var keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);

      await store.save(
        SshKeyEntry(
          id: 'test',
          label: 'Test Key',
          privateKey: 'pk-test',
          publicKey: 'ssh-ed25519 AAAA test',
          keyType: 'ssh-ed25519',
          createdAt: DateTime.now(),
        ),
      );

      // Still cached
      keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);

      // Invalidate and reload
      container.invalidate(sshKeysProvider);
      keys = await container.read(sshKeysProvider.future);
      expect(keys, hasLength(1));
      expect(keys[0].label, 'Test Key');
    });
  });
}
