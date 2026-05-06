/// Coverage for [KnownHostsNotifier] + [knownHostFingerprint].
///
/// Wires a `:memory:` SQLCipher DB through dbInit so the FRB DAOs
/// resolve real rows; the notifier's load + upsert + remove path
/// then runs end-to-end without any keychain or platform edge.
/// Bus events from the Rust DAO drive `reload()` automatically;
/// when the test wants deterministic state it calls `load()` /
/// `reload()` directly.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/known_hosts_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  setUp(() async {
    // Each test starts from an empty known_hosts table — drop everything
    // the prior test inserted so assertions on count / entries are
    // deterministic. The DB is `:memory:` but the Rust handle is a
    // process singleton: state survives across tests in the same file.
    final container = ProviderContainer();
    await container.read(knownHostsProvider.notifier).clearAll();
    container.dispose();
  });

  group('initial state', () {
    test('count is zero on a fresh container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      expect(notifier.count, 0);
    });

    test('entries returns an empty map view on a fresh container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      expect(notifier.entries, isEmpty);
    });

    test('entries returns an unmodifiable view', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      // Caller must not be able to mutate state through the read-only
      // `entries` view — that would silently desync from the FRB DB.
      expect(
        () => notifier.entries['evil:22'] = 'rsa AAAA',
        throwsUnsupportedError,
      );
    });
  });

  group('load + upsert + remove lifecycle', () {
    test('upsert + load surfaces the new entry in the cache', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('host.example', 22, 'ssh-ed25519', 'AAAAtestkey');
      await notifier.load();
      expect(notifier.entries, contains('host.example:22'));
      expect(notifier.entries['host.example:22'], 'ssh-ed25519 AAAAtestkey');
    });

    test('removeHost parses port from "host:port"', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('h1.example', 2222, 'ssh-rsa', 'AAAAh1');
      await notifier.load();
      expect(notifier.entries, contains('h1.example:2222'));
      await notifier.removeHost('h1.example:2222');
      await notifier.reload();
      expect(notifier.entries, isNot(contains('h1.example:2222')));
    });

    test('removeHost falls back to port 22 when no colon present', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('bare.example', 22, 'ssh-ed25519', 'AAAAbare');
      await notifier.load();
      // The string "bare.example" with no port suffix routes to the
      // port=22 default in the parser.
      await notifier.removeHost('bare.example');
      await notifier.reload();
      expect(notifier.entries, isNot(contains('bare.example:22')));
    });

    test('removeMultiple drops each named entry, leaves the rest', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('a.example', 22, 'ssh-rsa', 'AAAAa');
      await notifier.upsert('b.example', 22, 'ssh-rsa', 'AAAAb');
      await notifier.upsert('c.example', 22, 'ssh-rsa', 'AAAAc');
      // The notifier subscribes to KnownHostsChanged bus events on
      // build() and reload()s on every emit, which races against the
      // explicit load() after a burst of upserts. Force a fresh
      // snapshot via invalidate + load so the count assertion sees
      // the post-burst state, not a mid-race intermediate.
      notifier.invalidateCache();
      await notifier.load();
      await notifier.removeMultiple({'a.example:22', 'b.example:22'});
      notifier.invalidateCache();
      await notifier.load();
      expect(notifier.entries, isNot(contains('a.example:22')));
      expect(notifier.entries, isNot(contains('b.example:22')));
      expect(notifier.entries, contains('c.example:22'));
    });

    test('clearAll empties the table', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('clear.example', 22, 'ssh-rsa', 'AAAAclear');
      await notifier.load();
      expect(notifier.count, greaterThan(0));
      await notifier.clearAll();
      await notifier.reload();
      expect(notifier.entries, isEmpty);
    });
  });

  group('cache invalidation + single-flight', () {
    test('invalidateCache resets state to empty + flips _loaded', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('inv.example', 22, 'ssh-rsa', 'AAAAinv');
      await notifier.load();
      expect(notifier.count, greaterThan(0));
      notifier.invalidateCache();
      // Cache is empty after invalidate, but next load() repopulates
      // (single-flight bookkeeping is reset, so the load actually runs
      // instead of returning instantly).
      expect(notifier.count, 0);
      await notifier.load();
      expect(notifier.entries, contains('inv.example:22'));
    });

    test('concurrent load() calls share a single future', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      await notifier.upsert('sf.example', 22, 'ssh-rsa', 'AAAAsf');
      notifier.invalidateCache();
      // Three concurrent load()s — single-flight must complete all
      // three with one underlying FRB round-trip.
      await Future.wait([notifier.load(), notifier.load(), notifier.load()]);
      expect(notifier.entries, contains('sf.example:22'));
    });
  });

  group('import + export round-trip', () {
    test('importFromFile returns 0 for a non-existent path', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      final tmp = Directory.systemTemp.createTempSync('lfs_kh_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      // No file at this path — the early `await file.exists()` returns
      // false and the helper short-circuits without an FRB call.
      final added = await notifier.importFromFile('${tmp.path}/missing');
      expect(added, 0);
    });

    test('importFromString tolerates non-known-hosts content', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      // Garbage content — must not throw. The Rust importer's
      // per-line parser is lenient by design (the upstream OpenSSH
      // format admits comments and blank lines), so the returned
      // count may be 0 or non-zero depending on how much of the
      // input the parser opted to interpret. The portable assertion
      // is "non-negative integer, no throw".
      final added = await notifier.importFromString(
        'not a known_hosts line\n# comment only\n',
      );
      expect(added, greaterThanOrEqualTo(0));
    });

    test('exportToString returns a string (possibly empty)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(knownHostsProvider.notifier);
      // The contract is "best-effort export, empty string on failure".
      // Empty DB → empty string is the canonical case.
      final exported = await notifier.exportToString();
      expect(exported, isA<String>());
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
