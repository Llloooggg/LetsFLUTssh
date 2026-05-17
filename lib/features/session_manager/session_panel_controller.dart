import 'package:flutter/foundation.dart';

/// Headless state for [SessionPanel]. Holds multi-select, focus, marquee,
/// and clipboard fields so the widget class can stay a thin renderer
/// wired through [AnimatedBuilder].
///
/// Same `ChangeNotifier` pattern as [FilePaneController] — widget-local
/// state that never belongs in a Riverpod provider (never shared, tied
/// to one widget's lifecycle).
class SessionPanelController extends ChangeNotifier {
  bool _selectMode = false;
  final Set<String> _selectedIds = <String>{};
  final Set<String> _selectedFolderPaths = <String>{};

  String? _focusedSessionId;
  String? _focusedFolderPath;
  int _focusedFolderItemCount = 0;

  String? _copiedSessionId;
  String? _copiedFolderPath;

  bool _marqueeInProgress = false;

  bool get selectMode => _selectMode;
  Set<String> get selectedIds => _selectedIds;
  Set<String> get selectedFolderPaths => _selectedFolderPaths;

  String? get focusedSessionId => _focusedSessionId;
  String? get focusedFolderPath => _focusedFolderPath;
  int get focusedFolderItemCount => _focusedFolderItemCount;

  String? get copiedSessionId => _copiedSessionId;
  String? get copiedFolderPath => _copiedFolderPath;

  bool get marqueeInProgress => _marqueeInProgress;

  bool get hasSelection =>
      _selectedIds.isNotEmpty || _selectedFolderPaths.isNotEmpty;

  // ---- Select mode --------------------------------------------------

  void exitSelectMode() {
    _selectMode = false;
    _selectedIds.clear();
    _selectedFolderPaths.clear();
    notifyListeners();
  }

  void enterSelectModeWithSession(String sessionId) {
    _selectMode = true;
    _selectedIds
      ..clear()
      ..add(sessionId);
    _selectedFolderPaths.clear();
    notifyListeners();
  }

  void enterSelectModeWithFolder(String folderPath) {
    _selectMode = true;
    _selectedIds.clear();
    _selectedFolderPaths
      ..clear()
      ..add(folderPath);
    notifyListeners();
  }

  // ---- Selection toggles --------------------------------------------

  void toggleSelected(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void toggleFolderSelected(String folderPath) {
    if (_selectedFolderPaths.contains(folderPath)) {
      _selectedFolderPaths.remove(folderPath);
    } else {
      _selectedFolderPaths.add(folderPath);
    }
    notifyListeners();
  }

  /// Clears multi-selection (marquee / Ctrl+click) but keeps focus, so
  /// the details panel continues showing the last focused row.
  void clearDesktopSelection() {
    if (_selectedIds.isEmpty && _selectedFolderPaths.isEmpty) return;
    _selectedIds.clear();
    _selectedFolderPaths.clear();
    notifyListeners();
  }

  void selectAllIds(Iterable<String> ids) {
    _selectedIds.addAll(ids);
    notifyListeners();
  }

  void deselectAll() {
    if (_selectedIds.isEmpty && _selectedFolderPaths.isEmpty) return;
    _selectedIds.clear();
    _selectedFolderPaths.clear();
    notifyListeners();
  }

  // ---- Marquee ------------------------------------------------------

  void setMarqueeSelection(
    Set<String> ids, [
    Set<String> folderPaths = const {},
  ]) {
    _selectedIds
      ..clear()
      ..addAll(ids);
    _selectedFolderPaths
      ..clear()
      ..addAll(folderPaths);
    notifyListeners();
  }

  void setMarqueeInProgress(bool value) {
    if (_marqueeInProgress == value) return;
    _marqueeInProgress = value;
    notifyListeners();
  }

  // ---- Focus --------------------------------------------------------

  void setFocusedSession(String? id) {
    _focusedSessionId = id;
    _focusedFolderPath = null;
    notifyListeners();
  }

  void setFocusedFolder(String path, int itemCount) {
    _focusedFolderPath = path;
    _focusedFolderItemCount = itemCount;
    _focusedSessionId = null;
    notifyListeners();
  }

  /// Clear both focused pointers. Used by the "tap empty space in the
  /// sidebar" path to dim the row highlight without giving up the
  /// Flutter `FocusNode` (so `CallbackShortcuts` keeps firing on
  /// `Ctrl+V` / `Ctrl+Z`).
  void clearFocus() {
    if (_focusedSessionId == null && _focusedFolderPath == null) return;
    _focusedSessionId = null;
    _focusedFolderPath = null;
    _focusedFolderItemCount = 0;
    notifyListeners();
  }

  // ---- Clipboard ----------------------------------------------------

  void copyFocused() {
    if (_focusedSessionId != null) {
      copySessionId(_focusedSessionId!);
      return;
    }
    if (_focusedFolderPath != null) {
      copyFolderPath(_focusedFolderPath!);
    }
  }

  /// Mark the focused entry for cut — a subsequent paste moves the
  /// session / folder to the target folder instead of duplicating
  /// it. The flag is one-shot; paste consumes it and clears the
  /// clipboard.
  void cutFocused() {
    if (_focusedSessionId != null) {
      cutSessionId(_focusedSessionId!);
      return;
    }
    if (_focusedFolderPath != null) {
      cutFolderPath(_focusedFolderPath!);
    }
  }

  /// Copy [id] directly into the clipboard — used by the right-click
  /// context menu, which targets the row under the cursor rather than
  /// the currently focused row.
  void copySessionId(String id) {
    _copiedSessionId = id;
    _copiedFolderPath = null;
    _cutPending = false;
    notifyListeners();
  }

  /// Mark [id] for cut — same rationale as [copySessionId].
  void cutSessionId(String id) {
    _copiedSessionId = id;
    _copiedFolderPath = null;
    _cutPending = true;
    notifyListeners();
  }

  /// Copy a folder path directly into the clipboard. Mutually
  /// exclusive with the session-id slot — clipboard holds either a
  /// session OR a folder, never both. Paste decides which entity to
  /// duplicate / move based on whichever slot is non-null.
  void copyFolderPath(String path) {
    _copiedFolderPath = path;
    _copiedSessionId = null;
    _cutPending = false;
    notifyListeners();
  }

  /// Mark a folder path for cut — paste will move the folder + its
  /// entire subtree (sessions, subfolders) to the target instead of
  /// deep-duplicating it.
  void cutFolderPath(String path) {
    _copiedFolderPath = path;
    _copiedSessionId = null;
    _cutPending = true;
    notifyListeners();
  }

  /// True when the current clipboard entry should be treated as a
  /// cut + paste (move) rather than a copy + paste (duplicate).
  bool get cutPending => _cutPending;
  bool _cutPending = false;

  /// Called by the panel's paste path after the move / duplicate
  /// completes, and by the lock / wipe paths via
  /// `SessionPanel.dispose` on the reset flow. The clipboard holds a
  /// 30-char id or short folder path — not session data — so there
  /// is no RAM leak beyond the reference itself, and clearing is
  /// driven by explicit events (paste succeeded, panel torn down)
  /// rather than a wall-clock timer.
  void clearClipboard() {
    if (_copiedSessionId == null && _copiedFolderPath == null && !_cutPending) {
      return;
    }
    _copiedSessionId = null;
    _copiedFolderPath = null;
    _cutPending = false;
    notifyListeners();
  }
}
