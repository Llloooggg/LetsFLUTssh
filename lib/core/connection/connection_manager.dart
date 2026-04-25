import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/app.dart' as rust_app;
import '../../utils/logger.dart';
import '../security/session_credential_cache.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_config.dart';
import '../ssh/transport/rust_transport.dart';
import '../ssh/transport/ssh_transport.dart';
import '../ssh/transport/transport_factory.dart';
import 'connection.dart';

/// Optional callback invoked when the number of active (connected) sessions changes.
typedef ActiveCountCallback = void Function(int activeCount);

/// Callback for interactive passphrase prompts — set by the UI layer.
typedef PassphrasePromptCallback =
    Future<({String passphrase, bool remember})?> Function(
      String host,
      int attempt,
    );

/// Manages active SSH connections lifecycle.
///
/// Tracks connections, associates them with tabs, notifies listeners.
class ConnectionManager {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();

  /// Per-connection generation counter — prevents stale reconnect results.
  final _connectGeneration = <String, int>{};
  final KnownHostsManager knownHosts;

  /// Page-locked per-session credential cache. Populated on successful
  /// auth; read by the reconnect path so `auto-lock` can close the
  /// encrypted store (which strips plaintext from `SessionStore.load`)
  /// without breaking active connections' reconnects. Nullable only for
  /// legacy constructor callers in tests that don't care about
  /// reconnect-after-lock. See [SessionCredentialCache].
  final SessionCredentialCache? _credentialCache;

  /// Called whenever the number of *connected* sessions changes.
  /// Used by [ForegroundServiceManager] on Android to start/stop the service.
  ActiveCountCallback? onActiveCountChanged;

  /// Called when an encrypted SSH key needs a passphrase interactively.
  /// Reserved for the upcoming Rust-side passphrase callback hook —
  /// today it stays unwired (the Rust transport returns
  /// `PassphraseIncorrect` / `PassphraseRequired` errors rather than
  /// prompting mid-handshake).
  PassphrasePromptCallback? onPassphraseRequired;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  /// Optional override of the SSH transport factory — useful in tests
  /// to inject a mock SshTransport without touching the global factory.
  /// In production stays null and `createSshTransport()` is used.
  final SshTransport Function(KnownHostsManager)? _transportFactory;

  ConnectionManager({
    required this.knownHosts,
    SessionCredentialCache? credentialCache,
    this.onActiveCountChanged,
    SshTransport Function(KnownHostsManager)? transportFactory,
  }) : _credentialCache = credentialCache,
       _transportFactory = transportFactory;

  /// User-visible connections. Excludes internal bastion hops the
  /// manager opens to back ProxyJump chains; those rides are owned
  /// by their parent connection and surface through it instead.
  List<Connection> get connections => [
    for (final c in _connections.values)
      if (!c.internal) c,
  ];

  /// Every connection including internal bastion hops — used by the
  /// foreground-service active-count callback so a long-running
  /// bastion still keeps the Android service alive.
  List<Connection> get allConnections => _connections.values.toList();

  Connection? get(String id) => _connections[id];

  /// Create a connection and start connecting in the background.
  /// Returns the Connection immediately (in `connecting` state).
  /// The connection transitions to `connected` or `disconnected` asynchronously.
  Connection connectAsync(
    SSHConfig config, {
    String? label,
    String? sessionId,
    Connection? bastion,
    bool internal = false,
  }) {
    final id = _uuid.v4();
    final conn = Connection(
      id: id,
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
      knownHosts: knownHosts,
      state: SSHConnectionState.connecting,
      bastion: bastion,
      internal: internal,
    );
    _connections[id] = conn;
    _notify();
    // Full structure is preserved on purpose — AppLogger.sanitize
    // turns it into `Connecting to <host>:<port> as <user>` when the
    // file is written, so the diagnostic signal ("we tried to auth
    // with a user") stays readable without leaking the actual
    // username or hostname.
    AppLogger.instance.log(
      'Connecting to ${config.host}:${config.port} as ${config.user}',
      name: 'Connection',
    );

    // Start connection in background
    _connectGeneration[id] = 1;
    _doConnect(conn, config, 1);
    return conn;
  }

  /// Connection timeout — applied at the transport level, not in UI.
  static const connectionTimeout = Duration(seconds: 30);

  /// Background connection logic.
  ///
  /// [generation] is a per-connection counter that prevents stale results
  /// from a previous reconnect attempt overwriting a newer one.
  Future<void> _doConnect(
    Connection conn,
    SSHConfig config,
    int generation,
  ) async {
    final effectiveConfig = await _withCredentialOverlay(conn, config);
    final transport =
        _transportFactory?.call(knownHosts) ??
        createSshTransport(knownHosts: knownHosts);
    final auth = await _authFromConfig(effectiveConfig.auth, conn.sessionId);
    final request = SshConnectRequest(
      host: effectiveConfig.host,
      port: effectiveConfig.port,
      user: effectiveConfig.user,
      auth: auth,
      inactivityTimeout: Duration(seconds: effectiveConfig.timeoutSec),
    );
    try {
      // ProxyJump dispatch: if `conn.bastion` carries a live Rust
      // transport, tunnel this hop's handshake through it via
      // `connectViaProxy`. Waiting on `bastion.waitUntilReady()`
      // closes the race where the parent's auth must finish before
      // the child reaches for the channel primitive.
      final parentTransport = await _resolveParentRustTransport(conn.bastion);
      if (parentTransport != null && transport is RustTransport) {
        await transport
            .connectViaProxy(parentTransport, request)
            .timeout(connectionTimeout);
      } else {
        await transport.connect(request).timeout(connectionTimeout);
      }
      if (_isStaleGeneration(conn.id, generation)) {
        await transport.disconnect();
        return;
      }
      conn.transport = transport;
      conn.state = SSHConnectionState.connected;
      _cachePostAuthCredentials(conn, effectiveConfig);
      conn.notifyExtensionsConnected();
      AppLogger.instance.log(
        'Connected: <label> (id=${conn.id})',
        name: 'Connection',
      );
    } on TimeoutException {
      if (_isStaleGeneration(conn.id, generation)) {
        await transport.disconnect();
        return;
      }
      conn.connectionError = TimeoutException(
        'Connection timed out',
        connectionTimeout,
      );
      conn.state = SSHConnectionState.disconnected;
      AppLogger.instance.log('Connection failed: timeout', name: 'Connection');
    } catch (e) {
      if (_isStaleGeneration(conn.id, generation)) {
        await transport.disconnect();
        return;
      }
      conn.connectionError = e;
      conn.state = SSHConnectionState.disconnected;
      AppLogger.instance.log(
        'Connection failed: $e',
        name: 'Connection',
        error: e,
      );
    } finally {
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.completeReady();
      }
      _notify();
    }
  }

  /// Wait for [bastion] to finish auth and pull its `RustTransport`
  /// out, ready to use as the parent of a `connectViaProxy` call.
  Future<RustTransport?> _resolveParentRustTransport(
    Connection? bastion,
  ) async {
    if (bastion == null) return null;
    await bastion.waitUntilReady();
    if (!bastion.isConnected) return null;
    final t = bastion.transport;
    return t is RustTransport ? t : null;
  }

  /// Translate the legacy [SshAuth] config bag into the typed
  /// [SshAuthMethod] family that [SshConnectRequest] uses.
  /// Precedence: keyData > password.
  ///
  /// When the connection has a stable [sessionId] we stash plaintext
  /// into the Rust SecretStore and emit the `*Ref` variant so the
  /// russh handshake reads bytes from Rust-side rather than receiving
  /// them through FRB. Quick-connect (no sessionId) keeps the
  /// plaintext variant as a fallback — switching that path onto a
  /// per-connection ephemeral ID is a follow-up.
  Future<SshAuthMethod> _authFromConfig(SshAuth auth, String? sessionId) async {
    if (sessionId != null) {
      if (auth.keyData.isNotEmpty) {
        final keyId = 'sess.key.$sessionId';
        await rust_app.secretsPut(
          id: keyId,
          bytes: Uint8List.fromList(auth.keyData.codeUnits),
        );
        String? passphraseId;
        if (auth.passphrase.isNotEmpty) {
          passphraseId = 'sess.passphrase.$sessionId';
          await rust_app.secretsPut(
            id: passphraseId,
            bytes: Uint8List.fromList(utf8.encode(auth.passphrase)),
          );
        }
        return SshAuthPubkeyRef(keyId, passphraseSecretId: passphraseId);
      }
      if (auth.password.isNotEmpty) {
        final id = 'sess.password.$sessionId';
        await rust_app.secretsPut(
          id: id,
          bytes: Uint8List.fromList(utf8.encode(auth.password)),
        );
        return SshAuthPasswordRef(id);
      }
    }
    if (auth.keyData.isNotEmpty) {
      return SshAuthPubkey(
        Uint8List.fromList(auth.keyData.codeUnits),
        passphrase: auth.passphrase.isEmpty ? null : auth.passphrase,
      );
    }
    return SshAuthPassword(auth.password);
  }

  /// Overlay credentials onto [config] from two defensive sources, in
  /// order of precedence:
  ///   1. [SessionCredentialCache] — page-locked copies kept alive across
  ///      auto-lock, so a reconnect issued while the encrypted store is
  ///      closed (see `AutoLockDetector`) still sees the user's password,
  ///      key bytes, and passphrase. Applied only when the session has a
  ///      stable id — quick-connect sessions have nothing to key on.
  ///   2. [Connection.cachedPassphrase] — populated on interactive
  ///      passphrase prompts with the "remember" box ticked. Strictly
  ///      narrower than the session cache; applied only when neither the
  ///      config nor the session cache carry a passphrase. Kept so the
  ///      "remember for this session" UX still works for one-off keys
  ///      that aren't in the session store.
  Future<SSHConfig> _withCredentialOverlay(
    Connection conn,
    SSHConfig config,
  ) async {
    var auth = config.auth;
    auth = await _overlaySessionCache(auth, conn.sessionId);
    if (auth.passphrase.isEmpty && conn.cachedPassphrase != null) {
      auth = auth.copyWith(passphrase: conn.cachedPassphrase);
    }
    return identical(auth, config.auth) ? config : config.copyWith(auth: auth);
  }

  /// Merge any password / key / passphrase entries the
  /// [SessionCredentialCache] holds for [sessionId] into [auth],
  /// overwriting empty fields only. The cache no longer serves
  /// plaintext to the Dart heap — read accessors return null — so
  /// the overlay is currently a no-op. It stays in place because the
  /// connect path will later resolve bytes Rust-side via a
  /// `connect_*_with_secret` variant; at that point the overlay is
  /// the right layering point to re-introduce.
  Future<SshAuth> _overlaySessionCache(SshAuth auth, String? sessionId) async {
    final cache = _credentialCache;
    if (sessionId == null || cache == null) return auth;
    final cached = cache.read(sessionId);
    if (cached == null) return auth;
    var merged = auth;
    if (merged.password.isEmpty) {
      final cachedPassword = await cached.readPassword();
      if (cachedPassword != null) {
        merged = merged.copyWith(password: cachedPassword);
      }
    }
    if (merged.keyData.isEmpty) {
      final cachedKey = await cached.readKeyData();
      if (cachedKey != null) {
        merged = merged.copyWith(keyData: cachedKey);
      }
    }
    if (merged.passphrase.isEmpty) {
      final cachedPassphrase = await cached.readKeyPassphrase();
      if (cachedPassphrase != null) {
        merged = merged.copyWith(passphrase: cachedPassphrase);
      }
    }
    return merged;
  }

  /// Store the post-auth credential envelope so a later reconnect
  /// (possibly after auto-lock closed the encrypted store) does not
  /// need to re-read `Session.auth`. Cache writes only happen for
  /// stored sessions — quick-connect has no stable key, and the next
  /// `reconnect` call already carries the full config.
  void _cachePostAuthCredentials(Connection conn, SSHConfig config) {
    final cache = _credentialCache;
    final sessionId = conn.sessionId;
    if (cache == null || sessionId == null) return;
    // Fire-and-forget — store() is async (FRB call); the rest of
    // the connect path doesn't need to wait for the cache to land.
    unawaited(
      cache.store(
        sessionId: sessionId,
        password: config.auth.password.isEmpty ? null : config.auth.password,
        keyData: config.auth.keyData.isEmpty ? null : config.auth.keyData,
        keyPassphrase: config.auth.passphrase.isEmpty
            ? null
            : config.auth.passphrase,
      ),
    );
  }

  /// Whether a newer reconnect generation has superseded [generation].
  bool _isStaleGeneration(String id, int generation) =>
      _connectGeneration[id] != generation;

  /// Reconnect an existing connection.
  ///
  /// Resets progress stream, disconnects old transport, and runs a fresh
  /// connection attempt in the background — same as [connectAsync] but
  /// reuses the existing [Connection] object so all tabs see the update.
  void reconnect(String id, {SSHConfig? updatedConfig}) {
    final conn = _connections[id];
    if (conn == null) return;

    // Tear down old transport. Notify extensions BEFORE we drop the
    // transport — port forwards / recording sinks need the live
    // transport to close their channels cleanly.
    conn.notifyExtensionsDisconnecting();
    final oldTransport = conn.transport;
    conn.transport = null;
    if (oldTransport != null) {
      // Best-effort — fire-and-forget so reconnect doesn't await tear-down.
      unawaited(
        oldTransport.disconnect().catchError((Object e) {
          AppLogger.instance.log(
            'Failed to disconnect old transport',
            name: 'Connection',
            error: e,
          );
        }),
      );
    }

    if (updatedConfig != null) conn.sshConfig = updatedConfig;

    conn.resetForReconnect();
    conn.notifyExtensionsReconnecting();
    conn.state = SSHConnectionState.connecting;
    _notify();

    AppLogger.instance.log(
      'Reconnecting to ${conn.sshConfig.host}:${conn.sshConfig.port} '
      'as ${conn.sshConfig.user}',
      name: 'Connection',
    );

    final gen = (_connectGeneration[id] ?? 0) + 1;
    _connectGeneration[id] = gen;
    _doConnect(conn, conn.sshConfig, gen);
  }

  /// Disconnect a specific connection.
  void disconnect(String id) {
    final conn = _connections[id];
    if (conn == null) return;
    AppLogger.instance.log(
      'Disconnected: <label> (id=${conn.id})',
      name: 'Connection',
    );
    conn.notifyExtensionsDisconnecting();
    final transport = conn.transport;
    conn.transport = null;
    conn.state = SSHConnectionState.disconnected;
    if (transport != null) {
      unawaited(
        transport.disconnect().catchError((Object e) {
          AppLogger.instance.log(
            'Failed to disconnect transport',
            name: 'Connection',
            error: e,
          );
        }),
      );
    }
    // Drop the cached passphrase BEFORE losing the Connection reference
    // so the GC can reclaim the String once our map stops pinning it.
    conn.clearCachedCredentials();
    // Explicit disconnect is the signal that the user is done with the
    // session — wipe the session-wide credential cache entry so the
    // plaintext does not linger in mlock'd memory across a later
    // reconnect-from-scratch. Auto-lock does NOT go through this path
    // (it never calls `disconnect`), so active sessions retain their
    // cache entries through a lock.
    final sessionId = conn.sessionId;
    if (sessionId != null) {
      // Fire-and-forget — evict() is async (FRB drop calls).
      unawaited(
        _credentialCache?.evict(sessionId).catchError((Object _) {}) ??
            Future<void>.value(),
      );
    }
    _connections.remove(id);
    _connectGeneration.remove(id);
    // Cascade-disconnect the bastion this connection rode on.
    final bastion = conn.bastion;
    if (bastion != null) {
      disconnect(bastion.id);
    }
    _notify();
  }

  /// Disconnect all connections.
  ///
  /// Completes pending [Connection.ready] futures so callers are not left
  /// hanging, then clears the connection map.
  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.notifyExtensionsDisconnecting();
      final transport = conn.transport;
      conn.transport = null;
      if (transport != null) {
        unawaited(transport.disconnect().catchError((Object _) {}));
      }
      conn.completeReady();
      conn.clearCachedCredentials();
      final sessionId = conn.sessionId;
      if (sessionId != null) {
        unawaited(
          _credentialCache?.evict(sessionId).catchError((Object _) {}) ??
              Future<void>.value(),
        );
      }
    }
    _connections.clear();
    _connectGeneration.clear();
    _notify();
  }

  /// Notify listeners that connection state changed externally.
  ///
  /// Called when a [Connection] object's state is mutated directly (e.g. by
  /// terminal pane on shell error). Prefer [_notify] for internal state
  /// changes — this is the public equivalent for external callers.
  void notifyStateChanged() => _notify();

  bool _disposed = false;

  int _lastActiveCount = 0;

  void _notify() {
    if (!_disposed) {
      _controller.add(null);
      _notifyActiveCount();
    }
  }

  void _notifyActiveCount() {
    final count = _connections.values
        .where((c) => c.state == SSHConnectionState.connected)
        .length;
    if (count != _lastActiveCount) {
      _lastActiveCount = count;
      onActiveCountChanged?.call(count);
    }
  }

  void dispose() {
    disconnectAll();
    _disposed = true;
    _controller.close();
  }
}
