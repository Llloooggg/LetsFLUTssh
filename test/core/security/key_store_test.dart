import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/key_store.dart';

void main() {
  group('SshKeyEntry', () {
    test('JSON roundtrip preserves all fields', () {
      final entry = SshKeyEntry(
        id: 'test-id',
        label: 'My Key',
        privateKey:
            '-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----',
        publicKey: 'ssh-ed25519 AAAA test',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025, 6, 15),
        isGenerated: true,
      );

      final json = entry.toJson();
      final restored = SshKeyEntry.fromJson(json);

      expect(restored.id, entry.id);
      expect(restored.label, entry.label);
      expect(restored.privateKey, entry.privateKey);
      expect(restored.publicKey, entry.publicKey);
      expect(restored.keyType, entry.keyType);
      expect(restored.isGenerated, isTrue);
    });

    test('fromJson handles missing fields gracefully', () {
      final entry = SshKeyEntry.fromJson({'id': 'x'});
      expect(entry.id, 'x');
      expect(entry.label, '');
      expect(entry.privateKey, '');
    });

    test('equality by id, label, privateKey', () {
      final a = SshKeyEntry(
        id: '1',
        label: 'k',
        privateKey: 'pk',
        publicKey: 'pub',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025),
      );
      final b = SshKeyEntry(
        id: '1',
        label: 'k',
        privateKey: 'pk',
        publicKey: 'pub',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025),
      );
      expect(a, equals(b));
    });

    test('copyWith updates label', () {
      final entry = SshKeyEntry(
        id: '1',
        label: 'Old',
        privateKey: 'pk',
        publicKey: 'pub',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2025),
      );
      final updated = entry.copyWith(label: 'New');
      expect(updated.label, 'New');
      expect(updated.id, entry.id);
      expect(updated.privateKey, entry.privateKey);
    });
  });

  group('Key generation', () {
    test('generateKeyPair Ed25519 produces valid PEM', () {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'test-ed');
      expect(entry.keyType, 'ssh-ed25519');
      expect(entry.privateKey, contains('OPENSSH PRIVATE KEY'));
      expect(entry.publicKey, startsWith('ssh-ed25519 '));
      expect(entry.publicKey, endsWith(' test-ed'));
      expect(entry.label, 'test-ed');
      expect(entry.isGenerated, isTrue);
      expect(entry.id, isNotEmpty);

      // Verify dartssh2 can parse the generated PEM back
      final pairs = SSHKeyPair.fromPem(entry.privateKey);
      expect(pairs, isNotEmpty);
      expect(pairs.first.type, 'ssh-ed25519');
    });

    test('generateKeyPair RSA-2048 produces valid PEM', () {
      final entry = KeyStore.generateKeyPair(SshKeyType.rsa2048, 'test-rsa');
      expect(entry.keyType, contains('rsa'));
      expect(entry.privateKey, contains('OPENSSH PRIVATE KEY'));
      expect(entry.publicKey, contains('rsa'));
      expect(entry.isGenerated, isTrue);

      // Verify dartssh2 can parse
      final pairs = SSHKeyPair.fromPem(entry.privateKey);
      expect(pairs, isNotEmpty);
    });

    test('two generated Ed25519 keys are different', () {
      final a = KeyStore.generateKeyPair(SshKeyType.ed25519, 'key-a');
      final b = KeyStore.generateKeyPair(SshKeyType.ed25519, 'key-b');
      expect(a.privateKey, isNot(b.privateKey));
      expect(a.publicKey, isNot(b.publicKey));
      expect(a.id, isNot(b.id));
    });
  });

  group('Key import', () {
    test('importKey parses Ed25519 PEM', () {
      final generated = KeyStore.generateKeyPair(SshKeyType.ed25519, 'gen');
      final store = KeyStore();
      final entry = store.importKey(generated.privateKey, 'imported');

      expect(entry.label, 'imported');
      expect(entry.keyType, 'ssh-ed25519');
      expect(entry.privateKey, isNotEmpty);
      expect(entry.publicKey, startsWith('ssh-ed25519 '));
      expect(entry.isGenerated, isFalse);
    });

    test('importKey throws on invalid PEM', () {
      final store = KeyStore();
      expect(() => store.importKey('not a PEM', 'bad'), throwsA(isA<Object>()));
    });
  });

  group('KeyStore — DB CRUD', () {
    late AppDatabase db;
    late KeyStore store;

    setUp(() {
      db = openTestDatabase();
      store = KeyStore()..setDatabase(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('loadAll returns empty when no keys', () async {
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('save and loadAll roundtrip', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'roundtrip');
      await store.save(entry);

      final loaded = await store.loadAll();
      expect(loaded.length, 1);
      expect(loaded[entry.id]!.label, 'roundtrip');
      expect(loaded[entry.id]!.keyType, 'ssh-ed25519');
      expect(loaded[entry.id]!.privateKey, entry.privateKey);
    });

    test('delete removes entry', () async {
      final e1 = KeyStore.generateKeyPair(SshKeyType.ed25519, 'one');
      final e2 = KeyStore.generateKeyPair(SshKeyType.ed25519, 'two');
      await store.save(e1);
      await store.save(e2);

      await store.delete(e1.id);
      final loaded = await store.loadAll();
      expect(loaded.length, 1);
      expect(loaded.containsKey(e2.id), isTrue);
    });

    test('get returns single entry or null', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'test');
      await store.save(entry);

      final found = await store.get(entry.id);
      expect(found, isNotNull);
      expect(found!.label, 'test');

      final missing = await store.get('nonexistent');
      expect(missing, isNull);
    });

    test('loadAllSafe returns empty on error', () async {
      // Without database, loadAll returns empty
      final emptyStore = KeyStore();
      final result = await emptyStore.loadAllSafe();
      expect(result, isEmpty);
    });

    test('save on existing id updates in place (not duplicate)', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'before');
      await store.save(entry);

      final renamed = entry.copyWith(label: 'after');
      await store.save(renamed);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[entry.id]!.label, 'after');
    });

    test('saveAll replaces the entire store atomically', () async {
      final a = KeyStore.generateKeyPair(SshKeyType.ed25519, 'a');
      final b = KeyStore.generateKeyPair(SshKeyType.ed25519, 'b');
      await store.save(a);
      await store.save(b);
      expect((await store.loadAll()), hasLength(2));

      final c = KeyStore.generateKeyPair(SshKeyType.ed25519, 'c');
      await store.saveAll({c.id: c});

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[c.id]!.label, 'c');
      expect(loaded.containsKey(a.id), isFalse);
    });

    test('saveAll with empty map clears the store', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'tmp');
      await store.save(entry);
      expect(await store.loadAll(), isNotEmpty);

      await store.saveAll({});
      expect(await store.loadAll(), isEmpty);
    });

    test('save/delete/saveAll no-op when no database attached', () async {
      final detached = KeyStore();
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'orphan');
      // Must not throw even though there is no backing DB.
      await detached.save(entry);
      await detached.delete(entry.id);
      await detached.saveAll({entry.id: entry});
    });
  });

  group('KeyStore — import dedup', () {
    late AppDatabase db;
    late KeyStore store;

    setUp(() {
      db = openTestDatabase();
      store = KeyStore()..setDatabase(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('privateKeyFingerprint is stable for equivalent PEMs', () {
      const pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END-----';
      final a = KeyStore.privateKeyFingerprint(pem);
      final b = KeyStore.privateKeyFingerprint('$pem\n\n');
      final c = KeyStore.privateKeyFingerprint(pem.replaceAll('\n', '\r\n'));
      expect(a, isNotEmpty);
      expect(a, b);
      expect(a, c);
    });

    test('privateKeyFingerprint differs for distinct keys', () {
      final a = KeyStore.privateKeyFingerprint('pem-a');
      final b = KeyStore.privateKeyFingerprint('pem-b');
      expect(a, isNot(b));
    });

    test('findIdByPrivateKey returns existing id on match', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'k1');
      await store.save(entry);
      final id = await store.findIdByPrivateKey(entry.privateKey);
      expect(id, entry.id);
    });

    test('findIdByPrivateKey returns null when no match', () async {
      final id = await store.findIdByPrivateKey('does-not-exist');
      expect(id, isNull);
    });

    test('importForMerge reuses id for identical private key', () async {
      final entry = KeyStore.generateKeyPair(SshKeyType.ed25519, 'original');
      await store.save(entry);

      // Simulate incoming import with a different id but same key material.
      final incoming = SshKeyEntry(
        id: 'other-id',
        label: 'imported',
        privateKey: entry.privateKey,
        publicKey: entry.publicKey,
        keyType: entry.keyType,
        createdAt: DateTime(2025),
      );
      final resolvedId = await store.importForMerge(incoming);
      expect(resolvedId, entry.id, reason: 'must dedupe by fingerprint');
      expect(await store.loadAll(), hasLength(1));
    });

    test(
      'importForMerge inserts fresh entry with "(copy)" label on label collision',
      () async {
        final a = KeyStore.generateKeyPair(SshKeyType.ed25519, 'shared');
        await store.save(a);

        final b = KeyStore.generateKeyPair(SshKeyType.ed25519, 'shared');
        final newId = await store.importForMerge(b);

        final all = await store.loadAll();
        expect(all, hasLength(2));
        expect(all[newId]!.label, 'shared (copy)');
      },
    );

    test(
      'importForMerge suffixes "(copy N)" when copy label also taken',
      () async {
        final a = KeyStore.generateKeyPair(SshKeyType.ed25519, 'k');
        await store.save(a);
        final b = KeyStore.generateKeyPair(SshKeyType.ed25519, 'k');
        await store.save(b.copyWith(label: 'k (copy)'));

        final c = KeyStore.generateKeyPair(SshKeyType.ed25519, 'k');
        final newId = await store.importForMerge(c);
        final all = await store.loadAll();
        expect(all[newId]!.label, 'k (copy 2)');
      },
    );
  });

  group('SshKeyType', () {
    test('all types have labels', () {
      for (final t in SshKeyType.values) {
        expect(t.label, isNotEmpty);
      }
    });
  });

  group('KeyStoreException', () {
    test('toString includes message', () {
      const ex = KeyStoreException('boom');
      expect(ex.toString(), contains('boom'));
      expect(ex.toString(), startsWith('KeyStoreException'));
    });

    test('preserves cause', () {
      final cause = StateError('inner');
      final ex = KeyStoreException('wrap', cause: cause);
      expect(ex.message, 'wrap');
      expect(ex.cause, same(cause));
    });
  });
}
