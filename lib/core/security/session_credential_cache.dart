import 'dart:convert';

import '../../src/rust/api/app.dart' as rust_app;

/// Per-session credential write-through to the Rust `SecretStore`.
///
/// # Secret-store boundary
///
/// The plaintext credentials (password / keyData / passphrase) live
/// exclusively inside the Rust core's `SecretStore` (a process-
/// singleton `Zeroizing<Vec<u8>>` map). This Dart class is a thin
/// translation layer that maps `(sessionId, slot)` → namespaced ID
/// and fires FRB writes / drops. Reads are intentionally not exposed
/// — the eventual `connect_*_with_secret` variants resolve the
/// bytes Rust-side, so plaintext never returns to the Dart heap.
///
/// # ID namespace
///   * `sess.password.{sessionId}`
///   * `sess.key.{sessionId}`
///   * `sess.passphrase.{sessionId}`
///
/// # What is NOT cached
///
///   * `keyPath` — path to an on-disk key file. Not a secret; the
///     reconnect path re-reads it from the Session object.
class SessionCredentialCache {
  static String _passwordId(String sessionId) => 'sess.password.$sessionId';
  static String _keyDataId(String sessionId) => 'sess.key.$sessionId';
  static String _passphraseId(String sessionId) => 'sess.passphrase.$sessionId';

  /// Store an auth envelope for [sessionId]. If an entry already exists
  /// for any slot it is overwritten (the previous Zeroizing buffer in
  /// Rust scrubs on drop). Empty / null slots are dropped, not stored.
  Future<void> store({
    required String sessionId,
    String? password,
    String? keyData,
    String? keyPassphrase,
  }) async {
    await _putOrDrop(_passwordId(sessionId), password);
    await _putOrDrop(_keyDataId(sessionId), keyData);
    await _putOrDrop(_passphraseId(sessionId), keyPassphrase);
  }

  static Future<void> _putOrDrop(String id, String? value) async {
    if (value == null || value.isEmpty) {
      rust_app.secretsDrop(id: id);
      return;
    }
    rust_app.secretsPut(id: id, bytes: utf8.encode(value));
  }

  /// Evict one entry. Drops every slot under that sessionId.
  Future<void> evict(String sessionId) async {
    rust_app.secretsDrop(id: _passwordId(sessionId));
    rust_app.secretsDrop(id: _keyDataId(sessionId));
    rust_app.secretsDrop(id: _passphraseId(sessionId));
  }

  /// Evict every entry. Maps to `secrets_clear` on the Rust side —
  /// drops every cached secret across every sessionId, plus any
  /// non-session entries (key-store cache, connection passphrases).
  /// Used on app shutdown, wipe-all, and forgot-password reset.
  Future<void> evictAll() async {
    await rust_app.secretsClear();
  }
}
