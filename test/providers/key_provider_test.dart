import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/providers/key_provider.dart';

// `sshKeysStreamProvider` reads through FRB (`lfs_core.db`).
// flutter_test does not load the native bridge, so the
// persistence-asserting tests that round-tripped through the
// in-memory DB no longer apply — equivalent coverage moves to
// integration_test. The remaining tests pin the stream + sync
// derive shape using the standard fake-stream override pattern.

void main() {
  group('sshKeysStreamProvider', () {
    test('yields the seeded list and the sync derive surfaces it', () async {
      final seed = <SshKeyEntry>[
        SshKeyEntry(
          id: 'k1',
          label: 'Laptop key',
          privateKey: '',
          publicKey: 'ssh-ed25519 AAAA',
          keyType: 'ssh-ed25519',
          createdAt: DateTime(2025, 1, 1),
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          sshKeysStreamProvider.overrideWith((_) => Stream.value(seed)),
        ],
      );
      addTearDown(container.dispose);

      // Pin the listener so Riverpod retains the stream subscription
      // through the `.future` await — the lone `.future` getter
      // alone doesn't anchor the subscription and the tear-down
      // would race against the first emission.
      container.listen<AsyncValue<List<SshKeyEntry>>>(
        sshKeysStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final emitted = await container.read(sshKeysStreamProvider.future);
      expect(emitted, hasLength(1));
      expect(emitted.first.label, 'Laptop key');

      // Sync derive surfaces the same list once the stream emits.
      expect(container.read(sshKeysProvider), hasLength(1));
    });

    test(
      'sshKeysProvider sync derive returns empty when stream is loading',
      () {
        // Override with a never-emitting stream — the derived
        // Provider falls back to `const []` until the first
        // emission lands, keeping widget consumers from seeing a
        // null on the first frame.
        final container = ProviderContainer(
          overrides: [
            sshKeysStreamProvider.overrideWith(
              (_) => const Stream<List<SshKeyEntry>>.empty(),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(sshKeysProvider), isEmpty);
      },
    );
  });
}
