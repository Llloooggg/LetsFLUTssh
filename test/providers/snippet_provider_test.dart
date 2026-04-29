import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';

// SnippetsNotifier reads/writes through FRB. The flutter_test runner
// does not load the native bridge, so the persistence-asserting tests
// that round-tripped through drift's in-memory DB no longer apply —
// equivalent coverage moves to integration_test.

void main() {
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
