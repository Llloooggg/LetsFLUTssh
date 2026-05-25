/// Coverage for the [knownHostsStreamProvider] + [knownHostsProvider]
/// + [KnownHostsMutator] surface, plus the [knownHostFingerprint]
/// helper.
///
/// `knownHostsStreamProvider` reads through FRB (`lfs_core.db`).
/// flutter_test does not load the native bridge, so the
/// persistence-asserting tests that round-tripped through the
/// in-memory DB no longer apply — equivalent coverage moves to
/// integration_test. The remaining tests pin the stream + sync
/// derive shape using the standard fake-stream override pattern.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/known_hosts_provider.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  // `knownHostFingerprint` routes through `lfs_core::ssh` (FRB
  // sync). Bootstrap once for the whole file.
  setUpAll(requireFrbLoaded);

  group('knownHostsStreamProvider', () {
    test('yields the seeded map and the sync derive surfaces it', () async {
      const seed = <String, String>{
        'host.example:22': 'ssh-ed25519 AAAAtestkey',
      };
      final container = ProviderContainer(
        overrides: [
          knownHostsStreamProvider.overrideWith((_) => Stream.value(seed)),
        ],
      );
      addTearDown(container.dispose);

      // Pin the listener so Riverpod retains the stream subscription
      // through the `.future` await — the lone `.future` getter
      // alone doesn't anchor the subscription and the tear-down
      // would race against the first emission.
      container.listen<AsyncValue<Map<String, String>>>(
        knownHostsStreamProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final emitted = await container.read(knownHostsStreamProvider.future);
      expect(emitted, contains('host.example:22'));
      expect(emitted['host.example:22'], 'ssh-ed25519 AAAAtestkey');

      // Sync derive surfaces the same map once the stream emits.
      expect(container.read(knownHostsProvider), hasLength(1));
    });

    test(
      'knownHostsProvider sync derive returns empty when stream is loading',
      () {
        // Override with a never-emitting stream — the derived
        // Provider falls back to `const {}` until the first
        // emission lands, keeping widget consumers from seeing a
        // null on the first frame.
        final container = ProviderContainer(
          overrides: [
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(knownHostsProvider), isEmpty);
      },
    );
  });

  group('knownHostsMutatorProvider', () {
    test('exposes a const KnownHostsMutator singleton', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final a = container.read(knownHostsMutatorProvider);
      final b = container.read(knownHostsMutatorProvider);
      // The mutator is stateless; the provider returns the same
      // const-constructed value on every read.
      expect(identical(a, b), isTrue);
      expect(a, isA<KnownHostsMutator>());
    });
  });

  group('splitKnownHostKey', () {
    test('splits a plain host:port key', () {
      expect(splitKnownHostKey('example.com:22'), ('example.com', 22));
      expect(splitKnownHostKey('10.0.0.1:2222'), ('10.0.0.1', 2222));
    });

    test('keeps an IPv6 address intact by splitting on the last colon', () {
      // The bug: split(':')[0] returned '' for `::1:2222`, so the
      // delete never matched and IPv6 rows were un-removable.
      expect(splitKnownHostKey('::1:2222'), ('::1', 2222));
      expect(splitKnownHostKey('fe80::1ff:fe23:4567:890a:22'), (
        'fe80::1ff:fe23:4567:890a',
        22,
      ));
    });

    test('falls back to port 22 for a key without a numeric trailing port', () {
      expect(splitKnownHostKey('bare-host'), ('bare-host', 22));
    });
  });

  group('knownHostFingerprint', () {
    test('returns SHA256: prefix + base64-no-pad body', () {
      // Any byte sequence — the Rust helper hashes it with SHA-256
      // and base64-encodes (no padding). The shape is the OpenSSH
      // `ssh-keygen -lf` format.
      final fp = knownHostFingerprint(Uint8List.fromList(List.filled(32, 7)));
      expect(fp, startsWith('SHA256:'));
      expect(fp.endsWith('='), isFalse, reason: 'no base64 padding');
      // SHA-256 → 32 bytes → 43 base64-no-pad chars.
      expect(fp.length, 'SHA256:'.length + 43);
    });

    test('produces stable output across calls for the same input', () {
      final keyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(knownHostFingerprint(keyBytes), knownHostFingerprint(keyBytes));
    });

    test('different inputs produce different fingerprints', () {
      final a = knownHostFingerprint(Uint8List.fromList([1, 2, 3]));
      final b = knownHostFingerprint(Uint8List.fromList([1, 2, 4]));
      expect(a, isNot(equals(b)));
    });

    test('accepts a plain List<int> via Uint8List.fromList branch', () {
      // Production callers pass either a Uint8List (already-typed
      // bytes) or a generic List<int> from FRB / parser output. The
      // helper's `is Uint8List` check + fromList fallback covers both.
      final fp = knownHostFingerprint(<int>[10, 20, 30]);
      expect(fp, startsWith('SHA256:'));
    });
  });
}
