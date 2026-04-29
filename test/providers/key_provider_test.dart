import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/key_provider.dart';

// SshKeysNotifier reads/writes through FRB (`lfs_core.db`).
// flutter_test does not load the native bridge, so the persistence-
// asserting tests that round-tripped through drift's in-memory DB no
// longer apply — equivalent coverage moves to integration_test.

void main() {
  group('sshKeysProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final keys = await container.read(sshKeysProvider.future);
      expect(keys, isEmpty);
    });
  });
}
