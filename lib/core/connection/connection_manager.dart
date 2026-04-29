import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/auth_compose.dart' as rust_auth;
import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/connection.dart' as rust_connection;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../security/session_credential_cache.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_config.dart';
import '../ssh/transport/ssh_transport.dart';
import 'connection.dart';
import 'connection_step.dart';
import 'connection_step_mappers.dart';

/// Manages active SSH connections lifecycle.
///
/// Tracks connections, associates them with tabs, notifies listeners.
/// Bus-driven per-connection state — transport adoption,
/// transient-secret eviction, progress fan-out — lives inside
/// the [Connection] class itself; the manager is the orchestrator
/// for the connect-attempt envelope (auth-overlay composition,
/// generation guarding, post-auth credential cache, extension
/// hook dispatch + the Dart-side Connection map the workspace UI
/// providers render against).
class ConnectionManager {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();

  /// Per-connection generation counter — prevents stale reconnect
  /// results. Routed through `lfs_core::connection::ConnectionRegistry`
  /// (FRB sync). FRB-unreachable contexts (flutter_test) swallow the
  /// throw silently — no test exercises a real connect lifecycle, so
  /// the generation guard is a no-op there.
  void _initGeneration(String id) {
    try {
      rust_connection.connectionInitGeneration(id: id);
    } catch (_) {}
  }

  int _bumpGeneration(String id) {
    try {
      return rust_connection.connectionBumpGeneration(id: id);
    } catch (_) {
      return 1;
    }
  }

  void _dropGeneration(String id) {
    try {
      rust_connection.connectionDropGeneration(id: id);
    } catch (_) {}
  }

  void _clearGenerations() {
    try {
      rust_connection.connectionClearGenerations();
    } catch (_) {}
  }

  final KnownHostsManager knownHosts;

  /// Page-locked per-session credential cache. Populated on successful
  /// auth; read by the reconnect path so `auto-lock` can close the
  /// encrypted store (which strips plaintext from `SessionStore.load`)
  /// without breaking active connections' reconnects. Nullable only for
  /// legacy constructor callers in tests that don't care about
  /// reconnect-after-lock. See [SessionCredentialCache].
  final SessionCredentialCache? _credentialCache;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  ConnectionManager({
    required this.knownHosts,
    SessionCredentialCache? credentialCache,
  }) : _credentialCache = credentialCache;

  /// User-visible connections. Excludes internal bastion hops the
  /// manager opens to back ProxyJump chains; those rides are owned
  /// by their parent connection and surface through it instead.
  List<Connection> get connections => [
    for (final c in _connections.values)
      if (!c.internal) c,
  ];

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

    // Connect through the Rust actor. Bus events stream the
    // handshake state changes back; once the actor reports
    // Connected we adopt the session into a `RustTransport`.
    _initGeneration(id);
    unawaited(_doConnect(conn, config, 1));
    return conn;
  }

  /// Dispatch the connect command to the Rust connection actor and
  /// mirror its bus events back onto the Dart `Connection` so the
  /// existing UI keeps observing the same `state` / `progressStream`
  /// / `connectionError` surface. Once the actor reports `Connected`
  /// the live `SshSession` is fetched via `connection_get_session`
  /// and adopted into a `RustTransport` for channel ops.
  Future<void> _doConnect(
    Connection conn,
    SSHConfig config,
    int generation,
  ) async {
    final effectiveConfig = _withCredentialOverlay(conn, config);
    final auth = await _authFromConfig(
      effectiveConfig.auth,
      conn.sessionId,
      conn,
    );

    // Bastion-readiness wait lives Rust-side now:
    // `lfs_core::connection::wait_for_parent_ready` subscribes to
    // the bus, snapshots the parent's current state, awaits the
    // next `ConnectionStateChanged` for the parent until it
    // settles into `Connected` (proceed) or `Disconnected`
    // (fail with a typed "ProxyJump parent failed" error). The
    // generation guard below still catches a stale-reconnect
    // overwrite if the user kicks a second connect mid-wait.
    //
    // The previous Dart `bastion!.waitUntilReady() + isConnected`
    // pair lives here as the test fallback only — flutter_test
    // contexts that don't load the FRB native lib never reach
    // the Rust connect path, so the in-memory `Connection`
    // bastion completer keeps tests passing without a fake
    // event-bus.
    if (conn.bastion != null) {
      final localBastion = conn.bastion!;
      // Best-effort — if the bastion future is already complete
      // this is a no-op; the Rust side will re-verify the parent
      // state when it actually runs the child connect.
      await localBastion.waitUntilReady();
      if (_isStaleGeneration(conn.id, generation)) return;
    }

    final rust_bus.BusConnectArgs args;
    try {
      args = busConnectArgs(conn, effectiveConfig, auth);
    } catch (e, st) {
      AppLogger.instance.log(
        'Bus connect args build failed: $e',
        name: 'Connection',
        error: e,
        stackTrace: st,
      );
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.connectionError = e;
        conn.state = SSHConnectionState.disconnected;
        conn.addProgressStep(
          ConnectionStep(
            phase: ConnectionPhase.socketConnect,
            status: StepStatus.failed,
            detail: e.toString(),
          ),
        );
        conn.completeReady();
        _notify();
      }
      return;
    }
    final sub = AppBus.instance
        .subscribeConnection(conn.id)
        .listen((event) => _applyConnectionEvent(conn, generation, event));

    conn.addProgressStep(
      const ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      ),
    );
    _notify();

    try {
      // Note: `connectionConnect` only returns once the actor has
      // settled into Connected or Disconnected — the bus events
      // arrive concurrently so the UI sees state transitions in
      // real time rather than at the resolve point.
      await rust_bus.connectionConnect(id: conn.id, args: args);
    } catch (e, st) {
      AppLogger.instance.log(
        'connectionConnect failed: $e',
        name: 'Connection',
        error: e,
        stackTrace: st,
      );
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.connectionError = e;
        conn.state = SSHConnectionState.disconnected;
      }
    } finally {
      await sub.cancel();
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.completeReady();
        // Cache post-auth credentials when the actor reached Connected.
        if (conn.state == SSHConnectionState.connected) {
          _cachePostAuthCredentials(conn, effectiveConfig);
        }
      }
      _notify();
    }
  }

  /// Translate a per-connection bus event into a Dart `Connection`
  /// state mutation. Stale-generation events are dropped.
  void _applyConnectionEvent(
    Connection conn,
    int generation,
    rust_bus.BusEvent event,
  ) {
    if (_isStaleGeneration(conn.id, generation)) return;
    switch (event) {
      case rust_bus.BusEvent_ConnectionStateChanged(:final state):
        switch (state) {
          case rust_bus.BusConnectionState.connecting:
            conn.state = SSHConnectionState.connecting;
          case rust_bus.BusConnectionState.connected:
            conn.state = SSHConnectionState.connected;
            AppLogger.instance.log(
              'Connected: ${conn.label} (id=${conn.id})',
              name: 'Connection',
            );
          // Transport adoption + transient-secret eviction
          // happen inside `Connection`'s own bus subscription
          // (it sees the same event).
          case rust_bus.BusConnectionState.disconnected:
            conn.state = SSHConnectionState.disconnected;
            AppLogger.instance.log(
              'Connection failed: ${conn.connectionError ?? "no error detail"}',
              name: 'Connection',
              level: LogLevel.warn,
              error: conn.connectionError,
            );
        }
      case rust_bus.BusEvent_ConnectionProgress(:final step):
        // Per-step append happens inside `Connection` via its
        // own bus subscription — nothing to do here for the
        // history fan-out. Failed-step logging stays here so
        // a support trace pins which connect attempt's Dart
        // listener saw the failure.
        if (step.status == rust_bus.BusStepStatus.failed) {
          AppLogger.instance.log(
            'Connect step failed: ${mapBusPhase(step.phase).name} '
            '— ${step.detail ?? "no detail"}',
            name: 'Connection',
            level: LogLevel.warn,
          );
        }
      case rust_bus.BusEvent_ConnectionError(:final detail):
        AppLogger.instance.log(
          'Connection actor error: $detail',
          name: 'Connection',
          level: LogLevel.warn,
        );
        conn.connectionError = detail;
      case rust_bus.BusEvent_ConnectionRemoved():
        // Actor torn down — leave Connection in its current state;
        // the manager's own `disconnect(id)` already removed the
        // Dart-side row.
        break;
      case _:
        break;
    }
    _notify();
  }

  // Transport adoption (`connection_get_session(id)` →
  // `RustTransport.adopt`) + the per-attempt transient-secret
  // eviction live inside `Connection`'s own bus subscription
  // since the relevant state is per-connection. The manager
  // only owns the connect-attempt orchestration: completer +
  // post-auth credential cache.

  // Phase / status / auth-ref / connect-args mapping lives in
  // `connection_step_mappers.dart` so the Connection class +
  // the manager share one canonical implementation.

  /// Connection timeout — applied inside the Rust actor.
  static const connectionTimeout = Duration(seconds: 30);

  /// Translate the legacy [SshAuth] config bag into the typed
  /// [SshAuthMethod] family the bus connect args carry.
  /// Precedence: keyData > password.
  ///
  /// Production routes through `lfs_core::connection::auth_compose::
  /// prepare_auth` (FRB async) so the saved-session-staged →
  /// manager-key-staged → quick-connect-fallback walk lives one
  /// place. The composer reads sqlite columns + stages every
  /// byte into the SecretStore inside Rust; the Dart caller
  /// only sees the typed ref + the transient id list to drop
  /// after the connect attempt settles.
  ///
  /// FRB-unreachable contexts (flutter_test) propagate the throw —
  /// every secret-staging path below is itself a FRB call, so the
  /// previous "Dart fallback" pipeline collapsed to the same failure
  /// the orchestrator surfaces directly.
  Future<SshAuthMethod> _authFromConfig(
    SshAuth auth,
    String? sessionId,
    Connection conn,
  ) async {
    final prepared = await rust_auth.connectionPrepareAuth(
      input: rust_auth.DbPrepareAuthInput(
        sessionId: sessionId,
        keyId: auth.keyId,
        keyData: auth.keyData,
        password: auth.password,
        passphrase: auth.passphrase,
      ),
    );
    conn.transientSecretIds.addAll(prepared.transientSecretIds);
    switch (prepared.kind) {
      case 'password':
        return SshAuthPasswordRef(prepared.primarySecretId);
      case 'pubkey':
        return SshAuthPubkeyRef(
          prepared.primarySecretId,
          passphraseSecretId: prepared.passphraseSecretId,
        );
      default:
        throw StateError(
          'connection_prepare_auth returned unknown kind "${prepared.kind}"',
        );
    }
  }

  /// Overlay [Connection.cachedPassphrase] onto [config] when set —
  /// populated on interactive passphrase prompts with the "remember"
  /// box ticked. Applied only when the config does not already carry
  /// a passphrase, so an explicitly-passed value wins. Kept so the
  /// "remember for this session" UX still works for one-off keys that
  /// are not in the session store.
  ///
  /// The wider `SessionCredentialCache` overlay used to live here too,
  /// but the cache stopped serving plaintext to the Dart heap (every
  /// `read*` accessor returned null) once `SecretStore` became the
  /// canonical store, so the overlay collapsed to a no-op and was
  /// retired. The eventual `connect_*_with_secret` connect variant
  /// will resolve the cached bytes Rust-side instead.
  SSHConfig _withCredentialOverlay(Connection conn, SSHConfig config) {
    final cached = conn.cachedPassphrase;
    if (cached == null || config.auth.passphrase.isNotEmpty) return config;
    return config.copyWith(auth: config.auth.copyWith(passphrase: cached));
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

  // Per-attempt transient-secret eviction lives inside
  // `Connection` — the connect-path's terminal-state bus event
  // drives it, and `Connection.dispose()` belt-and-braces
  // covers the disconnect race where the bus event might miss
  // a freshly-cancelled subscription.

  /// Whether a newer reconnect generation has superseded [generation].
  /// Routes through the Rust registry; FRB-unreachable contexts
  /// (flutter_test) treat every generation as current so the
  /// reconnect path doesn't short-circuit on the no-op stub.
  bool _isStaleGeneration(String id, int generation) {
    try {
      return !rust_connection.connectionIsCurrentGeneration(
        id: id,
        generation: generation,
      );
    } catch (_) {
      return false;
    }
  }

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

    final gen = _bumpGeneration(id);
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
    // Per-attempt transient secrets are evicted by
    // `Connection.dispose()` below (covers the explicit
    // disconnect race against the bus event path).
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
    // Dispatch the actor-side teardown so the russh handle is
    // dropped and the registry row cleared. Adopted transports'
    // `disconnect()` is a no-op (the `RustTransport.adopt` flag) —
    // the actor is the lifecycle owner.
    unawaited(
      AppBus.instance
          .dispatch(rust_bus.BusCommand.connectionDisconnect(id: id))
          .catchError((Object e) {
            AppLogger.instance.log(
              'Bus disconnect dispatch failed',
              name: 'Connection',
              error: e,
            );
          }),
    );
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
    _dropGeneration(id);
    // Cascade-disconnect the bastion this connection rode on.
    final bastion = conn.bastion;
    if (bastion != null) {
      disconnect(bastion.id);
    }
    // Tear down Connection's persistent resources (bus
    // subscription + progress controller) now that it's
    // no longer reachable through the manager's map.
    conn.dispose();
    _notify();
  }

  /// Disconnect all connections.
  ///
  /// Completes pending [Connection.ready] futures so callers are not left
  /// hanging, then clears the connection map.
  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.notifyExtensionsDisconnecting();
      // Transient eviction folded into `Connection.dispose()`
      // below.
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
      // Persistent bus subscription + progress controller —
      // both teardowns must fire here too, otherwise wholesale
      // disconnect leaves a fan-out of zombie listeners.
      conn.dispose();
    }
    _connections.clear();
    _clearGenerations();
    _notify();
  }

  /// Notify listeners that connection state changed externally.
  ///
  /// Called when a [Connection] object's state is mutated directly (e.g. by
  /// terminal pane on shell error). Prefer [_notify] for internal state
  /// changes — this is the public equivalent for external callers.
  void notifyStateChanged() => _notify();

  bool _disposed = false;

  void _notify() {
    if (!_disposed) {
      _controller.add(null);
    }
  }

  void dispose() {
    disconnectAll();
    _disposed = true;
    _controller.close();
  }
}
