import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tags/tag.dart';
import '../src/rust/api/db.dart' as rust_db;
import '../utils/logger.dart';

/// All tags — loaded from `letsflutssh.db` on first access. Mutations
/// route through the [TagsNotifier] CRUD methods which update local
/// state optimistically + invalidate the per-session / per-folder
/// family providers below.
///
/// Replaces the prior two-tier `Provider<TagStore>` +
/// `FutureProvider<List<Tag>>` split — the AsyncNotifier owns the FRB read/write
/// pipeline directly, so widgets that already consume the AsyncValue
/// surface keep their `.when()` blocks unchanged.
final tagsProvider = AsyncNotifierProvider<TagsNotifier, List<Tag>>(
  TagsNotifier.new,
);

/// Tags for a specific session.
final sessionTagsProvider = FutureProvider.family<List<Tag>, String>((
  ref,
  sessionId,
) async {
  return _fetchAndSort(
    () => rust_db.dbTagsListForSession(sessionId: sessionId),
  );
});

/// Tags for a specific folder (by folder DB id).
final folderTagsProvider = FutureProvider.family<List<Tag>, String>((
  ref,
  folderId,
) async {
  return _fetchAndSort(() => rust_db.dbTagsListForFolder(folderId: folderId));
});

class TagsNotifier extends AsyncNotifier<List<Tag>> {
  @override
  Future<List<Tag>> build() async => _fetchAndSort(rust_db.dbTagsListAll);

  /// Create a new tag (or update an existing one — Rust uses
  /// ON CONFLICT(id) so repeat inserts upsert).
  Future<void> add(Tag tag) async {
    try {
      await rust_db.dbTagsUpsert(row: _toRow(tag));
    } catch (e) {
      AppLogger.instance.log(
        'Tag upsert failed: $e',
        name: 'TagsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    _invalidateFamilies();
  }

  /// Delete a tag. Cascades to all session/folder links via FK.
  Future<void> delete(String id) async {
    try {
      await rust_db.dbTagsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'Tag delete failed: $e',
        name: 'TagsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    _invalidateFamilies();
  }

  /// Drop every tag. Cascades through `session_tags` / `folder_tags`.
  Future<void> deleteAll() async {
    try {
      await rust_db.dbTagsDeleteAll();
    } catch (e) {
      AppLogger.instance.log(
        'Tag deleteAll failed: $e',
        name: 'TagsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    _invalidateFamilies();
  }

  // --- Session tagging ---

  Future<void> tagSession(String sessionId, String tagId) async {
    try {
      await rust_db.dbSessionTagsLink(sessionId: sessionId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag session $sessionId with $tagId: $e',
        name: 'TagsNotifier',
      );
    }
    ref.invalidate(sessionTagsProvider(sessionId));
  }

  Future<void> untagSession(String sessionId, String tagId) async {
    try {
      await rust_db.dbSessionTagsUnlink(sessionId: sessionId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to untag session $sessionId with $tagId: $e',
        name: 'TagsNotifier',
      );
    }
    ref.invalidate(sessionTagsProvider(sessionId));
  }

  // --- Folder tagging ---

  Future<void> tagFolder(String folderId, String tagId) async {
    try {
      await rust_db.dbFolderTagsLink(folderId: folderId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag folder $folderId with $tagId: $e',
        name: 'TagsNotifier',
      );
    }
    ref.invalidate(folderTagsProvider(folderId));
  }

  Future<void> untagFolder(String folderId, String tagId) async {
    try {
      await rust_db.dbFolderTagsUnlink(folderId: folderId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to untag folder $folderId with $tagId: $e',
        name: 'TagsNotifier',
      );
    }
    ref.invalidate(folderTagsProvider(folderId));
  }

  /// Force a re-pull from the DB. Used by post-import refresh paths
  /// where the Rust apply layer wrote rows directly, and by the
  /// manager panel's mount-time load. Re-fetches imperatively and
  /// assigns `state` *after* the first await so it never schedules a
  /// self-invalidation synchronously during a widget mount — that path
  /// throws under the riverpod 3.3.2 vsync scheduler (`markNeedsBuild`
  /// during build). `return future` preserves the error propagation
  /// the old `invalidateSelf()` path had.
  Future<List<Tag>> loadAll() async {
    state = await AsyncValue.guard(() => _fetchAndSort(rust_db.dbTagsListAll));
    return future;
  }

  void _invalidateFamilies() {
    // Family providers cache per-key; without a way to enumerate the
    // active keys, drop the lot — they'll re-pull on next read.
    ref.invalidate(sessionTagsProvider);
    ref.invalidate(folderTagsProvider);
  }

  static rust_db.DbTag _toRow(Tag tag) => rust_db.DbTag(
    id: tag.id,
    name: tag.name,
    color: tag.color,
    createdAtMs: tag.createdAt.millisecondsSinceEpoch,
  );
}

Tag _toTag(rust_db.DbTag r) => Tag(
  id: r.id,
  name: r.name,
  color: r.color,
  createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
);

Future<List<Tag>> _fetchAndSort(
  Future<List<rust_db.DbTag>> Function() fetch,
) async {
  try {
    final rows = await fetch();
    final list = rows.map(_toTag).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  } catch (e) {
    AppLogger.instance.log(
      'Tag fetch failed: $e',
      name: 'TagsNotifier',
      level: LogLevel.warn,
    );
    return const [];
  }
}
