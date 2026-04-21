import 'dart:convert';
import 'dart:typed_data';

import 'secret_buffer.dart';

/// Per-session credential cache keyed by sessionId.
///
/// # Purpose
///
/// Realises the structural advantage of tier 2 (hardware-bound vault)
/// over tier 1 (keychain) in the threat matrix. Before this cache, the
/// auto-lock path was forced to keep the DB key warm whenever any SSH
/// session was active: closing the encrypted store would have evicted
/// the auth envelope for those sessions, so a live connection would be
/// one disconnect away from a broken reconnect. Keeping the DB key warm
/// means RAM forensics of the locked app can still recover it,
/// flattening T1+password and T2+password to the same row.
///
/// The cache holds each session's authentication envelope
/// (password, key bytes, passphrase) in [SecretBuffer] slots —
/// `mlock`/`VirtualLock`-pinned native memory with deterministic
/// zeroisation on [evict]. Reconnect consults the cache; auto-lock is
/// free to wipe the DB key unconditionally.
///
/// # Why not just read session.auth from memory?
///
/// Several reasons:
///   * `SessionStore` is free to strip plaintext from its cached list
///     at any point (see `Session.auth.hasStoredSecret`). If the store
///     evicts the credential portion after the DB closes, we have
///     nothing to reconnect with.
///   * Future pull-to-refresh in the session list may reload the store
///     in the locked state — forcing us to reach into a closed DB.
///   * The cache keeps plaintext exclusively in `mlock`'d memory, not
///     on the Dart heap — harder to page to swap, harder to surface in
///     a heap snapshot.
///
/// # Lifetime
///
///   1. Populated on successful SSH auth (via `ConnectionManager`).
///   2. Preserved across auto-lock: the DB is closed but the cache
///      survives, so the user can reconnect without typing again.
///   3. Evicted on explicit disconnect, on wipe/reset, on container
///      dispose (app shutdown).
///
/// # What is NOT cached
///
///   * `keyPath` — path to an on-disk key file. Not a secret; the
///     reconnect path re-reads it from the Session object.
///   * dartssh2's internal key material. The cache is defensive only;
///     dartssh2 keeps its own copies we cannot reach.
class SessionCredentialCache {
  final _entries = <String, CachedCredentials>{};

  /// Store an auth envelope for [sessionId]. If an entry already exists
  /// it is disposed first — stale bytes never linger.
  void store({
    required String sessionId,
    String? password,
    String? keyData,
    String? keyPassphrase,
  }) {
    _entries.remove(sessionId)?.dispose();
    if ((password == null || password.isEmpty) &&
        (keyData == null || keyData.isEmpty) &&
        (keyPassphrase == null || keyPassphrase.isEmpty)) {
      return;
    }
    _entries[sessionId] = CachedCredentials._(
      password: _bufferFromString(password),
      keyData: _bufferFromString(keyData),
      keyPassphrase: _bufferFromString(keyPassphrase),
    );
  }

  /// Return the cached envelope for [sessionId] or null on cache miss.
  CachedCredentials? read(String sessionId) => _entries[sessionId];

  /// Evict one entry — wipes the backing SecretBuffers, then removes the
  /// map key. Safe to call with an unknown [sessionId] (no-op).
  void evict(String sessionId) {
    _entries.remove(sessionId)?.dispose();
  }

  /// Evict every entry. Used on app shutdown, wipe-all, and forgot-
  /// password reset. Disposes all buffers before clearing the map so a
  /// crash mid-iteration still frees the native memory.
  void evictAll() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }

  /// Current entry count — for diagnostics / tests only. Do not branch
  /// security-sensitive logic on this.
  int get size => _entries.length;

  static SecretBuffer? _bufferFromString(String? value) {
    if (value == null || value.isEmpty) return null;
    return SecretBuffer.fromBytes(utf8.encode(value));
  }
}

/// One session's auth envelope. All three slots are optional — auth can
/// be password-only, key-only, or key+passphrase.
class CachedCredentials {
  final SecretBuffer? password;
  final SecretBuffer? keyData;
  final SecretBuffer? keyPassphrase;
  bool _disposed = false;

  CachedCredentials._({this.password, this.keyData, this.keyPassphrase});

  /// UTF-8 decode the password slot, or null if absent.
  String? get passwordString => _decode(password);

  /// UTF-8 decode the key-data slot (raw PEM text), or null if absent.
  String? get keyDataString => _decode(keyData);

  /// UTF-8 decode the passphrase slot, or null if absent.
  String? get keyPassphraseString => _decode(keyPassphrase);

  /// Zero + munlock + free every slot. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    password?.dispose();
    keyData?.dispose();
    keyPassphrase?.dispose();
  }

  String? _decode(SecretBuffer? buffer) {
    if (buffer == null) return null;
    // Allocate a fresh Uint8List copy for utf8.decode — the SecretBuffer
    // view aliases native memory and would be invalidated if the caller
    // retained the decoded string past dispose(). Copying to a managed
    // list keeps the String independent of the buffer lifetime. The
    // managed copy is GC'd normally; we cannot zero it (String is
    // immutable in Dart), so the exposure window is narrow but not
    // zero — same caveat as Connection.cachedPassphrase.
    final view = buffer.bytes;
    final copy = Uint8List(view.length)..setAll(0, view);
    return utf8.decode(copy);
  }
}
