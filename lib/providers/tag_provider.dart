import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tags/tag.dart';
import '../core/tags/tag_store.dart';

/// Global tag store instance.
final tagStoreProvider = Provider<TagStore>((ref) {
  return TagStore();
});

/// All tags — invalidate to reload after mutations.
final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final store = ref.watch(tagStoreProvider);
  return store.loadAll();
});

/// Tags for a specific session.
final sessionTagsProvider = FutureProvider.family<List<Tag>, String>((
  ref,
  sessionId,
) async {
  final store = ref.watch(tagStoreProvider);
  return store.getForSession(sessionId);
});

/// Tags for a specific folder (by folder DB id).
final folderTagsProvider = FutureProvider.family<List<Tag>, String>((
  ref,
  folderId,
) async {
  final store = ref.watch(tagStoreProvider);
  return store.getForFolder(folderId);
});
