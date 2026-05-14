import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/api/session_history.dart' as rust_history;
import '../../src/rust/api/sessions.dart' as rust_sess;
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
/// method calls round-trip through FRB; the snapshot envelope
/// (`{sessions: [...], emptyFolders: [...], description: ...}`)
/// codec also lives Rust-side under
/// `lfs_core::session_json::{encode,decode}_snapshot_envelope` so
/// the Dart class never opens the blob.
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
    // [SessionMutator] only ever stores `withoutCredentials()`
    // shapes in `state`, so the credential-bearing fields are
    // empty Strings; routing through `includeCredentials: false`
    // keeps the blob structurally credential-clean by construction.
    //
    // Both the per-session canonical encode and the outer
    // `{sessions, emptyFolders, description}` envelope wrap live
    // Rust-side in `lfs_core::session_json` — the Dart caller only
    // builds the typed input list and reads back the wire bytes.
    final inputs = snapshot.sessions
        .map((s) => sessionToJsonInput(s, includeCredentials: false))
        .toList(growable: false);
    final encoded = rust_sess.sessionHistoryEncodeSnapshotEnvelope(
      sessions: inputs,
      emptyFolders: snapshot.emptyFolders.toList(growable: false),
      description: snapshot.description,
    );
    return Uint8List.fromList(utf8.encode(encoded));
  }

  static SessionSnapshot _decode(Uint8List blob, String description) {
    final raw = utf8.decode(blob);
    final envelope = rust_sess.sessionHistoryDecodeSnapshotEnvelope(json: raw);
    final sessions = envelope.sessions.map(sessionFromJsonOutput).toList();
    return SessionSnapshot(
      sessions: sessions,
      emptyFolders: envelope.emptyFolders.toSet(),
      // The description in the envelope is informational only —
      // the registry hands the authoritative description back as a
      // sibling string argument so the Dart caller can preserve
      // its existing undo/redo menu-label contract.
      description: description,
    );
  }
}
