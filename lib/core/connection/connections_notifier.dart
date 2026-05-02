import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../providers/session_credential_cache_provider.dart';
import '../../src/rust/api/auth_compose.dart' as rust_auth;
import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/connection.dart' as rust_connection;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../security/session_credential_cache.dart';
import '../ssh/ssh_config.dart';
import '../ssh/transport/ssh_transport.dart';
import 'connection.dart';
import 'connection_step.dart';
import 'connection_step_mappers.dart';

/// Active SSH connections — Riverpod-native [Notifier] that owns
/// the in-memory `Connection` map + connect/reconnect/disconnect
/// orchestration.
///
/// `state` is the user-visible list (excludes internal bastion
/// hops the orchestrator opens for ProxyJump chains). Mutations
/// rebuild the list via `_notify()`; the Rust connection
/// registry's bus events also rebuild on every state transition
/// the workspace UI cares about.
///
/// Connection-class responsibilities (transport adoption,
/// transient-secret eviction, progress fan-out) live inside the
/// [Connection] class itself via its own per-id bus subscription.
/// This Notifier owns the connect-attempt envelope:
/// auth-overlay composition, generation guarding, post-auth
/// credential cache, extension hook dispatch, and the Dart-side
/// Connection map the workspace UI providers render against.
///
/// Consumers:
///   - `ref.watch(connectionsProvider)` — live `List<Connection>`
///   - `ref.read(connectionsProvider.notifier).connectAsync(...)` —
///     start a new connection
///   - `ref.read(connectionsProvider.notifier).disconnect(id)` —
///     tear one down
class ConnectionsNotifier extends Notifier<List<Connection>> {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();
  SessionCredentialCache? _credentialCache;
  bool _disposed = false;

  @override
  List<Connection> build() {
    _credentialCache = ref.watch(sessionCredentialCacheProvider);
    StreamSubscription<rust_bus.BusEvent>? busSub;
    // FRB-unreachable contexts (flutter_test) skip the bus
    // subscription. The Notifier's own mutations (connectAsync /
    // disconnect / reconnect / notifyStateChanged) drive every
    // Dart-test rebuild without it.
    try {
      busSub = AppBus.instance
          .subscribe(rust_bus.BusTopic.connection)
          .listen((_) => _notify());
    } catch (_) {}
    ref.onDispose(() {
      _disposed = true;
      if (busSub != null) unawaited(busSub.cancel());
      _disconnectAll();
    });
    return const [];
  }

  // ── Generation counter (Rust-backed) ──────────────────────────

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

  /// Whether a newer reconnect generation has superseded
  /// [generation]. Routes through the Rust registry; FRB-unreachable
  /// contexts (flutter_test) treat every generation as current so
  /// the reconnect path doesn't short-circuit on the no-op stub.
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

  // ── Public read surface ───────────────────────────────────────

  /// User-visible connections. Excludes internal bastion hops the
  /// orchestrator opens to back ProxyJump chains; those rides are
  /// owned by their parent connection and surface through it
  /// instead.
  List<Connection> get connections => [
    for (final c in _connections.values)
      if (!c.internal) c,
  ];

  /// Lookup a connection by id (includes internal bastion hops —
  /// the workspace UI never asks for one of those, but the
  /// `_doConnect` cascade does for ProxyJump parent resolution).
  Connection? get(String id) => _connections[id];

  // ── Connect / reconnect / disconnect ──────────────────────────

  /// Create a connection and start connecting in the background.
  /// Returns the Connection immediately (in `connecting` state).
  /// The connection transitions to `connected` or `disconnected`
  /// asynchronously through the Rust connection actor + bus.
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
      state: SSHConnectionState.connecting,
      bastion: bastion,
      internal: internal,
    );
    _connections[id] = conn;
    _notify();
    // Full structure is preserved on purpose — AppLogger.sanitize
    // turns it into `Connecting to <host>:<port> as <user>` when
    // the file is written, so the diagnostic signal stays
    // readable without leaking the actual hostname.
    AppLogger.instance.log(
      'Connecting to ${config.host}:${config.port} as ${config.user}',
      name: 'Connection',
    );

    _initGeneration(id);
    unawaited(_doConnect(conn, config, 1));
    return conn;
  }

  /// Reconnect an existing connection.
  ///
  /// Resets progress stream, disconnects old transport, and runs a
  /// fresh connection attempt in the background — same as
  /// [connectAsync] but reuses the existing [Connection] object so
  /// all tabs see the update.
  void reconnect(String id, {SSHConfig? updatedConfig}) {
    final conn = _connections[id];
    if (conn == null) return;

    // Tear down old transport. Notify extensions BEFORE we drop
    // the transport — port forwards / recording sinks need the
    // live transport to close their channels cleanly.
    conn.notifyExtensionsDisconnecting();
    final oldTransport = conn.transport;
    conn.transport = null;
    if (oldTransport != null) {
      // Best-effort — fire-and-forget so reconnect doesn't await
      // tear-down.
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
    // Drop the cached passphrase BEFORE losing the Connection
    // reference so the GC can reclaim the String once our map
    // stops pinning it.
    conn.clearCachedCredentials();
    // Explicit disconnect = the user is done with the session.
    // Wipe the session-wide credential cache entry so the
    // plaintext does not linger in mlock'd memory across a
    // later reconnect-from-scratch. Auto-lock does NOT go
    // through this path (it never calls `disconnect`), so
    // active sessions retain their cache entries through a
    // lock.
    final sessionId = conn.sessionId;
    if (sessionId != null) {
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
    // subscription + progress controller) now that it's no
    // longer reachable through the map.
    conn.dispose();
    _notify();
  }

  /// Disconnect all connections — used by the Notifier disposal
  /// path so a teardown (test container.dispose, hot-reload)
  /// doesn't leak russh sessions / bus subscriptions.
  void _disconnectAll() {
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
      conn.dispose();
    }
    _connections.clear();
    _clearGenerations();
  }

  /// Notify listeners that connection state changed externally.
  ///
  /// Called when a [Connection] object's state is mutated directly
  /// (e.g. by terminal pane on shell error). Prefer the internal
  /// `_notify()` for in-Notifier mutations — this is the public
  /// equivalent for external callers.
  void notifyStateChanged() => _notify();

  /// Internal — rebuild [state] from the connection map. The
  /// `if (!_disposed)` guard catches the post-dispose race where
  /// a fire-and-forget transport teardown's catchError fires
  /// after the Notifier is gone.
  void _notify() {
    if (_disposed) return;
    state = connections;
  }

  // ── Connect orchestration (private) ───────────────────────────

  /// Dispatch the connect command to the Rust connection actor
  /// and mirror its bus events back onto the Dart `Connection` so
  /// the existing UI keeps observing the same `state` /
  /// `progressStream` / `connectionError` surface. Once the actor
  /// reports `Connected` the live `SshSession` is fetched via
  /// `connection_get_session` and adopted into a `RustTransport`
  /// for channel ops (handled inside [Connection]'s own bus
  /// subscription, not here).
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

    // No manual `socketConnect: inProgress` emit here — `connect_async`
    // in `lfs_core::connection::run_connect_driver` publishes the same
    // step on the bus as its first action, and Connection's permanent
    // `_busSub` forwards it into the per-connection progress stream.
    // Doing both produced two identical "[*] Connecting…" lines in
    // the terminal + duplicate [Progress] log entries.
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
        // Actor torn down — leave Connection in its current
        // state; the Notifier's own `disconnect(id)` already
        // removed the Dart-side row.
        break;
      case _:
        break;
    }
    _notify();
  }

  /// Translate the legacy [SshAuth] config bag into the typed
  /// [SshAuthMethod] family the bus connect args carry.
  /// Precedence: keyData > password.
  ///
  /// Routes through `lfs_core::connection::auth_compose::
  /// prepare_auth` (FRB async) so the saved-session-staged →
  /// manager-key-staged → quick-connect-fallback walk lives one
  /// place. The composer reads sqlite columns + stages every
  /// byte into the SecretStore inside Rust; the Dart caller
  /// only sees the typed ref + the transient id list to drop
  /// after the connect attempt settles.
  ///
  /// FRB-unreachable contexts (flutter_test) propagate the throw —
  /// every secret-staging path was itself a FRB call, so the
  /// previous "Dart fallback" pipeline collapsed to the same
  /// failure the orchestrator surfaces directly.
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
    return switch (prepared.auth) {
      rust_auth.DbPreparedAuthRef_Password(:final secretId) =>
        SshAuthPasswordRef(secretId),
      rust_auth.DbPreparedAuthRef_Pubkey(
        :final keySecretId,
        :final passphraseSecretId,
      ) =>
        SshAuthPubkeyRef(keySecretId, passphraseSecretId: passphraseSecretId),
    };
  }

  /// Overlay [Connection.cachedPassphrase] onto [config] when set —
  /// populated on interactive passphrase prompts with the
  /// "remember" box ticked. Applied only when the config does not
  /// already carry a passphrase, so an explicitly-passed value
  /// wins.
  SSHConfig _withCredentialOverlay(Connection conn, SSHConfig config) {
    final cached = conn.cachedPassphrase;
    if (cached == null || config.auth.passphrase.isNotEmpty) return config;
    return config.copyWith(auth: config.auth.copyWith(passphrase: cached));
  }

  /// Store the post-auth credential envelope so a later reconnect
  /// (possibly after auto-lock closed the encrypted store) does
  /// not need to re-read `Session.auth`. Cache writes only happen
  /// for stored sessions — quick-connect has no stable key, and
  /// the next `reconnect` call already carries the full config.
  void _cachePostAuthCredentials(Connection conn, SSHConfig config) {
    final cache = _credentialCache;
    final sessionId = conn.sessionId;
    if (cache == null || sessionId == null) return;
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
}
