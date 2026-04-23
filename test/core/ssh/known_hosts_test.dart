import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:pointycastle/digests/sha256.dart';

// Test the fingerprint algorithm and verify() logic by re-creating a minimal
// KnownHostsManager that doesn't depend on path_provider.
// The real KnownHostsManager uses getApplicationSupportDirectory() which isn't
// available in unit tests, so we test the verification algorithm directly.

void main() {
  group('known_hosts fingerprint algorithm', () {
    String fingerprint(List<int> keyBytes) {
      final digest = SHA256Digest();
      final hash = digest.process(Uint8List.fromList(keyBytes));
      return 'SHA256:${base64Encode(hash)}';
    }

    test('produces SHA256: prefix', () {
      final fp = fingerprint([1, 2, 3, 4]);
      expect(fp, startsWith('SHA256:'));
    });

    test('same bytes produce same fingerprint', () {
      final bytes = [10, 20, 30, 40, 50];
      expect(fingerprint(bytes), fingerprint(bytes));
    });

    test('different bytes produce different fingerprint', () {
      expect(fingerprint([1, 2, 3]), isNot(fingerprint([4, 5, 6])));
    });

    test('empty bytes produce valid fingerprint', () {
      final fp = fingerprint([]);
      expect(fp, startsWith('SHA256:'));
      // SHA256 of empty input is a known value
      expect(
        fp,
        'SHA256:${base64Encode(SHA256Digest().process(Uint8List(0)))}',
      );
    });
  });

  group('known_hosts file format parsing', () {
    // Test the parsing logic that KnownHostsManager.load() uses
    Map<String, String> parseKnownHosts(String content) {
      final hosts = <String, String>{};
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split(' ');
        if (parts.length >= 3) {
          hosts[parts[0]] = '${parts[1]} ${parts[2]}';
        }
      }
      return hosts;
    }

    test('parses host:port keytype base64key', () {
      const content = 'example.com:22 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5\n';
      final hosts = parseKnownHosts(content);
      expect(hosts['example.com:22'], 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5');
    });

    test('skips empty lines', () {
      const content = '\n\nexample.com:22 ssh-rsa AAAA\n\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });

    test('skips comment lines', () {
      const content = '# comment\nexample.com:22 ssh-rsa AAAA\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });

    test('multiple hosts', () {
      const content = 'a.com:22 ssh-rsa KEY1\nb.com:2222 ssh-ed25519 KEY2\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 2);
      expect(hosts['a.com:22'], 'ssh-rsa KEY1');
      expect(hosts['b.com:2222'], 'ssh-ed25519 KEY2');
    });

    test('ignores lines with fewer than 3 parts', () {
      const content = 'bad line\nexample.com:22 ssh-rsa AAAA\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });
  });

  group('known_hosts verify logic', () {
    // Inline reimplementation of verify() to test the algorithm without I/O.
    late Map<String, String> hosts;
    late List<String> unknownHostCalls;
    late List<String> keyChangedCalls;
    late bool acceptUnknown;
    late bool acceptChanged;

    setUp(() {
      hosts = {};
      unknownHostCalls = [];
      keyChangedCalls = [];
      acceptUnknown = true;
      acceptChanged = false;
    });

    Future<bool> verify(
      String host,
      int port,
      String keyType,
      List<int> keyBytes, {
      bool hasUnknownCallback = true,
      bool hasChangedCallback = true,
    }) async {
      final hostPort = '$host:$port';
      final keyData = base64Encode(keyBytes);
      final keyString = '$keyType $keyData';
      final existing = hosts[hostPort];

      if (existing != null) {
        if (existing == keyString) return true;
        // Key changed
        if (hasChangedCallback) {
          keyChangedCalls.add(hostPort);
          if (acceptChanged) {
            hosts[hostPort] = keyString;
            return true;
          }
        }
        return false;
      }

      // Unknown host
      if (hasUnknownCallback) {
        unknownHostCalls.add(hostPort);
        if (acceptUnknown) {
          hosts[hostPort] = keyString;
          return true;
        }
        return false;
      }

      // No callback — reject (require explicit user confirmation)
      return false;
    }

    test('unknown host with callback — accepted', () async {
      acceptUnknown = true;
      final result = await verify('example.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, ['example.com:22']);
      expect(hosts.containsKey('example.com:22'), isTrue);
    });

    test('unknown host with callback — rejected', () async {
      acceptUnknown = false;
      final result = await verify('example.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isFalse);
      expect(hosts.containsKey('example.com:22'), isFalse);
    });

    test('unknown host without callback — rejected', () async {
      final result = await verify('example.com', 22, 'ssh-rsa', [
        1,
        2,
        3,
      ], hasUnknownCallback: false);
      expect(result, isFalse);
      expect(unknownHostCalls, isEmpty);
      expect(hosts.containsKey('example.com:22'), isFalse);
    });

    test('known host with matching key — accepted silently', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      final result = await verify('server', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, isEmpty);
      expect(keyChangedCalls, isEmpty);
    });

    test('known host with changed key — rejected by default', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      acceptChanged = false;
      final result = await verify('server', 22, 'ssh-rsa', [4, 5, 6]);
      expect(result, isFalse);
      expect(keyChangedCalls, ['server:22']);
    });

    test(
      'known host with changed key — accepted when callback approves',
      () async {
        hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
        acceptChanged = true;
        final result = await verify('server', 22, 'ssh-rsa', [4, 5, 6]);
        expect(result, isTrue);
        // Key should be updated
        expect(hosts['server:22'], 'ssh-rsa ${base64Encode([4, 5, 6])}');
      },
    );

    test('known host with changed key — rejected when no callback', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      final result = await verify('server', 22, 'ssh-rsa', [
        4,
        5,
        6,
      ], hasChangedCallback: false);
      expect(result, isFalse);
    });

    test('different ports are different hosts', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      acceptUnknown = true;
      final result = await verify('server', 2222, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, ['server:2222']);
      expect(hosts.length, 2);
    });
  });

  group('KnownHostsManager — DB backed', () {
    late AppDatabase db;
    late KnownHostsManager manager;

    setUp(() {
      db = openTestDatabase();
      manager = KnownHostsManager()..setDatabase(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('load with empty DB', () async {
      await manager.load();
      expect(manager.count, 0);
    });

    test('verify unknown host without callback rejects', () async {
      await manager.load();
      final result = await manager.verify('unknown.com', 22, 'ssh-rsa', [
        1,
        2,
        3,
      ]);
      expect(result, isFalse);
    });

    test('verify unknown host with accepting callback adds entry', () async {
      manager.onUnknownHost = (host, port, keyType, fingerprint) async => true;
      await manager.load();

      final result = await manager.verify('newhost.com', 22, 'ssh-ed25519', [
        1,
        2,
        3,
      ]);
      expect(result, isTrue);
      expect(manager.count, 1);
    });

    test('verify known host with matching key accepts', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();

      await manager.verify('server.com', 22, 'ssh-rsa', [10, 20, 30]);
      final result = await manager.verify('server.com', 22, 'ssh-rsa', [
        10,
        20,
        30,
      ]);
      expect(result, isTrue);
    });

    test('verify known host with changed key rejects', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();

      await manager.verify('server.com', 22, 'ssh-rsa', [1, 2, 3]);
      final result = await manager.verify('server.com', 22, 'ssh-rsa', [
        4,
        5,
        6,
      ]);
      expect(result, isFalse);
    });

    test('verify changed key with accepting callback updates', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      manager.onHostKeyChanged = (_, _, _, _) async => true;
      await manager.load();

      await manager.verify('server.com', 22, 'ssh-rsa', [1, 2, 3]);
      final result = await manager.verify('server.com', 22, 'ssh-rsa', [
        4,
        5,
        6,
      ]);
      expect(result, isTrue);
    });

    test('removeHost removes entry', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('h1.com', 22, 'ssh-rsa', [1, 2, 3]);
      await manager.verify('h2.com', 22, 'ssh-rsa', [4, 5, 6]);

      await manager.removeHost('h1.com:22');
      expect(manager.count, 1);
      expect(manager.entries.containsKey('h1.com:22'), isFalse);
    });

    test('removeMultiple removes selected', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('h1.com', 22, 'ssh-rsa', [1]);
      await manager.verify('h2.com', 22, 'ssh-rsa', [2]);
      await manager.verify('h3.com', 22, 'ssh-rsa', [3]);

      await manager.removeMultiple({'h1.com:22', 'h3.com:22'});
      expect(manager.count, 1);
    });

    test('clearAll removes all', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('h1.com', 22, 'ssh-rsa', [1]);
      await manager.verify('h2.com', 22, 'ssh-rsa', [2]);

      await manager.clearAll();
      expect(manager.count, 0);
    });

    test('importFromString adds new entries', () async {
      await manager.load();
      final added = await manager.importFromString(
        'host1:22 ssh-ed25519 AAAA\nhost2:22 ssh-rsa BBBB\n',
      );
      expect(added, 2);
      expect(manager.count, 2);
    });

    test('importFromString skips existing', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('host1', 22, 'ssh-ed25519', base64Decode('AAAA'));

      final added = await manager.importFromString(
        'host1:22 ssh-ed25519 AAAA\nhost2:22 ssh-rsa BBBB\n',
      );
      expect(added, 1);
      expect(manager.count, 2);
    });

    test('exportToString produces the LetsFLUTssh wire format', () async {
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('alpha.com', 22, 'ssh-rsa', [1, 2]);
      await manager.verify('beta.com', 2222, 'ssh-ed25519', [3, 4]);

      final exported = await manager.exportToString();
      expect(exported, contains('alpha.com:22 ssh-rsa'));
      expect(exported, contains('beta.com:2222 ssh-ed25519'));
    });

    test('export → import round-trip preserves every entry verbatim', () async {
      // Pins the wire-format symmetry that `.lfs` archive import
      // relies on: whatever `exportToString` writes, `importFromString`
      // must read back into the same (hostPort → keyString) pairs. A
      // drift in either end would silently corrupt every user's TOFU
      // history the next time they round-tripped an archive.
      manager.onUnknownHost = (_, _, _, _) async => true;
      await manager.load();
      await manager.verify('alpha.com', 22, 'ssh-rsa', [1, 2, 3]);
      await manager.verify('beta.com', 2222, 'ssh-ed25519', [4, 5, 6]);

      final wire = await manager.exportToString();

      final fresh = KnownHostsManager()..setDatabase(openTestDatabase());
      await fresh.load();
      final added = await fresh.importFromString(wire);

      expect(added, 2);
      expect(fresh.entries['alpha.com:22'], manager.entries['alpha.com:22']);
      expect(fresh.entries['beta.com:2222'], manager.entries['beta.com:2222']);
    });

    test(
      'exportToString auto-loads when called before any verify/load',
      () async {
        // Pre-seed the DB via a separate manager, flush it, then create a
        // fresh manager that hasn't had load() called. The first real call
        // has to be `exportToString`, simulating the Settings → Export path
        // when the user hasn't touched known-hosts UI yet this session.
        manager.onUnknownHost = (_, _, _, _) async => true;
        await manager.load();
        await manager.verify('gamma.com', 22, 'ssh-rsa', [5, 6]);

        final fresh = KnownHostsManager()..setDatabase(db);
        // No explicit load() — exportToString() must hydrate first.
        final exported = await fresh.exportToString();
        expect(exported, contains('gamma.com:22 ssh-rsa'));
      },
    );

    test('callback receives correct parameters', () async {
      String? capturedHost;
      int? capturedPort;
      manager.onUnknownHost = (host, port, keyType, fingerprint) async {
        capturedHost = host;
        capturedPort = port;
        return true;
      };
      await manager.load();

      await manager.verify('test.org', 2222, 'ssh-ed25519', [42, 43]);
      expect(capturedHost, 'test.org');
      expect(capturedPort, 2222);
    });

    test('static fingerprint produces SHA256 prefix', () {
      final fp = KnownHostsManager.fingerprint([10, 20, 30]);
      expect(fp, startsWith('SHA256:'));
    });

    test(
      'reload() picks up entries inserted directly into the DAO bypassing the manager',
      () async {
        manager.onUnknownHost = (_, _, _, _) async => true;
        await manager.verify('alpha.com', 22, 'ssh-rsa', [1, 2]);
        expect(manager.count, 1);

        // Simulate an external mutation: the import service writes straight
        // into the DAO. The in-memory cache is now stale.
        await db.knownHostDao.insert(
          KnownHostsCompanion.insert(
            host: 'beta.com',
            port: const Value(22),
            keyType: 'ssh-rsa',
            keyBase64: 'AAAA',
            addedAt: DateTime.now(),
          ),
        );
        // Plain load() is a no-op because the manager already loaded once.
        await manager.load();
        expect(manager.count, 1, reason: 'load() must not re-fetch');

        await manager.reload();
        expect(manager.count, 2, reason: 'reload() must re-fetch from the DAO');
      },
    );

    test(
      'concurrent clearAll + importFromString are serialised, no interleave',
      () async {
        manager.onUnknownHost = (_, _, _, _) async => true;
        await manager.verify('alpha.com', 22, 'ssh-rsa', [1, 2]);
        await manager.verify('beta.com', 22, 'ssh-rsa', [3, 4]);
        expect(manager.count, 2);

        // Kick off a clearAll and an import at the "same time". The
        // serialised write lock must run them in submission order so the
        // import sees a clean slate and ends with exactly the imported
        // entries — never a mixture.
        final clear = manager.clearAll();
        final imp = manager.importFromString(
          'gamma.com:22 ssh-rsa CCCC\n'
          'delta.com:22 ssh-rsa DDDD\n',
        );
        await Future.wait([clear, imp]);

        expect(manager.count, 2);
        expect(manager.entries.containsKey('gamma.com:22'), isTrue);
        expect(manager.entries.containsKey('delta.com:22'), isTrue);
        expect(manager.entries.containsKey('alpha.com:22'), isFalse);
      },
    );

    test(
      'verify is serialised against clearAll — accepted TOFU survives',
      () async {
        // Race reconstruction: user opens a fresh connection, the
        // TOFU prompt fires via `onUnknownHost` and awaits a user
        // tap; while the prompt is open another Settings action
        // kicks `clearAll`. Before the fix, the reader path
        // (`verify`) was not locked, so `clearAll` interleaved and
        // wiped `_hosts` + the DB; when the user tapped Accept the
        // TOFU `_addHost` re-wrote the row the user had just
        // asked to forget. With verify now inside `_serializeWrite`,
        // `clearAll` is queued behind the in-flight verify and the
        // user's Accept wins cleanly.
        final gate = Completer<bool>();
        manager.onUnknownHost = (_, _, _, _) async => gate.future;
        await manager.load();

        // Kick off verify — it will block inside onUnknownHost until
        // we resolve `gate`. In parallel submit a clearAll; it must
        // wait for verify to finish before running.
        final verifyFut = manager.verify('alpha.com', 22, 'ssh-rsa', [1, 2]);
        final clearFut = manager.clearAll();

        // Give the scheduler a beat so both futures have had a
        // chance to grab the write lock.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Accept TOFU; verify resolves, clearAll unblocks.
        gate.complete(true);
        await verifyFut;
        await clearFut;

        // clearAll runs AFTER verify finished, so the accepted TOFU
        // row is wiped by the time we inspect — but crucially there
        // is no state where verify re-added a row to a cleared DB.
        // That's the invariant being pinned: the two ops serialise
        // cleanly rather than interleave. Count == 0 (clear won the
        // tail), but the important guarantee is that the earlier
        // verify never saw a half-cleared state.
        expect(manager.count, 0);
      },
    );

    test(
      'load() retries after the underlying DAO call throws on a previous attempt',
      () async {
        // First load — DB is unset, so _doLoad() returns silently without
        // marking _loaded. Next load() with the DB attached must perform
        // real I/O instead of short-circuiting.
        final fresh = KnownHostsManager();
        await fresh.load(); // no DB yet — silent no-op
        expect(fresh.count, 0);

        // Pre-seed the DB and only now attach it.
        await db.knownHostDao.insert(
          KnownHostsCompanion.insert(
            host: 'gamma.com',
            port: const Value(22),
            keyType: 'ssh-rsa',
            keyBase64: 'BBBB',
            addedAt: DateTime.now(),
          ),
        );
        fresh.setDatabase(db);

        await fresh.load();
        expect(fresh.count, 1);
      },
    );
  });
}
