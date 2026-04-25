import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/providers/key_provider.dart';

// Phase 4.2 stage 6: KeyStore now reads/writes through FRB
// (`lfs_core.db`). flutter_test does not load the native bridge, so
// the persistence-asserting tests that round-tripped through drift's
// in-memory DB no longer apply — equivalent coverage moves to
// integration_test.

void main() {
  group('keyStoreProvider', () {
    test('returns KeyStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(keyStoreProvider);
      expect(store, isA<KeyStore>());
    });
  });

  group('sshKeysProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);
    });
  });
}
