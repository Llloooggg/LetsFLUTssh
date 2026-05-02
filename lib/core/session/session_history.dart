import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/api/session_history.dart' as rust_history;
import 'session.dart';

/// Snapshot of session state for undo/redo.
///
/// Pure Dart value class — UI / Riverpod consumers read `sessions`,
/// `emptyFolders` and `description` directly. Persistence to the
/// Rust-side stack happens through `_encode` / `_decode` on the
/// [SessionHistory] boundary; the Rust actor stores opaque bytes.
class SessionSnapshot {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final String description;

  SessionSnapshot({
    required this.sessions,
    required this.emptyFolders,
    required this.description,
  });
}

/// Undo/redo history stack for session operations.
///
/// State machine ownership lives in `lfs_core::session_history`
/// (FRB sync). This Dart class is a thin handle wrapper:
/// `SessionHistory()` mints a Rust-side actor on construction;
/// method calls round-trip through FRB; the only Dart-side
/// concern is `SessionSnapshot` ↔ JSON-bytes serialisation since
/// the Rust actor stores opaque blobs.
///
/// Pair every `SessionHistory()` with a [dispose] when the owning
/// notifier tears down — otherwise the actor handle leaks for the
/// lifetime of the process.
class SessionHistory {
  late final BigInt _handleId;
  bool _disposed = false;

  SessionHistory() {
    _handleId = rust_history.sessionHistoryCreate();
  }

  bool get canUndo {
    if (_disposed) return false;
    return rust_history.sessionHistoryCanUndo(handleId: _handleId);
  }

  bool get canRedo {
    if (_disposed) return false;
    return rust_history.sessionHistoryCanRedo(handleId: _handleId);
  }

  String? get undoDescription {
    if (_disposed) return null;
    return rust_history.sessionHistoryUndoDescription(handleId: _handleId);
  }

  String? get redoDescription {
    if (_disposed) return null;
    return rust_history.sessionHistoryRedoDescription(handleId: _handleId);
  }

  /// Save current state before a destructive operation.
  void pushUndo(SessionSnapshot snapshot) {
    if (_disposed) return;
    rust_history.sessionHistoryPushUndo(
      handleId: _handleId,
      description: snapshot.description,
      blob: _encode(snapshot),
    );
  }

  /// Pop the last undo snapshot and push current state onto redo
  /// stack.
  SessionSnapshot? undo(SessionSnapshot currentState) {
    if (_disposed) return null;
    final result = rust_history.sessionHistoryUndo(
      handleId: _handleId,
      currentDescription: currentState.description,
      currentBlob: _encode(currentState),
    );
    if (result == null) return null;
    return _decode(result.blob, result.description);
  }

  /// Pop the last redo snapshot and push current state onto undo
  /// stack.
  SessionSnapshot? redo(SessionSnapshot currentState) {
    if (_disposed) return null;
    final result = rust_history.sessionHistoryRedo(
      handleId: _handleId,
      currentDescription: currentState.description,
      currentBlob: _encode(currentState),
    );
    if (result == null) return null;
    return _decode(result.blob, result.description);
  }

  void clear() {
    if (_disposed) return;
    rust_history.sessionHistoryClear(handleId: _handleId);
  }

  /// Drop the Rust-side actor. Idempotent. Call from the owning
  /// notifier's `dispose` so the per-handle state evicts from the
  /// process registry.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    rust_history.sessionHistoryDrop(handleId: _handleId);
  }

  static Uint8List _encode(SessionSnapshot snapshot) {
    // Plaintext credentials never enter the undo blob.
    // [SessionNotifier] only ever stores `withoutCredentials()`
    // shapes in `state`, so the credential-bearing fields would be
    // empty Strings anyway — but emitting them through
    // `toJsonWithCredentials` re-introduced a JSON-encoded
    // plaintext byte buffer for every undoable mutation, which
    // sat on the Dart heap until the GC reaped it. Use the
    // credential-stripped `toJson()` so the on-bus blob is
    // structurally credential-clean by construction.
    //
    // On restore, the Rust-side DB row keeps its own credential
    // columns; `_restoreSnapshot` writes empty strings there
    // today (a separate pre-existing limitation tracked under
    // the SecretRef migration). Switching to credential-clean
    // JSON here doesn't change the restore behaviour — empty
    // strings come from the cache regardless of whether they
    // travel through `toJson` or `toJsonWithCredentials`.
    final json = {
      'sessions': snapshot.sessions.map((s) => s.toJson()).toList(),
      'emptyFolders': snapshot.emptyFolders.toList(),
      'description': snapshot.description,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  static SessionSnapshot _decode(Uint8List blob, String description) {
    final json = jsonDecode(utf8.decode(blob)) as Map<String, dynamic>;
    final sessions = (json['sessions'] as List<dynamic>)
        .map((e) => Session.fromJson(e as Map<String, dynamic>))
        .toList();
    final folders = (json['emptyFolders'] as List<dynamic>)
        .map((e) => e as String)
        .toSet();
    return SessionSnapshot(
      sessions: sessions,
      emptyFolders: folders,
      description: description,
    );
  }
}
