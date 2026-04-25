import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';

// Phase 4.2 stage 6: TagStore now reads/writes through FRB
// (`lfs_core.db`). flutter_test does not load the native bridge, so
// the persistence-asserting unit tests that round-tripped through
// drift's in-memory DB no longer apply — equivalent coverage moves
// to integration_test.

void main() {
  group('TagStore (no-DB sentinels)', () {
    test('loadAll returns empty when DB is unreachable', () async {
      final store = TagStore();
      expect(await store.loadAll(), isEmpty);
    });

    test('getForSession returns empty when DB is unreachable', () async {
      final store = TagStore();
      expect(await store.getForSession('whatever'), isEmpty);
    });

    test('getForFolder returns empty when DB is unreachable', () async {
      final store = TagStore();
      expect(await store.getForFolder('whatever'), isEmpty);
    });
  });
}
