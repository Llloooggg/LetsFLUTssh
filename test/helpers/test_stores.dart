/// Wire real drift-backed stores on top of an in-memory test database.
///
/// The no-op fakes in `fake_security.dart` / `fake_session_store.dart`
/// are the right default when a test only needs to satisfy provider
/// overrides — they never touch disk, but they also never persist
/// anything, so they cannot exercise round-trip logic like
/// "save a session, reopen the DB, load it back, assert shape".
///
/// For those round-trip paths use [makeTestStores]:
/// ```dart
/// late TestStores stores;
/// setUp(() {
///   stores = makeTestStores();
///   addTearDown(stores.close);
/// });
/// ```
/// The bundle owns the database; callers must not close it separately.
library;

import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/auto_lock_store.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';

/// Bundle of drift-backed stores wired to a single shared
/// [AppDatabase] opened via `openTestDatabase()` (an in-memory
/// NativeDatabase, no filesystem / keychain round-trip).
///
/// The bundle owns [db]; calling [close] closes the DB and leaves
/// every wrapped store dangling (do not reuse after close).
class TestStores {
  TestStores._({
    required this.db,
    required this.sessionStore,
    required this.tagStore,
    required this.snippetStore,
    required this.keyStore,
    required this.autoLockStore,
  });

  final AppDatabase db;
  final SessionStore sessionStore;
  final TagStore tagStore;
  final SnippetStore snippetStore;
  final KeyStore keyStore;
  final AutoLockStore autoLockStore;

  Future<void> close() => db.close();
}

/// Construct a [TestStores] bundle with a fresh in-memory DB and every
/// drift store wired up. Each test gets an isolated database — there
/// is no cross-test state leakage.
TestStores makeTestStores() {
  final db = openTestDatabase();
  // SessionStore reads/writes through FRB; native lib not loaded
  // in unit tests so reads return empty / writes no-op.
  final sessionStore = SessionStore();
  // TagStore now backed by FRB — see SnippetStore note above.
  final tagStore = TagStore();
  // SnippetStore now backed by FRB; native lib not loaded in unit
  // tests so reads return empty / writes no-op via internal try/catch.
  // Live persistence belongs in integration_test.
  final snippetStore = SnippetStore();
  // KeyStore now backed by FRB; native lib not loaded in unit tests.
  final keyStore = KeyStore();
  // AutoLockStore now reads/writes through FRB — unit-test runner
  // doesn't load the native lib, so persistence calls degrade to 0
  // / no-op via the in-store try/catch. Bundle keeps the instance
  // for the provider-override surface; tests that need live values
  // belong in integration_test.
  final autoLockStore = AutoLockStore();
  return TestStores._(
    db: db,
    sessionStore: sessionStore,
    tagStore: tagStore,
    snippetStore: snippetStore,
    keyStore: keyStore,
    autoLockStore: autoLockStore,
  );
}
