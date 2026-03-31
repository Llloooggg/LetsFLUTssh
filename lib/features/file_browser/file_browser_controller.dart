import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_models.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';

/// Sort column options for file table.
enum SortColumn { name, size, mode, modified, owner }

/// Controller for a single file pane (local or remote).
class FilePaneController extends ChangeNotifier {
  final FileSystem fs;
  final String label;

  String _currentPath = '';
  List<FileEntry> _entries = [];
  Set<String> _selected = {};
  bool _loading = false;
  String? _error;
  SortColumn _sortColumn = SortColumn.name;
  bool _sortAscending = true;

  // Cached computed properties (invalidated on entries/selection change)
  List<FileEntry>? _cachedSelectedEntries;
  int? _cachedTotalFileSize;

  // Navigation history
  final _backStack = <String>[];
  final _forwardStack = <String>[];

  FilePaneController({required this.fs, required this.label});

  String get currentPath => _currentPath;
  List<FileEntry> get entries => List.unmodifiable(_entries);
  Set<String> get selected => _selected;
  bool get loading => _loading;
  String? get error => _error;
  SortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

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
      AppLogger.instance.log('Failed to list $_currentPath: $e', name: 'FilePane', error: e);
      _error = sanitizeError(e);
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
    return _cachedTotalFileSize ??=
        _entries.where((e) => !e.isDir).fold<int>(0, (sum, e) => sum + e.size);
  }

  /// Get selected file entries (cached, invalidated on selection/entries change).
  List<FileEntry> get selectedEntries {
    return _cachedSelectedEntries ??=
        _entries.where((e) => _selected.contains(e.path)).toList();
  }

  @override
  void dispose() {
    _backStack.clear();
    _forwardStack.clear();
    super.dispose();
  }
}
