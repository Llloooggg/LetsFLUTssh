import 'dart:async';

import 'package:dartssh2/dartssh2.dart' show SSHSocket;
import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../security/session_credential_cache.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';
import 'connection.dart';

/// Factory for creating SSH connections — injectable for testing.
typedef SSHConnectionFactory =
    SSHConnection Function(SSHConfig config, KnownHostsManager knownHosts);

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
  final SSHConnectionFactory _connectionFactory;

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
  /// Set by the UI layer (main.dart) — same pattern as host key callbacks.
  PassphrasePromptCallback? onPassphraseRequired;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  ConnectionManager({
    required this.knownHosts,
    SSHConnectionFactory? connectionFactory,
    SessionCredentialCache? credentialCache,
    this.onActiveCountChanged,
  }) : _credentialCache = credentialCache,
       _connectionFactory =
           connectionFactory ??
           ((config, kh) => SSHConnection(config: config, knownHosts: kh));

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
    Future<SSHSocket> Function()? socketProvider,
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
      socketProvider: socketProvider,
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
    final effectiveConfig = _withCredentialOverlay(conn, config);
    final sshConn = _connectionFactory(effectiveConfig, knownHosts);
    // Identity-guarded callback. A stale generation path (timeout,
    // superseded reconnect, mid-connect error) still calls
    // `sshConn.disconnect()` on the old transport to release the
    // socket, which fires this callback. Without the guard the old
    // callback would clobber `conn.sshConnection`/`conn.state` even
    // after a newer generation had already assigned its own transport
    // into the shared Connection — flipping the UI to "disconnected"
    // while the new connection was in fact live.
    sshConn.onDisconnect = () {
      if (conn.sshConnection != sshConn) return;
      conn.state = SSHConnectionState.disconnected;
      conn.sshConnection = null;
      _notify();
    };
    _wirePassphrasePrompt(sshConn, conn);

    try {
      await sshConn
          .connect(
            onProgress: (step) => conn.addProgressStep(step),
            socketProvider: conn.socketProvider,
          )
          .timeout(connectionTimeout);

      // Check if a newer reconnect has started while we were connecting.
      if (_isStaleGeneration(conn.id, generation)) {
        sshConn.disconnect();
        return;
      }

      conn.sshConnection = sshConn;
      conn.state = SSHConnectionState.connected;
      _cachePostAuthCredentials(conn, effectiveConfig);
      // Fire after the transport is fully wired so extensions can dial
      // into `conn.sshConnection!.client` without a null-guard race
      // window. Hook failures are caught inside the fan-out — one
      // broken extension never blocks the connect or the others.
      conn.notifyExtensionsConnected();
      AppLogger.instance.log(
        'Connected: <label> (id=${conn.id})',
        name: 'Connection',
      );
    } on TimeoutException {
      if (_isStaleGeneration(conn.id, generation)) {
        sshConn.disconnect();
        return;
      }
      _handleConnectionFailure(
        conn,
        sshConn,
        TimeoutException('Connection timed out', connectionTimeout),
        'Connection timed out after ${connectionTimeout.inSeconds}s',
      );
    } catch (e) {
      if (_isStaleGeneration(conn.id, generation)) {
        sshConn.disconnect();
        return;
      }
      _handleConnectionFailure(conn, sshConn, e, 'Connection failed: $e');
    } finally {
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.completeReady();
      }
      _notify();
    }
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
  SSHConfig _withCredentialOverlay(Connection conn, SSHConfig config) {
    var auth = config.auth;
    auth = _overlaySessionCache(auth, conn.sessionId);
    if (auth.passphrase.isEmpty && conn.cachedPassphrase != null) {
      auth = auth.copyWith(passphrase: conn.cachedPassphrase);
    }
    return identical(auth, config.auth) ? config : config.copyWith(auth: auth);
  }

  /// Merge any password / key / passphrase entries the
  /// [SessionCredentialCache] holds for [sessionId] into [auth],
  /// overwriting empty fields only. Pulled out of
  /// [_withCredentialOverlay] so each nested "cache present AND
  /// entry present AND this field empty AND cached value non-null"
  /// guard pair stops inflating the outer method's cognitive
  /// complexity.
  SshAuth _overlaySessionCache(SshAuth auth, String? sessionId) {
    final cache = _credentialCache;
    if (sessionId == null || cache == null) return auth;
    final cached = cache.read(sessionId);
    if (cached == null) return auth;
    var merged = auth;
    if (merged.password.isEmpty && cached.passwordString != null) {
      merged = merged.copyWith(password: cached.passwordString);
    }
    if (merged.keyData.isEmpty && cached.keyDataString != null) {
      merged = merged.copyWith(keyData: cached.keyDataString);
    }
    if (merged.passphrase.isEmpty && cached.keyPassphraseString != null) {
      merged = merged.copyWith(passphrase: cached.keyPassphraseString);
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
    cache.store(
      sessionId: sessionId,
      password: config.auth.password.isEmpty ? null : config.auth.password,
      keyData: config.auth.keyData.isEmpty ? null : config.auth.keyData,
      keyPassphrase: config.auth.passphrase.isEmpty
          ? null
          : config.auth.passphrase,
    );
  }

  /// Wire interactive passphrase prompt if the UI layer provided one.
  void _wirePassphrasePrompt(SSHConnection sshConn, Connection conn) {
    if (onPassphraseRequired == null) return;
    sshConn.onPassphraseRequired = (host, attempt) async {
      final result = await onPassphraseRequired!(host, attempt);
      if (result == null) return null;
      if (result.remember) conn.cachedPassphrase = result.passphrase;
      return result.passphrase;
    };
  }

  /// Whether a newer reconnect generation has superseded [generation].
  bool _isStaleGeneration(String id, int generation) =>
      _connectGeneration[id] != generation;

  /// Log the error, disconnect, and mark the connection as failed.
  void _handleConnectionFailure(
    Connection conn,
    SSHConnection sshConn,
    Object error,
    String logMessage,
  ) {
    AppLogger.instance.log(logMessage, name: 'Connection', error: error);
    sshConn.disconnect();
    conn.state = SSHConnectionState.disconnected;
    conn.connectionError = error;
  }

  /// Reconnect an existing connection.
  ///
  /// Resets progress stream, disconnects old SSH, and runs a fresh
  /// connection attempt in the background — same as [connectAsync] but
  /// reuses the existing [Connection] object so all tabs see the update.
  void reconnect(String id, {SSHConfig? updatedConfig}) {
    final conn = _connections[id];
    if (conn == null) return;

    // Tear down old SSH connection. Notify extensions BEFORE we drop
    // the transport — port forwards / recording sinks need the live
    // SSHClient to close their channels cleanly.
    conn.notifyExtensionsDisconnecting();
    conn.sshConnection?.disconnect();
    conn.sshConnection = null;

    // Apply updated config if provided (e.g. session was edited)
    if (updatedConfig != null) conn.sshConfig = updatedConfig;

    // Reset for fresh progress
    conn.resetForReconnect();
    // Extensions reset transient state (channel handles, in-flight
    // futures) but keep persistent config — a forward rule list
    // survives, the live channels do not.
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
    conn.sshConnection?.disconnect();
    conn.state = SSHConnectionState.disconnected;
    conn.sshConnection = null;
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
      _credentialCache?.evict(sessionId);
    }
    _connections.remove(id);
    _connectGeneration.remove(id);
    // Cascade-disconnect the bastion this connection rode on. The
    // bastion was created internally and is unreachable from any
    // other UI surface, so leaving it behind would leak both the
    // socket and the keepalive timer. Done after the parent's
    // cleanup so the parent doesn't try to forwardLocal a dying
    // channel during its final flush.
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
      conn.sshConnection?.disconnect();
      conn.completeReady();
      conn.clearCachedCredentials();
      final sessionId = conn.sessionId;
      if (sessionId != null) {
        _credentialCache?.evict(sessionId);
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
