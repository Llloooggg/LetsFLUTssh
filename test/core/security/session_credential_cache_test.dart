import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/session_credential_cache.dart';

void main() {
  group('SessionCredentialCache', () {
    late SessionCredentialCache cache;

    setUp(() => cache = SessionCredentialCache());
    tearDown(() => cache.evictAll());

    test('store + read round-trip preserves every slot', () {
      cache.store(
        sessionId: 'alpha',
        password: 'hunter2',
        keyData:
            '-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----\n',
        keyPassphrase: 'phrase',
      );
      final got = cache.read('alpha');
      expect(got, isNotNull);
      expect(got!.passwordString, 'hunter2');
      expect(got.keyDataString, contains('BEGIN PRIVATE KEY'));
      expect(got.keyPassphraseString, 'phrase');
    });

    test('empty slots are not allocated', () {
      cache.store(sessionId: 'beta', password: 'pw', keyData: '');
      final got = cache.read('beta');
      expect(got!.password, isNotNull);
      expect(got.keyData, isNull);
      expect(got.keyPassphrase, isNull);
    });

    test('empty envelope does not insert an entry', () {
      cache.store(sessionId: 'gamma', password: null, keyData: '');
      expect(cache.read('gamma'), isNull);
      expect(cache.size, 0);
    });

    test('store with existing id disposes the old entry first', () {
      cache.store(sessionId: 'delta', password: 'first');
      final first = cache.read('delta')!;
      final firstPasswordBuffer = first.password!;
      cache.store(sessionId: 'delta', password: 'second');
      // Old buffer is disposed — reading its bytes must throw.
      expect(() => firstPasswordBuffer.bytes, throwsStateError);
      expect(cache.read('delta')!.passwordString, 'second');
      expect(cache.size, 1);
    });

    test('evict wipes one entry and leaves others intact', () {
      cache.store(sessionId: 'a', password: 'pa');
      cache.store(sessionId: 'b', password: 'pb');
      final aBuffer = cache.read('a')!.password!;
      cache.evict('a');
      expect(cache.read('a'), isNull);
      expect(() => aBuffer.bytes, throwsStateError);
      expect(cache.read('b'), isNotNull);
      expect(cache.read('b')!.passwordString, 'pb');
    });

    test('evict with unknown id is a no-op', () {
      cache.store(sessionId: 'only', password: 'x');
      cache.evict('other');
      expect(cache.read('only'), isNotNull);
      expect(cache.size, 1);
    });

    test('evictAll disposes every entry and clears the map', () {
      cache.store(sessionId: 'a', password: 'pa');
      cache.store(sessionId: 'b', keyData: 'kb');
      final aPw = cache.read('a')!.password!;
      final bKey = cache.read('b')!.keyData!;
      cache.evictAll();
      expect(cache.size, 0);
      expect(cache.read('a'), isNull);
      expect(cache.read('b'), isNull);
      expect(() => aPw.bytes, throwsStateError);
      expect(() => bKey.bytes, throwsStateError);
    });

    test('decoded slot value survives buffer lifetime (copy on decode)', () {
      cache.store(sessionId: 'x', password: 'persist');
      final s1 = cache.read('x')!.passwordString;
      cache.evict('x');
      // The decoded String is a managed Dart value independent of the
      // now-disposed SecretBuffer — still valid.
      expect(s1, 'persist');
    });

    test('UTF-8 payloads round-trip (non-ASCII passwords)', () {
      cache.store(sessionId: 'intl', password: 'пароль😀');
      expect(cache.read('intl')!.passwordString, 'пароль😀');
      // Direct byte-level check too.
      final bytes = cache.read('intl')!.password!.bytes;
      expect(utf8.decode(bytes), 'пароль😀');
    });
  });
}
