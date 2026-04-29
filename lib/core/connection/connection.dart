import 'dart:async';

import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/bus.dart' as rust_bus;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../ssh/ssh_config.dart';
import '../ssh/transport/rust_transport.dart';
import '../ssh/transport/ssh_transport.dart';
import 'connection_extension.dart';
import 'connection_step.dart';
import 'connection_step_mappers.dart';

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

  SSHConnectionState state;

  /// Passphrase entered interactively — cached for reconnect within same session.
  ///
  /// Cleared eagerly on [ConnectionsNotifier.disconnect] via
  /// [clearCachedCredentials]. Set by [ConnectionsNotifier] when user
  /// checks "remember".
  ///
  /// ## Memory hygiene caveat
  ///
  /// Dart `String` is immutable — we cannot overwrite its backing
  /// bytes with zeros the way [SecretBuffer] does for the DB key.
  /// The best we can do is drop every reference we own so the
  /// garbage collector can reclaim it, which is what
  /// [clearCachedCredentials] does. The passphrase copies that the
  /// Rust transport holds during auth (russh / russh-keys) live
  /// inside `Zeroizing` buffers there. Treat this field as "narrow
  /// the exposure window" rather than "erase the secret".
  String? cachedPassphrase;

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
          addProgressStep(
            ConnectionStep(
              phase: mapBusPhase(event.step.phase),
              status: mapBusStatus(event.step.status),
              detail: event.step.detail,
            ),
          );
        } else if (event is rust_bus.BusEvent_ConnectionStateChanged) {
          _onBusStateChanged(event.state);
        }
      });
    } catch (e) {
      // FRB native lib not loaded (flutter_test). Tests drive
      // progress via direct `addProgressStep` and set
      // `transport` / `state` directly; the bus subscription
      // is opt-in.
      AppLogger.instance.log(
        'Connection.subscribeProgressBus skipped: $e',
        name: 'Connection',
      );
    }
  }

  /// Bus-driven state-machine hook. The Rust connection actor
  /// publishes a `ConnectionStateChanged` event for every
  /// transition; this listener mirrors the relevant Dart-side
  /// state (transport adoption + transient-secret eviction)
  /// without requiring the manager to mediate.
  ///
  /// `Connecting` → no Dart-side mutation needed (the manager
  /// flips the `state` field directly when it kicks off the
  /// connect attempt; a redundant write here would just race).
  ///
  /// `Connected` → fetch the live russh session via FRB, wrap
  /// it in `RustTransport.adopt`, fire the connected hook, drop
  /// any per-attempt transient secrets the connect path staged.
  ///
  /// `Disconnected` → clear the adopted transport + drop staged
  /// transient secrets so the next reconnect starts clean.
  void _onBusStateChanged(rust_bus.BusConnectionState state) {
    switch (state) {
      case rust_bus.BusConnectionState.connecting:
        // No-op — manager-side flow flips the Dart `state`
        // field at the same edge.
        break;
      case rust_bus.BusConnectionState.connected:
        unawaited(_adoptSession());
        _evictTransientSecrets();
      case rust_bus.BusConnectionState.disconnected:
        transport = null;
        _evictTransientSecrets();
    }
  }

  Future<void> _adoptSession() async {
    try {
      final session = await rust_bus.connectionGetSession(id: id);
      if (session == null) {
        AppLogger.instance.log(
          'connection_get_session returned null for $id',
          name: 'Connection',
          level: LogLevel.warn,
        );
        return;
      }
      transport = RustTransport.adopt(session);
      notifyExtensionsConnected();
    } catch (e) {
      AppLogger.instance.log(
        'Connection.adoptSession failed for $id: $e',
        name: 'Connection',
        level: LogLevel.warn,
      );
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

  /// Mark connection attempt as resolved. Called by [ConnectionsNotifier].
  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    if (!_progressController.isClosed) _progressController.close();
  }

  /// Stream of connection progress steps. Closes when [completeReady] is called.
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
    if (!_progressController.isClosed) _progressController.close();
    _progressController = StreamController<ConnectionStep>.broadcast();
    _progressHistory.clear();
    connectionError = null;
    // Old transient ids belonged to the prior attempt's
    // SecretStore entries (already dropped on its terminal state);
    // start the new attempt with an empty set.
    transientSecretIds.clear();
  }

  /// Drop every reference this Connection owns to plaintext credentials
  /// so the GC can reclaim them as soon as possible.
  ///
  /// Meant to be called by [ConnectionsNotifier] right before removing the
  /// Connection from its map on disconnect — by that point there is no
  /// legitimate reason to keep the passphrase, and holding onto an
  /// immutable `String` any longer just widens the window a coredump
  /// could scoop it up. See the caveat on [cachedPassphrase] for why
  /// "drop reference" is as strong as Dart allows.
  void clearCachedCredentials() {
    cachedPassphrase = null;
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
  /// Idempotent — repeated calls are a no-op.
  void dispose() {
    final sub = _busSub;
    _busSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
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
