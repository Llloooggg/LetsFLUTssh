import 'dart:convert';

import '../../src/rust/api/app.dart' as rust_app;

/// Per-session credential cache keyed by sessionId.
///
/// # Secret-store boundary
///
/// The plaintext credentials (password / keyData / passphrase) live
/// exclusively inside the Rust core's `SecretStore` (a process-
/// singleton `Zeroizing<Vec<u8>>` map). This Dart class is a thin
/// wrapper that translates `(sessionId, slot)` → namespaced ID and
/// fires FRB calls. The Dart heap never holds the plaintext beyond
/// the brief moment between the user typing and the FRB
/// `secrets_put` call. Once a `connect_*_with_secret` variant
/// replaces the plaintext-bearing connect path, the bytes never
/// cross back into Dart at all.
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
  /// Track which sessionIds have at least one slot set, so the
  /// `read()` API can return a stub `CachedCredentials` quickly
  /// (with FRB-fed slot accessors) without firing three `has`
  /// probes per call.
  final _knownSessionIds = <String>{};

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
    if ((password != null && password.isNotEmpty) ||
        (keyData != null && keyData.isNotEmpty) ||
        (keyPassphrase != null && keyPassphrase.isNotEmpty)) {
      _knownSessionIds.add(sessionId);
    } else {
      _knownSessionIds.remove(sessionId);
    }
  }

  static Future<void> _putOrDrop(String id, String? value) async {
    if (value == null || value.isEmpty) {
      await rust_app.secretsDrop(id: id);
      return;
    }
    await rust_app.secretsPut(id: id, bytes: utf8.encode(value));
  }

  /// Return a stub envelope that knows how to fetch each slot from
  /// the Rust SecretStore on demand. Returns null if no slot is
  /// stored for [sessionId].
  CachedCredentials? read(String sessionId) {
    if (!_knownSessionIds.contains(sessionId)) return null;
    return CachedCredentials._(sessionId);
  }

  /// Evict one entry. Drops every slot under that sessionId.
  Future<void> evict(String sessionId) async {
    await rust_app.secretsDrop(id: _passwordId(sessionId));
    await rust_app.secretsDrop(id: _keyDataId(sessionId));
    await rust_app.secretsDrop(id: _passphraseId(sessionId));
    _knownSessionIds.remove(sessionId);
  }

  /// Evict every entry. Maps to `secrets_clear` on the Rust side —
  /// drops every cached secret across every sessionId, plus any
  /// non-session entries (key-store cache, connection passphrases).
  /// Used on app shutdown, wipe-all, and forgot-password reset.
  Future<void> evictAll() async {
    await rust_app.secretsClear();
    _knownSessionIds.clear();
  }

  /// Current entry count — for diagnostics / tests only. Do not branch
  /// security-sensitive logic on this.
  int get size => _knownSessionIds.length;
}

/// One session's auth envelope. All three slots are fetched on
/// demand from the Rust SecretStore — Dart never holds them
/// long-term. Each accessor returns the bytes if present (and
/// promptly drops the local copy), or null on cache miss.
class CachedCredentials {
  final String _sessionId;

  CachedCredentials._(this._sessionId);

  /// UTF-8 decode the password slot, or null if absent.
  Future<String?> readPassword() =>
      _readUtf8(SessionCredentialCache._passwordId(_sessionId));

  /// UTF-8 decode the key-data slot (raw PEM text), or null if absent.
  Future<String?> readKeyData() =>
      _readUtf8(SessionCredentialCache._keyDataId(_sessionId));

  /// UTF-8 decode the passphrase slot, or null if absent.
  Future<String?> readKeyPassphrase() =>
      _readUtf8(SessionCredentialCache._passphraseId(_sessionId));

  static Future<String?> _readUtf8(String id) async {
    if (!await rust_app.secretsHas(id: id)) return null;
    // A `secretsGet` accessor is intentionally NOT exposed — that
    // would re-cross plaintext into Dart. The eventual connect path
    // (`ssh_connect_*_with_secret`) bypasses this method entirely
    // and resolves the bytes Rust-side. Until that lands, the cache
    // keeps its existing API shape but cannot serve plaintext: any
    // caller that still needs the actual bytes (the legacy
    // `_withCredentialOverlay` in ConnectionManager) detects the
    // null return and falls through to `Session.auth` directly.
    // Net effect: the cache is no longer a hot plaintext store;
    // Dart-heap exposure shrinks to whatever the Session model
    // itself still carries.
    return null;
  }
}
