import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';

// Phase 4.2 stage 6: SnippetStore now reads/writes through FRB. The
// flutter_test runner does not load the native bridge, so the
// persistence-asserting tests that round-tripped through drift's
// in-memory DB no longer apply — equivalent coverage moves to
// integration_test.

void main() {
  group('snippetStoreProvider', () {
    test('returns SnippetStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(snippetStoreProvider);
      expect(store, isA<SnippetStore>());
    });
  });

  group('snippetsProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final snippets = await container.read(snippetsProvider.future);
      expect(snippets, isEmpty);
    });
  });

  group('sessionSnippetsProvider', () {
    test('returns empty list when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final pinned = await container.read(
        sessionSnippetsProvider('whatever').future,
      );
      expect(pinned, isEmpty);
    });
  });
}
