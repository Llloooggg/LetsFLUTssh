/// Real-DB integration tests for the production [SshKeysMutator] and
/// the [sshKeysStreamProvider] data flow.
///
/// The unit layer (`test/providers/key_provider_test.dart`) mocks the
/// stream with `Stream.value(seed)` — its own header notes the
/// persistence-asserting tests "move to integration_test", which is
/// this file. The real FRB path was otherwise untested: the
/// `db_ssh_keys_*` writes (upsert / replace-all / delete /
/// import-for-merge), the metadata + certificate listing read in
/// `loadAllMetadata`, the credential-stripping + createdAt-desc sort in
/// `_loadKeys`, and the `BusEvent::KeysChanged` round-trip that
/// re-flows the stream. These boot an unlocked in-memory DB, drive the
/// REAL mutator, and assert the REAL list the stream re-emits.
///
/// Key material can be synthetic: Rust computes the metadata
/// fingerprints as `normalized_sha256_hex` over the stored key TEXT
/// (`lfs_core::db::ssh_keys::list_metadata`), and `import_key_for_merge`
/// dedups on the same text fingerprint — neither parses real SSH key
/// bytes. So distinct/identical `publicKey` strings drive the
/// insert-vs-dedup branches deterministically.
///
/// Cadence note: each mutation is followed by a `waitForKeys` before
/// the next, so the stream consumes each `KeysChanged` tick while the
/// `_loadKeys` body is idle. Firing two writes back-to-back can race
/// the broadcast bus (the second tick arrives mid-`_loadKeys` and the
/// `await for` drops it until the next event) — a one-action-at-a-time
/// cadence mirrors real usage and keeps the assertions deterministic.
///
/// Tagged `frb_global_store` for the same reason as
/// `session_workspace_db_test`: they wipe and assert the exact contents
/// of the process-global DB, so they run in their own `flutter test`
/// process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  // Each test starts from an empty key store — the DB is process-global,
  // so a leftover row would skew the exact-list assertions.
  setUp(() async {
    await rust_db.dbSshKeysReplaceAll(rows: const []);
  });

  SshKeyEntry makeEntry({
    required String id,
    String label = 'Key',
    String privateKey = 'PRIVATE-PEM',
    String publicKey = 'ssh-ed25519 AAAAPUB',
    String keyType = 'ssh-ed25519',
    DateTime? createdAt,
    bool isGenerated = false,
  }) {
    return SshKeyEntry(
      id: id,
      label: label,
      privateKey: privateKey,
      publicKey: publicKey,
      keyType: keyType,
      createdAt: createdAt ?? DateTime(2025, 1, 1),
      isGenerated: isGenerated,
    );
  }

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen<AsyncValue<List<SshKeyEntry>>>(
      sshKeysStreamProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return c;
  }

  /// Wait until the SSH-keys stream emits a list satisfying [predicate],
  /// or time out. Robust to the write→tick gap.
  Future<List<SshKeyEntry>> waitForKeys(
    ProviderContainer c,
    bool Function(List<SshKeyEntry>) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final completer = Completer<List<SshKeyEntry>>();
    final sub = c.listen<AsyncValue<List<SshKeyEntry>>>(sshKeysStreamProvider, (
      _,
      next,
    ) {
      if (!next.hasValue || completer.isCompleted) return;
      final value = next.value as List<SshKeyEntry>;
      if (predicate(value)) completer.complete(value);
    }, fireImmediately: true);
    return completer.future.timeout(timeout).whenComplete(sub.close);
  }

  group('SshKeysMutator writes against a real DB', () {
    test('save inserts a key the stream re-emits with PEM stripped', () async {
      final c = makeContainer();
      await c
          .read(sshKeysMutatorProvider)
          .save(
            makeEntry(
              id: 'k1',
              label: 'Laptop',
              privateKey: 'TOP-SECRET-PEM',
              publicKey: 'ssh-ed25519 AAAAK1',
            ),
          );
      final keys = await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));
      final k = keys.firstWhere((e) => e.id == 'k1');
      expect(k.label, 'Laptop');
      expect(k.publicKey, 'ssh-ed25519 AAAAK1');
      // The stream view never carries the private PEM bytes.
      expect(k.privateKey, isEmpty);
    });

    test('save on the same id updates the entry', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(makeEntry(id: 'k1', label: 'Old'));
      await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));
      await mutator.save(makeEntry(id: 'k1', label: 'New'));
      final keys = await waitForKeys(
        c,
        (l) => l.any((e) => e.id == 'k1' && e.label == 'New'),
      );
      expect(keys.where((e) => e.id == 'k1'), hasLength(1));
    });

    test('saveAll replaces the entire store', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(makeEntry(id: 'k1', publicKey: 'ssh-ed25519 A1'));
      await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));
      await mutator.save(makeEntry(id: 'k2', publicKey: 'ssh-ed25519 A2'));
      await waitForKeys(c, (l) => l.length == 2);
      await mutator.saveAll({
        'k3': makeEntry(id: 'k3', publicKey: 'ssh-ed25519 A3'),
      });
      final keys = await waitForKeys(
        c,
        (l) => l.length == 1 && l.single.id == 'k3',
      );
      expect(keys.single.id, 'k3');
    });

    test('delete removes one key, leaving the rest', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(makeEntry(id: 'k1', publicKey: 'ssh-ed25519 A1'));
      await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));
      await mutator.save(makeEntry(id: 'k2', publicKey: 'ssh-ed25519 A2'));
      await waitForKeys(c, (l) => l.length == 2);
      await mutator.delete('k1');
      final keys = await waitForKeys(
        c,
        (l) => l.length == 1 && l.single.id == 'k2',
      );
      expect(keys.single.id, 'k2');
    });

    test('stream sorts keys by createdAt descending', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(
        makeEntry(
          id: 'older',
          publicKey: 'ssh-ed25519 OLD',
          createdAt: DateTime(2023, 6, 1),
        ),
      );
      await waitForKeys(c, (l) => l.any((e) => e.id == 'older'));
      await mutator.save(
        makeEntry(
          id: 'newer',
          publicKey: 'ssh-ed25519 NEW',
          createdAt: DateTime(2025, 6, 1),
        ),
      );
      final keys = await waitForKeys(c, (l) => l.length == 2);
      expect(keys.map((e) => e.id).toList(), ['newer', 'older']);
    });
  });

  group('SshKeysMutator.loadAllMetadata against a real DB', () {
    test('returns fingerprints and the isGenerated flag per id', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(
        makeEntry(id: 'gen', publicKey: 'ssh-ed25519 GEN', isGenerated: true),
      );
      await waitForKeys(c, (l) => l.any((e) => e.id == 'gen'));
      await mutator.save(
        makeEntry(id: 'imp', publicKey: 'ssh-ed25519 IMP', isGenerated: false),
      );
      await waitForKeys(c, (l) => l.length == 2);

      final meta = await mutator.loadAllMetadata();
      expect(meta.keys, containsAll(['gen', 'imp']));
      expect(meta['gen']!.isGenerated, isTrue);
      expect(meta['imp']!.isGenerated, isFalse);
      // Fingerprints are derived Rust-side from the stored key text.
      expect(meta['gen']!.publicFingerprint, isNotEmpty);
      expect(meta['gen']!.privateFingerprint, isNotEmpty);
      // No cert attached → no validity, empty principals.
      expect(meta['gen']!.validity, isNull);
      expect(meta['gen']!.principals, isEmpty);
    });

    test(
      'identical public-key text yields identical public fingerprint',
      () async {
        final c = makeContainer();
        final mutator = c.read(sshKeysMutatorProvider);
        await mutator.save(makeEntry(id: 'a', publicKey: 'ssh-ed25519 SAME'));
        await waitForKeys(c, (l) => l.any((e) => e.id == 'a'));
        await mutator.save(makeEntry(id: 'b', publicKey: 'ssh-ed25519 SAME'));
        await waitForKeys(c, (l) => l.length == 2);

        final meta = await mutator.loadAllMetadata();
        expect(meta['a']!.publicFingerprint, meta['b']!.publicFingerprint);
      },
    );
  });

  group('SshKeysMutator.importForMerge against a real DB', () {
    test('dedups by public fingerprint, returning the existing id', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(
        makeEntry(id: 'stored', publicKey: 'ssh-ed25519 DEDUP'),
      );
      await waitForKeys(c, (l) => l.any((e) => e.id == 'stored'));

      // Same public-key text, different proposed id → no new row.
      final resultId = await mutator.importForMerge(
        makeEntry(id: 'proposed', publicKey: 'ssh-ed25519 DEDUP'),
      );
      expect(resultId, 'stored');
      final meta = await mutator.loadAllMetadata();
      expect(meta.keys, ['stored']);
    });

    test('keeps the proposed id when it does not collide', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(makeEntry(id: 'k1', publicKey: 'ssh-ed25519 ONE'));
      await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));

      // New material, non-colliding id → inserted under the proposed id.
      final resultId = await mutator.importForMerge(
        makeEntry(id: 'fresh', publicKey: 'ssh-ed25519 TWO'),
      );
      expect(resultId, 'fresh');
      final keys = await waitForKeys(c, (l) => l.length == 2);
      expect(keys.map((e) => e.id), containsAll(['k1', 'fresh']));
    });

    test('mints a new id when the proposed id collides', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(makeEntry(id: 'dup', publicKey: 'ssh-ed25519 ONE'));
      await waitForKeys(c, (l) => l.any((e) => e.id == 'dup'));

      // Distinct material but the proposed id reuses the stored 'dup'
      // id → import must mint a fresh id so it can't clobber the row.
      final resultId = await mutator.importForMerge(
        makeEntry(id: 'dup', publicKey: 'ssh-ed25519 TWO'),
      );
      expect(resultId, isNot('dup'));
      final keys = await waitForKeys(c, (l) => l.length == 2);
      expect(keys.map((e) => e.id), containsAll(['dup', resultId]));
    });

    test('appends a copy suffix when the label collides', () async {
      final c = makeContainer();
      final mutator = c.read(sshKeysMutatorProvider);
      await mutator.save(
        makeEntry(id: 'k1', label: 'Shared', publicKey: 'ssh-ed25519 ONE'),
      );
      await waitForKeys(c, (l) => l.any((e) => e.id == 'k1'));

      final resultId = await mutator.importForMerge(
        makeEntry(id: 'p', label: 'Shared', publicKey: 'ssh-ed25519 TWO'),
      );
      final meta = await mutator.loadAllMetadata();
      // Insert happened (distinct material) and the colliding label was
      // disambiguated rather than duplicated verbatim.
      expect(meta[resultId]!.label, isNot('Shared'));
      expect(meta[resultId]!.label, contains('Shared'));
    });
  });
}
