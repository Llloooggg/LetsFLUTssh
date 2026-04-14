import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/snippets/snippet.dart';
import '../core/snippets/snippet_store.dart';

/// Global snippet store instance.
final snippetStoreProvider = Provider<SnippetStore>((ref) {
  return SnippetStore();
});

/// All snippets — invalidate to reload after mutations.
final snippetsProvider = FutureProvider<List<Snippet>>((ref) async {
  final store = ref.watch(snippetStoreProvider);
  return store.loadAll();
});

/// Snippets pinned to a specific session.
final sessionSnippetsProvider = FutureProvider.family<List<Snippet>, String>((
  ref,
  sessionId,
) async {
  final store = ref.watch(snippetStoreProvider);
  return store.loadForSession(sessionId);
});
