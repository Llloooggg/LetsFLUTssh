import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/providers/key_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('key_prov_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
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
      final keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);
    });

    test('returns keys sorted by createdAt descending', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider);

      // Add two keys with different creation dates
      final olderKey = SshKeyEntry(
        id: 'older',
        label: 'Old Key',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nold\n-----END OPENSSH PRIVATE KEY-----',
        publicKey: 'ssh-ed25519 AAAA old',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2024, 1, 1),
      );
      final newerKey = SshKeyEntry(
        id: 'newer',
        label: 'New Key',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nnew\n-----END OPENSSH PRIVATE KEY-----',
        publicKey: 'ssh-ed25519 AAAA new',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025, 1, 1),
      );

      await store.save(olderKey);
      await store.save(newerKey);

      // Invalidate provider to reload
      container.invalidate(sshKeysProvider);
      final keys = await container.read(sshKeysProvider.future);

      expect(keys, hasLength(2));
      // Newer key should come first (descending sort)
      expect(keys[0].id, 'newer');
      expect(keys[1].id, 'older');
    });

    test('reloads after invalidation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider);

      // Initial read
      var keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);

      // Add a key
      await store.save(
        SshKeyEntry(
          id: 'test',
          label: 'Test Key',
          privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
          publicKey: 'ssh-ed25519 AAAA test',
          keyType: 'ssh-ed25519',
          createdAt: DateTime.now(),
        ),
      );

      // Should still be empty (cached)
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
