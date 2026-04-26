/// Bundle of FRB-backed stores wired up for tests.
///
/// Every store reads/writes through `lfs_core.db` via FRB. The
/// flutter_test runner does not load the native bridge, so reads
/// return empty / writes no-op (each store catches the
/// RustLib-not-initialised throw internally). Live persistence
/// coverage belongs in integration_test.
///
/// Usage:
/// ```dart
/// late TestStores stores;
/// setUp(() {
///   stores = makeTestStores();
/// });
/// ```
library;

import 'package:letsflutssh/core/security/auto_lock_store.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';

class TestStores {
  TestStores._({
    required this.sessionStore,
    required this.tagStore,
    required this.snippetStore,
    required this.keyStore,
    required this.autoLockStore,
  });

  final SessionStore sessionStore;
  final TagStore tagStore;
  final SnippetStore snippetStore;
  final KeyStore keyStore;
  final AutoLockStore autoLockStore;

  Future<void> close() async {}
}

TestStores makeTestStores() {
  return TestStores._(
    sessionStore: SessionStore(),
    tagStore: TagStore(),
    snippetStore: SnippetStore(),
    keyStore: KeyStore(),
    autoLockStore: AutoLockStore(),
  );
}
