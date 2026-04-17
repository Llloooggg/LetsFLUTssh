import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_models.dart';
import '../../utils/logger.dart';

/// Sort column options for file table.
enum SortColumn { name, size, mode, modified, owner }

/// Cached outcome of an async folder-size computation.
sealed class FolderSizeResult {
  const FolderSizeResult();
}

class FolderSizeOk extends FolderSizeResult {
  final int bytes;
  const FolderSizeOk(this.bytes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FolderSizeOk && other.bytes == bytes;

  @override
  int get hashCode => bytes.hashCode;
}

class FolderSizeFailed extends FolderSizeResult {
  const FolderSizeFailed();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FolderSizeFailed;

  @override
  int get hashCode => 0;
}

/// Controller for a single file pane (local or remote).
class FilePaneController extends ChangeNotifier {
  final FileSystem fs;
  final String label;

  String _currentPath = '';
  List<FileEntry> _entries = [];
  Set<String> _selected = {};
  bool _loading = false;
  Object? _error;
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;

  // Cached computed properties (invalidated on entries/selection change)
  List<FileEntry>? _cachedSelectedEntries;
  int? _cachedTotalFileSize;

  // Folder size cache: path → result (calculated async, max 2 concurrent).
  // Failed computations are cached as `FolderSizeFailed` so the UI can show
  // an error indicator instead of an indefinite spinner, and so the queue
  // does not endlessly retry the same broken path on every redraw.
  final Map<String, FolderSizeResult> _folderSizes = {};
  final Set<String> _folderSizesPending = {};
  final Queue<String> _folderSizeQueue = Queue();
  static const _maxConcurrentSizeCalcs = 2;

  // Navigation history
  final _backStack = <String>[];
  final _forwardStack = <String>[];

  FilePaneController({required this.fs, required this.label});

  String get currentPath => _currentPath;
  List<FileEntry> get entries => List.unmodifiable(_entries);
  Set<String> get selected => _selected;
  bool get loading => _loading;
  Object? get error => _error;
  SortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

  /// Get cached folder size, or null if not yet calculated.
  FolderSizeResult? folderSize(String path) => _folderSizes[path];

  /// Discard any cached size (success or failure) for [path] so the next
  /// `requestFolderSize` retries from scratch. Used by the "retry" affordance
  /// in the UI when the user wants to re-attempt a failed calculation.
  void clearFolderSize(String path) {
    if (_folderSizes.remove(path) != null) notifyListeners();
  }

  /// Request async folder size calculation (queued, max 2 concurrent).
  void requestFolderSize(String path) {
    if (_folderSizes.containsKey(path) ||
        _folderSizesPending.contains(path) ||
        _folderSizeQueue.contains(path)) {
      return;
    }
    _folderSizeQueue.add(path);
    _drainSizeQueue();
  }

  void _drainSizeQueue() {
    while (_folderSizesPending.length < _maxConcurrentSizeCalcs &&
        _folderSizeQueue.isNotEmpty) {
      final path = _folderSizeQueue.removeFirst();
      if (_folderSizes.containsKey(path)) continue;
      _folderSizesPending.add(path);
      fs
          .dirSize(path)
          .then((size) {
            _folderSizes[path] = FolderSizeOk(size);
            _folderSizesPending.remove(path);
            notifyListeners();
            _drainSizeQueue();
          })
          .catchError((e) {
            // Cache the failure so the UI shows an error marker and the
            // queue does not re-pick this path on every redraw. Caller can
            // explicitly retry via `clearFolderSize`.
            _folderSizes[path] = const FolderSizeFailed();
            _folderSizesPending.remove(path);
            AppLogger.instance.log(
              'Folder size failed: $path: $e',
              name: 'FilePane',
            );
            notifyListeners();
            _drainSizeQueue();
          });
    }
  }

  /// Initialize with the file system's initial directory.
  Future<void> init() async {
    final dir = await fs.initialDir();
    await navigateTo(dir, addToHistory: false);
  }

  /// Navigate to a directory path.
  Future<void> navigateTo(String path, {bool addToHistory = true}) async {
    if (addToHistory && _currentPath.isNotEmpty) {
      _backStack.add(_currentPath);
      _forwardStack.clear();
    }
    _currentPath = path;
    _selected = {};
    _folderSizes.clear();
    _folderSizesPending.clear();
    _folderSizeQueue.clear();
    await refresh();
  }

  /// Go to parent directory.
  Future<void> navigateUp() async {
    if (_currentPath == '/') return;
    final parent = _currentPath.endsWith('/')
        ? _currentPath.substring(0, _currentPath.length - 1)
        : _currentPath;
    final idx = parent.lastIndexOf('/');
    final up = idx <= 0 ? '/' : parent.substring(0, idx);
    await navigateTo(up);
  }

  /// Go back in navigation history.
  Future<void> goBack() async {
    if (_backStack.isEmpty) return;
    _forwardStack.add(_currentPath);
    _currentPath = _backStack.removeLast();
    _selected = {};
    await refresh();
  }

  /// Go forward in navigation history.
  Future<void> goForward() async {
    if (_forwardStack.isEmpty) return;
    _backStack.add(_currentPath);
    _currentPath = _forwardStack.removeLast();
    _selected = {};
    await refresh();
  }

  /// Refresh current directory listing.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _entries = await fs.list(_currentPath);
      _sortEntries();
      _invalidateCaches();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to list $_currentPath: $e',
        name: 'FilePane',
        error: e,
      );
      _error = e;
      _entries = [];
      _invalidateCaches();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _invalidateCaches() {
    _cachedSelectedEntries = null;
    _cachedTotalFileSize = null;
  }

  void _invalidateSelectionCache() {
    _cachedSelectedEntries = null;
  }

  /// Toggle selection of a file entry.
  void toggleSelect(String path) {
    final newSet = Set<String>.from(_selected);
    if (newSet.contains(path)) {
      newSet.remove(path);
    } else {
      newSet.add(path);
    }
    _selected = newSet;
    _invalidateSelectionCache();
    notifyListeners();
  }

  /// Select a single entry (clear others).
  void selectSingle(String path) {
    _selected = {path};
    _invalidateSelectionCache();
    notifyListeners();
  }

  /// Clear selection.
  void clearSelection() {
    _selected = {};
    _invalidateSelectionCache();
    notifyListeners();
  }

  /// Select all entries.
  void selectAll() {
    _selected = _entries.map((e) => e.path).toSet();
    _invalidateSelectionCache();
    notifyListeners();
  }

  /// Change sort column/direction.
  void setSort(SortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    _sortEntries();
    notifyListeners();
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      // Directories always first
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;

      int cmp;
      switch (_sortColumn) {
        case SortColumn.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortColumn.size:
          cmp = a.size.compareTo(b.size);
        case SortColumn.mode:
          cmp = a.mode.compareTo(b.mode);
        case SortColumn.modified:
          cmp = a.modTime.compareTo(b.modTime);
        case SortColumn.owner:
          cmp = a.owner.toLowerCase().compareTo(b.owner.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  /// Set selection to a specific set of paths.
  void selectPaths(Set<String> paths) {
    _selected = paths;
    _invalidateSelectionCache();
    notifyListeners();
  }

  /// Total size of all non-directory entries (cached).
  int get totalFileSize {
    return _cachedTotalFileSize ??= _entries
        .where((e) => !e.isDir)
        .fold<int>(0, (sum, e) => sum + e.size);
  }

  /// Get selected file entries (cached, invalidated on selection/entries change).
  List<FileEntry> get selectedEntries {
    return _cachedSelectedEntries ??= _entries
        .where((e) => _selected.contains(e.path))
        .toList();
  }

  @override
  void dispose() {
    _backStack.clear();
    _forwardStack.clear();
    super.dispose();
  }
}
