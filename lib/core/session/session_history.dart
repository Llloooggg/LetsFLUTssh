import '../security/credential_store.dart';
import 'session.dart';

/// Snapshot of session state for undo/redo.
class SessionSnapshot {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final String description;
  /// Credentials saved before deletion — restored on undo.
  final Map<String, CredentialData> credentials;

  SessionSnapshot({
    required this.sessions,
    required this.emptyFolders,
    required this.description,
    this.credentials = const {},
  });
}

/// Undo/redo history stack for session operations.
class SessionHistory {
  final List<SessionSnapshot> _undoStack = [];
  final List<SessionSnapshot> _redoStack = [];

  static const _maxHistory = 50;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String? get undoDescription =>
      _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription =>
      _redoStack.isNotEmpty ? _redoStack.last.description : null;

  /// Save current state before a destructive operation.
  void pushUndo(SessionSnapshot snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Pop the last undo snapshot and push current state onto redo stack.
  SessionSnapshot? undo(SessionSnapshot currentState) {
    if (!canUndo) return null;
    _redoStack.add(currentState);
    return _undoStack.removeLast();
  }

  /// Pop the last redo snapshot and push current state onto undo stack.
  SessionSnapshot? redo(SessionSnapshot currentState) {
    if (!canRedo) return null;
    _undoStack.add(currentState);
    return _redoStack.removeLast();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
