/// Real-DB integration tests for the production [KnownHostsMutator] and
/// the [knownHostsStreamProvider] data flow.
///
/// The unit layer (`test/providers/known_hosts_provider_test.dart`)
/// mocks the stream with `Stream.value(seed)` and exercises only the
/// pure helpers (`splitKnownHostKey`, `knownHostFingerprint`), so the
/// real FRB path was untested: the `db_known_hosts_*` writes
/// (upsert / delete / clear / import-from-string / import-from-path /
/// export), the `db_known_hosts_list_all` read in `_loadEntries`, and
/// the `BusEvent::KnownHostsChanged` round-trip that re-flows the
/// stream. These boot an unlocked in-memory DB, drive the REAL mutator,
/// and assert against the REAL map the stream re-emits after each
/// Rust-published bus tick.
///
/// Key-body discipline: the import parser
/// (`lfs_core::known_hosts_parser::parse_line`) rejects a line whose
/// key body is not valid standard base64, so every entry that has to
/// round-trip through import/export uses a valid-base64 key (length a
/// multiple of 4, base64 alphabet). `upsert` itself does NOT validate,
/// but the keys here stay valid base64 throughout to mirror real
/// host-key material.
///
/// Tagged `frb_global_store` for the same reason as
/// `session_workspace_db_test`: they wipe and assert the exact contents
/// of the process-global DB, so they run in their own `flutter test`
/// process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/known_hosts_provider.dart';
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

  // Each test starts from an empty table — the DB is process-global, so
  // a leftover row would skew the exact-map assertions.
  setUp(() async {
    await rust_db.dbKnownHostsClearAll();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen<AsyncValue<Map<String, String>>>(
      knownHostsStreamProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return c;
  }

  /// Wait until the known-hosts stream emits a map satisfying
  /// [predicate], or time out. Robust to the write→tick gap.
  Future<Map<String, String>> waitForMap(
    ProviderContainer c,
    bool Function(Map<String, String>) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final completer = Completer<Map<String, String>>();
    final sub = c.listen<AsyncValue<Map<String, String>>>(
      knownHostsStreamProvider,
      (_, next) {
        if (!next.hasValue || completer.isCompleted) return;
        final value = next.value as Map<String, String>;
        if (predicate(value)) completer.complete(value);
      },
      fireImmediately: true,
    );
    return completer.future.timeout(timeout).whenComplete(sub.close);
  }

  group('KnownHostsMutator writes against a real DB', () {
    test('upsert inserts an entry the stream re-emits', () async {
      final c = makeContainer();
      await c
          .read(knownHostsMutatorProvider)
          .upsert('10.0.0.1', 22, 'ssh-ed25519', 'AAAAKEYA');
      final map = await waitForMap(c, (m) => m.containsKey('10.0.0.1:22'));
      expect(map['10.0.0.1:22'], 'ssh-ed25519 AAAAKEYA');
    });

    test('upsert on the same host:port overwrites the key', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('host.example', 22, 'ssh-rsa', 'OLDKEYAA');
      await waitForMap(c, (m) => m['host.example:22'] == 'ssh-rsa OLDKEYAA');
      await mutator.upsert('host.example', 22, 'ssh-ed25519', 'NEWKEYAA');
      final map = await waitForMap(
        c,
        (m) => m['host.example:22'] == 'ssh-ed25519 NEWKEYAA',
      );
      expect(map.length, 1);
    });

    test('removeHost deletes a single entry by host:port key', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('keep.example', 22, 'ssh-rsa', 'KEEPKEYA');
      await mutator.upsert('drop.example', 22, 'ssh-rsa', 'DROPKEYA');
      await waitForMap(c, (m) => m.length == 2);
      await mutator.removeHost('drop.example:22');
      final map = await waitForMap(c, (m) => m.length == 1);
      expect(map.keys.single, 'keep.example:22');
    });

    test('removeHost splits an IPv6 key on its last colon', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      // The stream key for an IPv6 host on port 2222 is "::1:2222";
      // removeHost must split on the LAST colon so the host stays "::1".
      await mutator.upsert('::1', 2222, 'ssh-ed25519', 'VVVVKEYA');
      await waitForMap(c, (m) => m.containsKey('::1:2222'));
      await mutator.removeHost('::1:2222');
      final map = await waitForMap(c, (m) => m.isEmpty);
      expect(map, isEmpty);
    });

    test('removeMultiple deletes the named set', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('a.example', 22, 'ssh-rsa', 'AAAAKEYB');
      await mutator.upsert('b.example', 22, 'ssh-rsa', 'BBBBKEYB');
      await mutator.upsert('c.example', 22, 'ssh-rsa', 'CCCCKEYB');
      await waitForMap(c, (m) => m.length == 3);
      await mutator.removeMultiple({'a.example:22', 'c.example:22'});
      final map = await waitForMap(c, (m) => m.length == 1);
      expect(map.keys.single, 'b.example:22');
    });

    test('clearAll empties the table', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('x.example', 22, 'ssh-rsa', 'XXXXKEYA');
      await waitForMap(c, (m) => m.isNotEmpty);
      await mutator.clearAll();
      final map = await waitForMap(c, (m) => m.isEmpty);
      expect(map, isEmpty);
    });
  });

  group('KnownHostsMutator import/export against a real DB', () {
    test('export → clearAll → importFromString round-trips', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('one.example', 22, 'ssh-rsa', 'KEYA1234');
      await mutator.upsert('two.example', 2200, 'ssh-ed25519', 'KEYB5678');
      final seeded = await waitForMap(c, (m) => m.length == 2);

      final wire = await mutator.exportToString();
      expect(wire, isNotEmpty);

      await mutator.clearAll();
      await waitForMap(c, (m) => m.isEmpty);

      final added = await mutator.importFromString(wire);
      expect(added, 2);
      final reimported = await waitForMap(c, (m) => m.length == 2);
      expect(reimported, seeded);
    });

    test('importFromString skips hashed lines, counts only plain', () async {
      final c = makeContainer();
      // A `|1|salt|hash` hashed-hostname row cannot be reversed to a
      // host, so the importer skips it; only the plain row is added.
      const blob =
          '|1|abc=|def= ssh-rsa HASHEDKEY\n'
          'plain.example ssh-ed25519 PLAINKEY\n';
      final added = await c
          .read(knownHostsMutatorProvider)
          .importFromString(blob);
      expect(added, 1);
      final map = await waitForMap(c, (m) => m.containsKey('plain.example:22'));
      expect(map.length, 1);
      expect(map['plain.example:22'], 'ssh-ed25519 PLAINKEY');
    });

    test('importFromFile imports from a known_hosts file on disk', () async {
      final c = makeContainer();
      final mutator = c.read(knownHostsMutatorProvider);
      await mutator.upsert('seed.example', 22, 'ssh-rsa', 'SEEDKEYA');
      await waitForMap(c, (m) => m.isNotEmpty);
      final wire = await mutator.exportToString();
      await mutator.clearAll();
      await waitForMap(c, (m) => m.isEmpty);

      final dir = await Directory.systemTemp.createTemp('known_hosts_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/known_hosts');
      await file.writeAsString(wire);

      final added = await mutator.importFromFile(file.path);
      expect(added, 1);
      final map = await waitForMap(c, (m) => m.containsKey('seed.example:22'));
      expect(map['seed.example:22'], 'ssh-rsa SEEDKEYA');
    });

    test('importFromFile on a missing path adds nothing', () async {
      final c = makeContainer();
      await waitForMap(c, (_) => true);
      final added = await c
          .read(knownHostsMutatorProvider)
          .importFromFile('/nonexistent/path/known_hosts');
      expect(added, 0);
    });

    test('exportToString on an empty table yields an empty string', () async {
      final c = makeContainer();
      await waitForMap(c, (_) => true);
      expect(await c.read(knownHostsMutatorProvider).exportToString(), isEmpty);
    });
  });
}
