import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';

// Phase 4.2 stage 6: SnippetStore now reads/writes through FRB
// (`lfs_core.db`). flutter_test does not load the native bridge, so
// the persistence-asserting unit tests that round-tripped through
// drift's in-memory DB no longer apply — equivalent coverage moves
// to integration_test. Same precedent as the dartssh2 →
// MockSshTransport sweep.

void main() {
  group('SnippetStore (no-DB sentinels)', () {
    test('loadAll returns empty when DB is unreachable', () async {
      // No FRB native lib in unit-test runner → DB call throws →
      // store catches and surfaces an empty list. Same shape pre-
      // unlock at runtime.
      final store = SnippetStore();
      expect(await store.loadAll(), isEmpty);
    });

    test('loadForSession returns empty when DB is unreachable', () async {
      final store = SnippetStore();
      expect(await store.loadForSession('whatever'), isEmpty);
    });

    test('linkedSnippetIds returns empty when DB is unreachable', () async {
      final store = SnippetStore();
      expect(await store.linkedSnippetIds('whatever'), isEmpty);
    });
  });
}
