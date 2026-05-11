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

  /// Per-connection revision counter. Bumped every time a bus
  /// event for that id arrives — `state_changed`, `progress`,
  /// `error`, `removed`. Consumers that want fine-grained
  /// rebuilds (`connectionByIdProvider` family) watch
  /// `connectionRevisionProvider(id)` so siblings' state
  /// transitions don't repaint a row tied to a different id.
  /// Without this, every consumer of `connectionsProvider`
  /// rebuilt on every event because the list rebuild fan-out
  /// can't be deduplicated by id at the list level.
  final Map<String, int> _revisions = <String, int>{};

  /// Read the current revision for [id]. `0` for an id that has
  /// never received a bus event. Increments monotonically; never
  /// decreases, never wraps in practice (`int` is 64-bit on every
  /// supported platform).
  int revisionFor(String id) => _revisions[id] ?? 0;

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
          .listen(_handleBusEvent);
    } on StateError catch (e) {
      // FRB-not-initialised in flutter_test. Narrowed catch so a
      // typed FRB envelope error still surfaces.
      AppLogger.instance.log(
        'connections_notifier: bus subscribe skipped (FRB not init): $e',
        name: 'ConnectionsNotifier',
      );
    }
    ref.onDispose(() {
      _disposed = true;
      if (busSub != null) unawaited(busSub.cancel());
      _disconnectAll();
    });
    return const [];
  }

  /// Bus → notifier glue. Bumps the per-id revision before the
  /// list rebuild so a `connectionRevisionProvider(id)` consumer
  /// sees the new revision on the same frame the list-level
  /// rebuild fans out.
  ///
  /// `Progress` events fire at ~50 ms cadence per connect phase
  /// and feed `Connection.progressStream` directly via the
  /// per-id `AppBus.subscribeConnection(id)` subscription the
  /// [Connection] class owns; list-watchers (workspace summary
  /// projection, mobile-shell SFTP-button gate) never project
  /// progress fields, so the list re-emit on every progress
  /// tick was wasted work. Skip `_notify()` on Progress; the
  /// per-id revision still bumps so a
  /// `connectionRevisionProvider(id)` consumer (today: no UI
  /// surface; reserved for a future fine-grained consumer) can
  /// observe the tick without a list-level fan-out.
  void _handleBusEvent(rust_bus.BusEvent event) {
    final id = switch (event) {
      rust_bus.BusEvent_ConnectionStateChanged(:final id) => id,
      rust_bus.BusEvent_ConnectionProgress(:final id) => id,
      rust_bus.BusEvent_ConnectionError(:final id) => id,
      rust_bus.BusEvent_ConnectionRemoved(:final id) => id,
      _ => null,
    };
    if (id != null) {
      _revisions[id] = (_revisions[id] ?? 0) + 1;
    }
    if (event is rust_bus.BusEvent_ConnectionProgress) return;
    _notify();
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
    } on StateError {
      // FRB stub in tests — caller doesn't branch on the result.
    }
  }

  int _bumpGeneration(String id) {
    try {
      return rust_connection.connectionBumpGeneration(id: id);
    } on StateError {
      return 1;
    }
  }

  void _dropGeneration(String id) {
    try {
      rust_connection.connectionDropGeneration(id: id);
    } on StateError {
      // FRB stub in tests — caller doesn't branch on the result.
    }
  }

  void _clearGenerations() {
    try {
      rust_connection.connectionClearGenerations();
    } on StateError {
      // FRB stub in tests — caller doesn't branch on the result.
    }
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
    } on StateError {
      // FRB stub in tests — every generation is "current" so the
      // reconnect path doesn't short-circuit on the no-op stub.
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
    // longer reachable through the map. `dispose()` is async
    // because it waits for `BusEvent::ConnectionRemoved` to
    // arrive on `Connection._busSub` before cancelling the
    // subscription — the wait is what kills the
    // "Fail to post message to Dart" stderr noise FRB used to
    // emit on every disconnect (the worker was racing the
    // cancel). Fire-and-forget here: the workspace caller
    // doesn't await disconnect, and we already removed the
    // Connection from the map so nothing reads it after this.
    unawaited(conn.dispose());
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
      final sessionId = conn.sessionId;
      if (sessionId != null) {
        unawaited(
          _credentialCache?.evict(sessionId).catchError((Object _) {}) ??
              Future<void>.value(),
        );
      }
      unawaited(conn.dispose());
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
    final auth = await _authFromConfig(config.auth, conn.sessionId, conn);

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
      args = busConnectArgs(conn, config, auth);
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
    // No manual `socketConnect: inProgress` emit here — `connect_async`
    // in `lfs_core::connection::run_connect_driver` publishes the same
    // step on the bus as its first action, and Connection's permanent
    // `_busSub` forwards it into the per-connection progress stream.
    // Doing both produced two identical "[*] Connecting…" lines in
    // the terminal + duplicate [Progress] log entries.
    //
    // The per-attempt sub used to live here too, but every duty it
    // had — state mutation, transient-secret eviction, connect-step
    // logging, ConnectionError → connectionError capture — is now
    // owned by Connection's permanent `_busSub`. A second listener
    // cancelled in this `finally` raced in-flight events from the
    // FRB worker thread and produced "Fail to post message to Dart"
    // stderr noise on every connect, so it's gone.
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
      if (!_isStaleGeneration(conn.id, generation)) {
        conn.completeReady();
        if (conn.state == SSHConnectionState.connected) {
          _cachePostAuthCredentials(conn, config);
        }
      }
      _notify();
    }
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
      // Cert-paired branch runs ahead of the plain-pubkey branch
      // for symmetry with the Rust composer's `match` arm ordering
      // — both selectors privilege the stronger cert-auth path
      // whenever a cert is paired to the resolved manager key.
      rust_auth.DbPreparedAuthRef_PubkeyCert(
        :final keySecretId,
        :final certSecretId,
        :final passphraseSecretId,
      ) =>
        SshAuthPubkeyCertRef(
          keySecretId,
          certSecretId,
          passphraseSecretId: passphraseSecretId,
        ),
      rust_auth.DbPreparedAuthRef_Pubkey(
        :final keySecretId,
        :final passphraseSecretId,
      ) =>
        SshAuthPubkeyRef(keySecretId, passphraseSecretId: passphraseSecretId),
    };
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
