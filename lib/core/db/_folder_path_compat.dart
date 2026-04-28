/// Folder-path helper compat wrappers — Rust-canonical with Dart
/// fallback so flutter_test contexts that don't bootstrap the FRB
/// native lib still see the same path-resolution policy the
/// production code applies.
///
/// Same shape as `_crypto_compat.dart` — production never reaches
/// the catch arm because `RustLib.init` runs before any provider
/// graph that touches `SessionStore` builds. Tests that mock the
/// DAOs or never bring up FRB hit the Dart branch and exercise the
/// identical orphan-marker / cascade-rename grammar by construction.
///
/// All wrappers are pure, sync, and side-effect-free; they take the
/// folder map view (`Map<String, DbFolder>`) the store keeps in
/// memory and return the same shape the legacy Dart helpers used.
library;

import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/folder_path.dart' as rust_fp;
import '../../utils/logger.dart';

/// Walk the parent chain of [folderId] and return the slash-joined
/// path string. Returns `''` for empty id; `'(orphaned)/...'` when a
/// referenced parent is missing from [folderMap].
String folderBuildPathCompat(
  String? folderId,
  Map<String, rust_db.DbFolder> folderMap,
) {
  final id = folderId ?? '';
  try {
    return rust_fp.folderBuildPath(
      folderId: id,
      folders: folderMap.values.toList(growable: false),
    );
  } catch (_) {
    return _buildPathDart(id, folderMap);
  }
}

/// Reverse lookup — find the folder id whose path equals [path], or
/// `null` for empty / unknown.
String? folderFindIdByPathCompat(
  String path,
  Map<String, rust_db.DbFolder> folderMap,
) {
  try {
    return rust_fp.folderFindIdByPath(
      path: path,
      folders: folderMap.values.toList(growable: false),
    );
  } catch (_) {
    if (path.isEmpty) return null;
    for (final entry in folderMap.entries) {
      if (_buildPathDart(entry.key, folderMap) == path) return entry.key;
    }
    return null;
  }
}

/// Enumerate every reachable folder path in [folderMap]. Result is
/// sorted + deduped.
Set<String> folderAllPathsCompat(Map<String, rust_db.DbFolder> folderMap) {
  try {
    return rust_fp
        .folderAllPaths(folders: folderMap.values.toList(growable: false))
        .toSet();
  } catch (_) {
    final out = <String>{};
    for (final id in folderMap.keys) {
      out.add(_buildPathDart(id, folderMap));
    }
    return out;
  }
}

/// Derive the set of folder paths that have no sessions pointing at
/// them — the "empty folders" the UI renders even when no session
/// lives under them.
Set<String> folderDeriveEmptyCompat(
  Map<String, rust_db.DbFolder> folderMap,
  Set<String> usedFolderIds,
) {
  try {
    return rust_fp
        .folderDeriveEmpty(
          folders: folderMap.values.toList(growable: false),
          usedFolderIds: usedFolderIds.toList(growable: false),
        )
        .toSet();
  } catch (_) {
    final out = <String>{};
    for (final folder in folderMap.values) {
      if (!usedFolderIds.contains(folder.id)) {
        final path = _buildPathDart(folder.id, folderMap);
        if (path.isNotEmpty) out.add(path);
      }
    }
    return out;
  }
}

/// Derive the set of folder paths whose row carries the `collapsed`
/// flag. The UI uses this to render the collapsed-triangle marker.
Set<String> folderDeriveCollapsedCompat(
  Map<String, rust_db.DbFolder> folderMap,
) {
  try {
    return rust_fp
        .folderDeriveCollapsed(
          folders: folderMap.values.toList(growable: false),
        )
        .toSet();
  } catch (_) {
    final out = <String>{};
    for (final folder in folderMap.values) {
      if (folder.collapsed) {
        final path = _buildPathDart(folder.id, folderMap);
        if (path.isNotEmpty) out.add(path);
      }
    }
    return out;
  }
}

/// Apply a folder rename across [paths]: exact matches move; entries
/// under `{oldPath}/` have the prefix rewritten. Result preserves
/// the input collection's iteration shape (Set in → Set out).
Set<String> folderRenamePathsCascadeCompat(
  Set<String> paths,
  String oldPath,
  String newPath,
) {
  try {
    return rust_fp
        .folderRenamePathsCascade(
          paths: paths.toList(growable: false),
          oldPath: oldPath,
          newPath: newPath,
        )
        .toSet();
  } catch (_) {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) {
      return Set<String>.from(paths);
    }
    final prefix = '$oldPath/';
    final out = <String>{};
    for (final p in paths) {
      if (p == oldPath) {
        out.add(newPath);
      } else if (p.startsWith(prefix)) {
        out.add('$newPath/${p.substring(prefix.length)}');
      } else {
        out.add(p);
      }
    }
    return out;
  }
}

/// Pure-Dart fallback path builder — same orphan-marker grammar as
/// `lfs_core::folder_path::build_folder_path`, kept in sync byte-
/// for-byte so the Rust + Dart paths agree on every input.
String _buildPathDart(
  String? folderId,
  Map<String, rust_db.DbFolder> folderMap,
) {
  if (folderId == null || folderId.isEmpty) return '';
  final parts = <String>[];
  String? current = folderId;
  while (current != null) {
    final folder = folderMap[current];
    if (folder == null) {
      AppLogger.instance.log(
        'Orphan folder reference: id=$current (started from $folderId). '
        'Partial path: ${parts.reversed.join('/')}',
        name: 'FolderMapper',
      );
      return '(orphaned)/${parts.reversed.join('/')}';
    }
    parts.add(folder.name);
    current = folder.parentId;
  }
  return parts.reversed.join('/');
}
