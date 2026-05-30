import 'dart:async';

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

    test(
      'sshKeysProvider sync derive returns empty on a stream error so the '
      'picker / manager surfaces an empty list instead of throwing',
      () async {
        // Spec: `sshKeysProvider` reads `async.hasValue` and falls
        // through to `const []` when the stream is in error
        // (`hasValue` is false on AsyncError). A regression that
        // forgot the guard would null-deref `async.value as List`
        // and crash every widget watching the listing.
        final container = ProviderContainer(
          overrides: [
            sshKeysStreamProvider.overrideWith(
              (_) => Stream<List<SshKeyEntry>>.error(StateError('db locked')),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen<AsyncValue<List<SshKeyEntry>>>(
          sshKeysStreamProvider,
          (_, _) {},
          fireImmediately: true,
        );
        // Yield once so the error event lands inside Riverpod.
        await Future<void>.delayed(Duration.zero);
        expect(container.read(sshKeysProvider), isEmpty);
      },
    );

    test('sshKeysStreamProvider re-emits every list the source stream pushes — '
        'the derive picks up the latest snapshot, not the first', () async {
      // Spec: `sshKeysProvider` is a thin derive over the AsyncValue
      // of `sshKeysStreamProvider`. On every new emission the derive
      // must surface the freshest list; consumers rely on this to
      // re-render after a `KeysChanged` bus event triggers a re-load.
      final first = <SshKeyEntry>[
        SshKeyEntry(
          id: 'k1',
          label: 'old',
          privateKey: '',
          publicKey: 'ssh-ed25519 AAAA',
          keyType: 'ssh-ed25519',
          createdAt: DateTime(2024),
        ),
      ];
      final second = <SshKeyEntry>[
        ...first,
        SshKeyEntry(
          id: 'k2',
          label: 'new',
          privateKey: '',
          publicKey: 'ssh-ed25519 BBBB',
          keyType: 'ssh-ed25519',
          createdAt: DateTime(2025),
        ),
      ];
      final controller = StreamController<List<SshKeyEntry>>.broadcast();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: [
          sshKeysStreamProvider.overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<List<SshKeyEntry>>>(
        sshKeysStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );

      controller.add(first);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sshKeysProvider), hasLength(1));

      controller.add(second);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sshKeysProvider), hasLength(2));
      expect(container.read(sshKeysProvider).map((e) => e.id), ['k1', 'k2']);
    });
  });

  group('SshKeysMutator construction', () {
    test(
      'sshKeysMutatorProvider returns a const mutator handle — every read '
      'sees the same identity so widget rebuilds do not churn the mutator',
      () {
        // Spec: `sshKeysMutatorProvider = Provider((ref) => const
        // SshKeysMutator())`. The stateless `const` constructor means
        // every container resolves to the same instance per-container,
        // and the mutator carries no Dart state — every method is a
        // pure pass-through to FRB. A regression that lifted the
        // mutator to a non-const construction (Riverpod
        // `NotifierProvider`, ChangeNotifier wrap) would re-introduce
        // exactly the Dart-cached state the architecture rule
        // forbids.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final a = container.read(sshKeysMutatorProvider);
        final b = container.read(sshKeysMutatorProvider);
        expect(identical(a, b), isTrue);
        expect(a, isA<SshKeysMutator>());
      },
    );
  });
}
