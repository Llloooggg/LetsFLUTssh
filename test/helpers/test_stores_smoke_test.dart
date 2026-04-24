import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

import 'test_stores.dart';

void main() {
  // Pin the test_stores.dart contract — a fresh bundle round-trips a
  // real session through the real SessionStore + drift in-memory
  // database. If a future refactor renames `setDatabase` on any
  // store, this smoke test catches the miss before every integration
  // test that relies on the bundle starts exploding.

  late TestStores stores;

  setUp(() {
    stores = makeTestStores();
  });

  tearDown(() async {
    await stores.close();
  });

  test('session round-trips through the bundle', () async {
    await stores.sessionStore.load();
    expect(stores.sessionStore.sessions, isEmpty);
    final session = Session(
      id: 'a',
      label: 'test',
      server: const ServerAddress(host: 'example.com', port: 22, user: 'root'),
    );
    await stores.sessionStore.add(session);
    // Reload to prove persistence, not just in-memory caching.
    await stores.sessionStore.load();
    expect(stores.sessionStore.sessions.single.id, 'a');
    expect(stores.sessionStore.sessions.single.host, 'example.com');
  });

  test('each call returns an isolated DB', () async {
    final other = makeTestStores();
    addTearDown(other.close);
    expect(identical(stores.db, other.db), isFalse);
  });
}
