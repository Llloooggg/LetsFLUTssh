import 'dart:async';

import '../ssh/known_hosts.dart';
import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';
import 'connection_step.dart';

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

  /// Known hosts manager — retained for reconnect after disconnect.
  final KnownHostsManager knownHosts;

  SSHConnection? sshConnection;
  SSHConnectionState state;

  /// Passphrase entered interactively — cached for reconnect within same session.
  ///
  /// Cleared eagerly on [ConnectionManager.disconnect] via
  /// [clearCachedCredentials]. Set by [ConnectionManager] when user
  /// checks "remember".
  ///
  /// ## Memory hygiene caveat
  ///
  /// Dart `String` is immutable — we cannot overwrite its backing
  /// bytes with zeros the way [SecretBuffer] does for the DB key.
  /// The best we can do is drop every reference we own so the
  /// garbage collector can reclaim it, which is what
  /// [clearCachedCredentials] does. The passphrase copies that
  /// `dartssh2` holds internally during auth are also out of reach
  /// for the same reason. Treat this field as "narrow the exposure
  /// window" rather than "erase the secret".
  String? cachedPassphrase;

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

  Connection({
    required this.id,
    required this.label,
    required this.sshConfig,
    this.sessionId,
    KnownHostsManager? knownHosts,
    this.sshConnection,
    this.state = SSHConnectionState.disconnected,
    this.connectionError,
  }) : knownHosts = knownHosts ?? KnownHostsManager();

  bool get isConnected => state == SSHConnectionState.connected;
  bool get isConnecting => state == SSHConnectionState.connecting;

  /// Future that completes when connection attempt finishes
  /// (success or failure). Safe to await multiple times.
  Future<void> get ready => _readyCompleter.future;

  /// Wait for connection to leave `connecting` state.
  ///
  /// No-op if not currently connecting. Timeout is handled at the
  /// [ConnectionManager] level — UI callers just await this.
  Future<void> waitUntilReady() async {
    if (!isConnecting) return;
    await ready;
  }

  /// Mark connection attempt as resolved. Called by [ConnectionManager].
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
  }

  /// Drop every reference this Connection owns to plaintext credentials
  /// so the GC can reclaim them as soon as possible.
  ///
  /// Meant to be called by [ConnectionManager] right before removing the
  /// Connection from its map on disconnect — by that point there is no
  /// legitimate reason to keep the passphrase, and holding onto an
  /// immutable `String` any longer just widens the window a coredump
  /// could scoop it up. See the caveat on [cachedPassphrase] for why
  /// "drop reference" is as strong as Dart allows.
  void clearCachedCredentials() {
    cachedPassphrase = null;
  }
}
