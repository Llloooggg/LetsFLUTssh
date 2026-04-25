import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';
import 'package:letsflutssh/providers/tag_provider.dart';

// Phase 4.2 stage 6: TagStore now reads/writes through FRB. The
// flutter_test runner does not load the native bridge, so the
// persistence-asserting tests that round-tripped through drift's
// in-memory DB no longer apply — equivalent coverage moves to
// integration_test.

void main() {
  group('tagStoreProvider', () {
    test('returns TagStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider);
      expect(store, isA<TagStore>());
    });
  });

  group('tagsProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tags = await container.read(tagsProvider.future);
      expect(tags, isEmpty);
    });
  });

  group('sessionTagsProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tags = await container.read(sessionTagsProvider('whatever').future);
      expect(tags, isEmpty);
    });
  });

  group('folderTagsProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tags = await container.read(folderTagsProvider('whatever').future);
      expect(tags, isEmpty);
    });
  });
}
