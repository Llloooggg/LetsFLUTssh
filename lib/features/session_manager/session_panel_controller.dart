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

  bool _marqueeInProgress = false;

  bool get selectMode => _selectMode;
  Set<String> get selectedIds => _selectedIds;
  Set<String> get selectedFolderPaths => _selectedFolderPaths;

  String? get focusedSessionId => _focusedSessionId;
  String? get focusedFolderPath => _focusedFolderPath;
  int get focusedFolderItemCount => _focusedFolderItemCount;

  String? get copiedSessionId => _copiedSessionId;

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

  // ---- Clipboard ----------------------------------------------------

  void copyFocused() {
    if (_focusedSessionId == null) return;
    _copiedSessionId = _focusedSessionId;
    // Clipboard is invisible — no listener update needed, but keep
    // semantics consistent by signalling anyway.
    notifyListeners();
  }
}
