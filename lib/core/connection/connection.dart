import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/s3.dart' as rust_s3;
import '../../src/rust/api/webdav.dart' as rust_webdav;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../session/session.dart';
import '../ssh/ssh_config.dart';
import '../ssh/transport/rust_transport.dart';
import '../ssh/transport/ssh_transport.dart';
import 'connection_step.dart';

part 'connection_extension.dart';
part 'connection_step_mappers.dart';

/// SSH connection lifecycle state.
enum SSHConnectionState { disconnected, connecting, connected }

/// Represents a single SSH connection with its lifecycle state.
///
/// One connection can serve multiple tabs (terminal + SFTP).
class Connection {
  final String id;
  final String label;
  SSHConfig sshConfig;

  /// Session ID from the store — used to re-read fresh config on reconnect.
  /// Null for quick-connect sessions (no saved session).
  final String? sessionId;

  /// Engine-agnostic SSH transport. Set on successful connect by
  /// `ConnectionsNotifier`; downstream features (shell_helper,
  /// sftp_initializer, port_forward_runtime) read it for shell /
  /// SFTP / port-forward channels.
  SshTransport? transport;

  /// Live WebDAV transport handle for WebDAV-kind sessions. Set on
  /// successful WebDAV connect; null for SSH sessions or before
  /// the WebDAV connect probe completes. The file browser reads it
  /// alongside [`transport`] when dispatching by [`kind`].
  rust_webdav.WebDavConnection? webdavConnection;

  /// Live S3 transport handle for S3-kind sessions. Set on
  /// successful connect; null for non-S3 sessions or before the
  /// connect probe completes. The file browser reads it alongside
  /// [`transport`] / [`webdavConnection`] when dispatching by
  /// [`kind`].
  rust_s3.S3Connection? s3Connection;

  /// Transport tag for this connection. SSH connections leave it
  /// at the default; WebDAV connections set it at construction
  /// time so the workspace UI and the file browser can branch on
  /// the value without re-reading the source [`Session`].
  SessionKind kind = SessionKind.ssh;

  /// Base URL for a WebDAV connection — the implicit "current
  /// working directory" the WebDAV file browser opens at. Empty
  /// for SSH connections. Set at the same point [`webdavConnection`]
  /// lands so the two move together.
  String webdavBaseUrl = '';

  /// Initial path the S3 file browser opens at. Resolved at
  /// connect time from the configured default bucket + prefix:
  /// either `s3://<bucket>/<prefix>` when an explicit bucket is
  /// set, or the empty string (browser starts at the bucket
  /// root). Empty for non-S3 connections.
  String s3InitialDir = '';

  SSHConnectionState state;

  /// Per-attempt transient secret IDs the connect path staged into
  /// the Rust `SecretStore`. Populated by
  /// `ConnectionsNotifier._authFromConfig` whenever the auth bytes
  /// don't have a stable id (quick-connect, key-with-typed-passphrase,
  /// empty-auth probe). Drained on terminal state (Connected /
  /// Disconnected) by `_applyConnectionEvent` so the secrets are
  /// dropped from `SecretStore` instead of accumulating across the
  /// process lifetime.
  ///
  /// Cleared on `resetForReconnect` so a fresh attempt starts with
  /// an empty list.
  final Set<String> transientSecretIds = <String>{};

  /// Raw error from last connection attempt, null if no error.
  /// Use [localizeError] from `utils/format.dart` to display to user.
  Object? connectionError;

  /// Completes when the connection leaves the `connecting` state
  /// (either connected or failed). Callers use [ready] instead of polling.
  Completer<void> _readyCompleter = Completer<void>();

  /// Broadcasts connection progress steps during connect/reconnect.
  StreamController<ConnectionStep> _progressController =
      StreamController<ConnectionStep>.broadcast();

  /// Buffered progress steps — replayed to late subscribers.
  final _progressHistory = <ConnectionStep>[];

  /// Resolves once `_adoptSession` has finished — `true` when the
  /// russh handle was fetched + wrapped in [`RustTransport`] (so
  /// [`transport`] is non-null), `false` when adoption failed
  /// (`connectionGetSession` returned null, FRB error, etc.) or
  /// the actor moved straight to Disconnected.
  ///
  /// Connect-flow consumers (terminal pane, SFTP browser) await
  /// this AFTER [waitUntilReady] before reading [`transport`] —
  /// otherwise they race the async adoption and see a null
  /// transport even though `state == connected` already flipped
  /// via [_onBusStateChanged].
  Completer<bool> _transportAdopted = Completer<bool>();

  /// Resolves when the Rust connection actor publishes
  /// [`BusEvent::ConnectionRemoved`] for this id — the canonical
  /// "the actor is gone, no more events for this id are coming"
  /// signal. [`dispose`] awaits this with a short timeout before
  /// cancelling [`_busSub`] so the listener has a chance to
  /// process trailing teardown events before its broadcast
  /// subscription drops. The timeout exists for the path where
  /// the Connection is disposed without ever having owned an
  /// actor (test container dispose, FRB-unreachable contexts) —
  /// there is no `ConnectionRemoved` to wait for, so we proceed
  /// after the bound elapses.
  final Completer<void> _removed = Completer<void>();

  /// Lifecycle add-ons (port forwards, recording sinks, future agent
  /// forwarding). See [ConnectionExtension] for the contract. The list
  /// is owned by this Connection — features register at construction
  /// time and stay attached for the connection's full lifetime, which
  /// is what lets them survive reconnect transparently.
  final _extensions = <ConnectionExtension>[];

  /// Bastion connection feeding this connection's ProxyJump tunnel.
  /// Owned by the manager's connection map; its lifecycle is pinned
  /// to this connection's lifecycle (disconnect cascades).
  /// Null = direct connect.
  Connection? bastion;

  /// True for connections the manager creates internally (e.g. the
  /// bastion hop of a ProxyJump chain). The workspace UI hides
  /// internal connections so the user never sees a phantom tab for
  /// the bastion that they never explicitly opened.
  bool internal;

  Connection({
    required this.id,
    required this.label,
    required this.sshConfig,
    this.sessionId,
    this.transport,
    this.state = SSHConnectionState.disconnected,
    this.connectionError,
    this.bastion,
    this.internal = false,
  }) {
    _subscribeProgressBus();
  }

  /// Bus subscription that drives the per-connection progress
  /// stream. The Rust connection actor publishes
  /// `BusEvent::ConnectionProgress` for every phase transition
  /// (socket connect, host-key verify, authenticate, open
  /// channel); this listener filters on [id], maps the typed
  /// FRB phase / status into the Dart enums, and feeds the
  /// existing [progressStream] / [progressHistory] surface so
  /// downstream consumers (`ProgressTracker`, the connection
  /// drawer) keep working unchanged.
  ///
  /// Best-effort — flutter_test contexts that don't load the
  /// FRB native lib hit the catch and the test code drives
  /// progress via direct [addProgressStep] calls instead.
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  void _subscribeProgressBus() {
    try {
      _busSub = AppBus.instance.subscribeConnection(id).listen((event) {
        if (event is rust_bus.BusEvent_ConnectionProgress) {
          final phase = mapBusPhase(event.step.phase);
          final status = mapBusStatus(event.step.status);
          addProgressStep(
            ConnectionStep(
              phase: phase,
              status: status,
              detail: event.step.detail,
            ),
          );
          if (status == StepStatus.failed) {
            AppLogger.instance.log(
              'Connect step failed: ${phase.name} '
              '— ${event.step.detail ?? "no detail"}',
              name: 'Connection',
              level: LogLevel.warn,
            );
          }
        } else if (event is rust_bus.BusEvent_ConnectionStateChanged) {
          _onBusStateChanged(event.state);
        } else if (event is rust_bus.BusEvent_ConnectionError) {
          connectionError = event.detail;
          AppLogger.instance.log(
            'Connection actor error: ${event.detail}',
            name: 'Connection',
            level: LogLevel.warn,
          );
        } else if (event is rust_bus.BusEvent_ConnectionRemoved) {
          if (!_removed.isCompleted) _removed.complete();
        }
      });
    } on StateError catch (e) {
      // FRB native lib not loaded (flutter_test). The init guard
      // throws `StateError("flutter_rust_bridge has not been
      // initialized")`; tests drive progress via direct
      // `addProgressStep` and set `transport` / `state` directly,
      // so the bus subscription is opt-in. Narrowed from the
      // earlier `catch (e)` so a real bug (a typed FRB error,
      // a `MissingPluginException` from a stub plugin) surfaces
      // instead of silently degrading to "no progress events".
      AppLogger.instance.log(
        'Connection.subscribeProgressBus skipped (FRB not initialised): $e',
        name: 'Connection',
      );
    }
  }

  /// Bus-driven state-machine hook. The Rust connection actor
  /// publishes a `ConnectionStateChanged` event for every
  /// transition; this listener owns the Dart-side `state` field
  /// + the per-state side effects (transport adoption,
  /// transient-secret eviction, connect-attempt success/failure
  /// logging).
  ///
  /// The manager (`ConnectionsNotifier`) used to mirror these
  /// events through a per-attempt subscription it cancelled in
  /// `_doConnect.finally`, but the cancel raced in-flight events
  /// from the FRB worker thread and produced "Fail to post
  /// message to Dart" stderr noise on every connect. Every duty
  /// the per-attempt sub had now lives here, where the
  /// subscription's lifetime matches the Connection's.
  ///
  /// `Connecting` → mirror state on the Dart object.
  ///
  /// `Connected` → flip state, fetch the live russh session via
  /// FRB, wrap it in `RustTransport.adopt`, fire the connected
  /// hook, drop any per-attempt transient secrets the connect
  /// path staged.
  ///
  /// `Disconnected` → flip state, clear the adopted transport,
  /// log "Connection failed" only if the prior state was
  /// `connecting` (a clean teardown after `connected` is logged
  /// by [`ConnectionsNotifier.disconnect`] itself), drop staged
  /// transient secrets so the next reconnect starts clean.
  void _onBusStateChanged(rust_bus.BusConnectionState state) {
    switch (state) {
      case rust_bus.BusConnectionState.connecting:
        this.state = SSHConnectionState.connecting;
      case rust_bus.BusConnectionState.connected:
        this.state = SSHConnectionState.connected;
        AppLogger.instance.log(
          'Connected: <label> (id=$id)',
          name: 'Connection',
        );
        unawaited(_adoptSession());
        _evictTransientSecrets();
      case rust_bus.BusConnectionState.disconnected:
        // Distinguish "connect attempt failed" (was connecting → now
        // disconnected) from "live session torn down" (was connected
        // → now disconnected). Only the former is a failure worth a
        // warn-level log line; teardown is logged at info level by
        // ConnectionsNotifier.disconnect itself.
        final wasConnecting = this.state == SSHConnectionState.connecting;
        this.state = SSHConnectionState.disconnected;
        transport = null;
        if (wasConnecting) {
          AppLogger.instance.log(
            'Connection failed: ${connectionError ?? "no error detail"}',
            name: 'Connection',
            level: LogLevel.warn,
            error: connectionError,
          );
        }
        // Wake any waiter on `transportReady` so the connect-flow
        // consumer doesn't deadlock when the actor moves straight
        // to Disconnected without an Adopt step.
        if (!_transportAdopted.isCompleted) {
          _transportAdopted.complete(false);
        }
        _evictTransientSecrets();
    }
  }

  /// Resolves once the russh transport has been adopted (or
  /// adoption failed). `true` = [`transport`] is non-null and
  /// usable; `false` = adoption failed / actor settled into
  /// Disconnected. Safe to await multiple times — a second
  /// `await` after completion returns the same value.
  Future<bool> get transportReady => _transportAdopted.future;

  /// Test-only: short-circuit the [transportReady] gate so widgets
  /// driven by [SftpBrowserMixin] / similar `await conn.transportReady`
  /// flows resolve under a synthetic [Connection] built directly
  /// with `state: SSHConnectionState.connected` (no actor, no
  /// `_adoptSession`). Production never calls this — the bus
  /// listener is the only path that completes the underlying
  /// completer in real flows.
  @visibleForTesting
  void debugMarkTransportAdopted({bool adopted = true}) {
    if (!_transportAdopted.isCompleted) {
      _transportAdopted.complete(adopted);
    }
  }

  Future<void> _adoptSession() async {
    var adopted = false;
    try {
      final session = await rust_bus.connectionGetSession(id: id);
      if (session == null) {
        AppLogger.instance.log(
          'connection_get_session returned null for $id',
          name: 'Connection',
          level: LogLevel.warn,
        );
      } else {
        transport = RustTransport.adopt(session);
        notifyExtensionsConnected();
        adopted = true;
      }
    } catch (e) {
      AppLogger.instance.log(
        'Connection.adoptSession failed for $id: $e',
        name: 'Connection',
        level: LogLevel.warn,
      );
    } finally {
      if (!_transportAdopted.isCompleted) {
        _transportAdopted.complete(adopted);
      }
    }
  }

  /// Drop every per-attempt secret the connect path staged into
  /// the Rust SecretStore in one batch FRB call. Best-effort —
  /// flutter_test contexts that don't load the FRB native lib
  /// hit the catch and the in-memory tracking set is still
  /// cleared so the next attempt starts clean.
  void _evictTransientSecrets() {
    if (transientSecretIds.isEmpty) return;
    final ids = List<String>.of(transientSecretIds);
    transientSecretIds.clear();
    try {
      rust_app.secretsDropMany(ids: ids);
    } catch (e) {
      AppLogger.instance.log(
        'Connection.evictTransientSecrets skipped: $e',
        name: 'Connection',
        level: LogLevel.warn,
      );
    }
  }

  bool get isConnected => state == SSHConnectionState.connected;
  bool get isConnecting => state == SSHConnectionState.connecting;

  /// Future that completes when connection attempt finishes
  /// (success or failure). Safe to await multiple times.
  Future<void> get ready => _readyCompleter.future;

  /// Wait for connection to leave `connecting` state.
  ///
  /// No-op if not currently connecting. Timeout is handled at the
  /// [ConnectionsNotifier] level — UI callers just await this.
  Future<void> waitUntilReady() async {
    if (!isConnecting) return;
    await ready;
  }

  /// Mark connection attempt as resolved. Called by [ConnectionsNotifier]
  /// inside `_doConnect.finally`, which happens immediately after the
  /// FRB `connection_connect` call returns. The Rust actor publishes
  /// post-handshake events (3× progress success + ConnectionStateChanged
  /// connected) right before `connect_async` returns, but Dart processes
  /// them via the bus subscription's microtask queue — so they land
  /// AFTER `completeReady` runs in the same tick.
  ///
  /// We do NOT close `_progressController` here for that reason. Closing
  /// it would silently drop every queued post-success step in
  /// `addProgressStep` (the `isClosed` guard kicks in), and downstream
  /// subscribers (`ProgressTracker.writeStep`) would never see the
  /// `success` lines for `socketConnect` / `hostKeyVerify` /
  /// `authenticate`. The controller stays open for the Connection's full
  /// lifetime; `dispose` closes it.
  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  /// Stream of connection progress steps. Open for the lifetime of the
  /// Connection — closed by [dispose].
  Stream<ConnectionStep> get progressStream => _progressController.stream;

  /// Buffered history of all progress steps — for late subscribers.
  List<ConnectionStep> get progressHistory =>
      List.unmodifiable(_progressHistory);

  /// Add a progress step to the stream (if still open).
  void addProgressStep(ConnectionStep step) {
    _progressHistory.add(step);
    if (!_progressController.isClosed) _progressController.add(step);
  }

  /// Register a lifecycle add-on. Idempotent on the same instance —
  /// re-registering is silently dropped so listener wiring at multiple
  /// layers (provider + manager) never double-attaches.
  void addExtension(ConnectionExtension extension) {
    if (_extensions.contains(extension)) return;
    _extensions.add(extension);
  }

  /// Remove a previously-registered extension. Safe to call when the
  /// extension was never added.
  void removeExtension(ConnectionExtension extension) {
    _extensions.remove(extension);
  }

  /// Snapshot view for diagnostics / tests — never mutate the live
  /// list directly. The Connection owns hook ordering.
  List<ConnectionExtension> get extensions => List.unmodifiable(_extensions);

  /// Fire [ConnectionExtension.onConnected] on every registered hook.
  /// Failures inside one extension never block the others or the
  /// surrounding connection lifecycle — log and continue.
  void notifyExtensionsConnected() =>
      _fanOut('onConnected', (e) => e.onConnected(this));

  /// Fire [ConnectionExtension.onDisconnecting] on every hook.
  void notifyExtensionsDisconnecting() =>
      _fanOut('onDisconnecting', (e) => e.onDisconnecting(this));

  /// Fire [ConnectionExtension.onReconnecting] on every hook.
  void notifyExtensionsReconnecting() =>
      _fanOut('onReconnecting', (e) => e.onReconnecting(this));

  void _fanOut(String hook, void Function(ConnectionExtension) fire) {
    // Iterate over a snapshot — extensions are allowed to mutate the
    // list (deregister themselves on failure, register dependent
    // extensions) without invalidating the iteration.
    for (final ext in List<ConnectionExtension>.from(_extensions)) {
      try {
        fire(ext);
      } catch (e, st) {
        AppLogger.instance.log(
          'ConnectionExtension $hook failed for <${ext.id}>',
          name: 'Connection',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Reset internal state for a reconnect attempt.
  ///
  /// Creates fresh [_readyCompleter] and [_progressController] so callers
  /// can await [ready] and subscribe to [progressStream] again.
  void resetForReconnect() {
    _readyCompleter = Completer<void>();
    _transportAdopted = Completer<bool>();
    if (!_progressController.isClosed) _progressController.close();
    _progressController = StreamController<ConnectionStep>.broadcast();
    _progressHistory.clear();
    connectionError = null;
    // Old transient ids belonged to the prior attempt's
    // SecretStore entries (already dropped on its terminal state);
    // start the new attempt with an empty set.
    transientSecretIds.clear();
  }

  /// Tear down the Connection's persistent resources — bus
  /// subscription, progress controller, and any per-attempt
  /// transient secrets the connect path staged that the bus's
  /// terminal-state path didn't already clear. Must be called
  /// by [ConnectionsNotifier] when removing the Connection from
  /// its map; without this the subscription pins the Connection
  /// in memory + keeps consuming bus events for an id no one
  /// renders anymore.
  ///
  /// Awaits [`_removed`] with a 1-second cap before cancelling
  /// [`_busSub`]. The Rust `connection::disconnect` publishes
  /// [`BusEvent::ConnectionRemoved`] as the last event of its
  /// teardown; once we observe it, no more bus traffic is coming
  /// for this id, so the subscription cancel cannot race the FRB
  /// worker thread's in-flight delivery. The cap fires for paths
  /// where the actor was never alive (test container dispose,
  /// FRB-unreachable contexts) — no `ConnectionRemoved` is ever
  /// published, so we proceed after the bound rather than hang.
  ///
  /// Idempotent — repeated calls are a no-op.
  Future<void> dispose() async {
    if (!_removed.isCompleted) {
      await _removed.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
    final sub = _busSub;
    _busSub = null;
    if (sub != null) {
      await sub.cancel();
    }
    if (!_progressController.isClosed) {
      _progressController.close();
    }
    // Belt-and-braces: evict any transient secrets the bus
    // event path didn't get to clear (explicit user-disconnect
    // races the bus subscription teardown — by the time the
    // `Disconnected` event fires the subscription may already
    // be cancelled, leaving the staged ids stranded in the
    // SecretStore).
    _evictTransientSecrets();
  }
}
