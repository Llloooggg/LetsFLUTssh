import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/security/session_credential_cache.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  // Each test starts from an empty SecretStore so writes are
  // observable without cross-test leakage.
  setUp(() async {
    await rust_app.secretsClear();
  });

  group('SessionCredentialCache', () {
    final cache = SessionCredentialCache();

    test('store stages each non-empty slot under sess.<slot>.<id>', () async {
      await cache.store(
        sessionId: 's1',
        password: 'pw',
        keyData: 'PEM',
        keyPassphrase: 'pp',
      );

      expect(rust_app.secretsHas(id: 'sess.password.s1'), isTrue);
      expect(rust_app.secretsHas(id: 'sess.key.s1'), isTrue);
      expect(rust_app.secretsHas(id: 'sess.passphrase.s1'), isTrue);

      // Bytes round-trip via UTF-8.
      expect(utf8.decode(rust_app.secretsTake(id: 'sess.password.s1')), 'pw');
      expect(utf8.decode(rust_app.secretsTake(id: 'sess.key.s1')), 'PEM');
      expect(utf8.decode(rust_app.secretsTake(id: 'sess.passphrase.s1')), 'pp');
    });

    test('store with null slots drops instead of staging', () async {
      // Pre-seed every slot so we can observe drops.
      await rust_app.secretsPut(
        id: 'sess.password.s2',
        bytes: utf8.encode('old'),
      );
      await rust_app.secretsPut(id: 'sess.key.s2', bytes: utf8.encode('old'));
      await rust_app.secretsPut(
        id: 'sess.passphrase.s2',
        bytes: utf8.encode('old'),
      );

      await cache.store(
        sessionId: 's2',
        password: null,
        keyData: null,
        keyPassphrase: null,
      );

      expect(rust_app.secretsHas(id: 'sess.password.s2'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.key.s2'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.passphrase.s2'), isFalse);
    });

    test('store with empty strings is a drop, not a put', () async {
      await rust_app.secretsPut(
        id: 'sess.password.s3',
        bytes: utf8.encode('seeded'),
      );

      await cache.store(sessionId: 's3', password: '');

      expect(rust_app.secretsHas(id: 'sess.password.s3'), isFalse);
    });

    test('store overwrites a previous value for the same slot', () async {
      await cache.store(sessionId: 's4', password: 'first');
      await cache.store(sessionId: 's4', password: 'second');

      expect(
        utf8.decode(rust_app.secretsTake(id: 'sess.password.s4')),
        'second',
      );
    });

    test('store namespaces session ids — s5 password ≠ s6 password', () async {
      await cache.store(sessionId: 's5', password: 'pw5');
      await cache.store(sessionId: 's6', password: 'pw6');

      expect(utf8.decode(rust_app.secretsTake(id: 'sess.password.s5')), 'pw5');
      expect(utf8.decode(rust_app.secretsTake(id: 'sess.password.s6')), 'pw6');
    });

    test('evict drops every slot for one sessionId only', () async {
      await cache.store(
        sessionId: 's7',
        password: 'pw',
        keyData: 'PEM',
        keyPassphrase: 'pp',
      );
      await cache.store(sessionId: 's8', password: 'keep');

      await cache.evict('s7');

      expect(rust_app.secretsHas(id: 'sess.password.s7'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.key.s7'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.passphrase.s7'), isFalse);
      // The neighbouring sessionId stays intact.
      expect(rust_app.secretsHas(id: 'sess.password.s8'), isTrue);
    });

    test('evict on a session that has nothing staged is a no-op', () async {
      await cache.evict('never-existed');
      // No throw; SecretStore stays empty (no other slots seeded).
      expect(
        rust_app.secretsHas(id: 'sess.password.never-existed'),
        isFalse,
      );
    });

    test('evictAll wipes every staged secret', () async {
      await cache.store(sessionId: 's9', password: 'pw', keyData: 'PEM');
      await cache.store(sessionId: 's10', password: 'pw');
      // Plus a non-session entry — evictAll must scrub it too.
      await rust_app.secretsPut(
        id: 'conn.something.uuid',
        bytes: utf8.encode('transient'),
      );

      await cache.evictAll();

      expect(rust_app.secretsHas(id: 'sess.password.s9'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.key.s9'), isFalse);
      expect(rust_app.secretsHas(id: 'sess.password.s10'), isFalse);
      expect(rust_app.secretsHas(id: 'conn.something.uuid'), isFalse);
    });
  });
}
