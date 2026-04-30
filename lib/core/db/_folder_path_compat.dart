/// Folder-path helper compat wrappers — Rust-canonical paths.
///
/// All wrappers are pure, sync, and side-effect-free; they take the
/// folder map view (`Map<String, DbFolder>`) the store keeps in
/// memory and return the same shape callers expect.
///
/// Tests that exercise these helpers bootstrap FRB via
/// `requireFrbLoaded()`. The Dart shadow implementations were
/// retired once the test suite could load the real `lfs_frb`
/// dynamic library.
library;

import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/folder_path.dart' as rust_fp;

/// Walk the parent chain of [folderId] and return the slash-joined
/// path string. Returns `''` for empty id; `'(orphaned)/...'` when a
/// referenced parent is missing from [folderMap].
String folderBuildPathCompat(
  String? folderId,
  Map<String, rust_db.DbFolder> folderMap,
) {
  return rust_fp.folderBuildPath(
    folderId: folderId ?? '',
    folders: folderMap.values.toList(growable: false),
  );
}

/// Reverse lookup — find the folder id whose path equals [path], or
/// `null` for empty / unknown.
String? folderFindIdByPathCompat(
  String path,
  Map<String, rust_db.DbFolder> folderMap,
) {
  return rust_fp.folderFindIdByPath(
    path: path,
    folders: folderMap.values.toList(growable: false),
  );
}

/// Enumerate every reachable folder path in [folderMap]. Result is
/// sorted + deduped.
Set<String> folderAllPathsCompat(Map<String, rust_db.DbFolder> folderMap) {
  return rust_fp
      .folderAllPaths(folders: folderMap.values.toList(growable: false))
      .toSet();
}

/// Derive the set of folder paths that have no sessions pointing at
/// them — the "empty folders" the UI renders even when no session
/// lives under them.
Set<String> folderDeriveEmptyCompat(
  Map<String, rust_db.DbFolder> folderMap,
  Set<String> usedFolderIds,
) {
  return rust_fp
      .folderDeriveEmpty(
        folders: folderMap.values.toList(growable: false),
        usedFolderIds: usedFolderIds.toList(growable: false),
      )
      .toSet();
}

/// Derive the set of folder paths whose row carries the `collapsed`
/// flag. The UI uses this to render the collapsed-triangle marker.
Set<String> folderDeriveCollapsedCompat(
  Map<String, rust_db.DbFolder> folderMap,
) {
  return rust_fp
      .folderDeriveCollapsed(folders: folderMap.values.toList(growable: false))
      .toSet();
}

/// Apply a folder rename across [paths]: exact matches move; entries
/// under `{oldPath}/` have the prefix rewritten. Result preserves
/// the input collection's iteration shape (Set in → Set out).
Set<String> folderRenamePathsCascadeCompat(
  Set<String> paths,
  String oldPath,
  String newPath,
) {
  return rust_fp
      .folderRenamePathsCascade(
        paths: paths.toList(growable: false),
        oldPath: oldPath,
        newPath: newPath,
      )
      .toSet();
}
