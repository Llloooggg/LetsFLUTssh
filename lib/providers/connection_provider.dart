
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/connection/connection.dart';
import '../core/connection/connections_notifier.dart';
import '../core/connection/foreground_service.dart';
import '../src/rust/api/bus.dart' as rust_bus;

export 'known_hosts_provider.dart' show knownHostsProvider;

/// Foreground service manager — singleton (Android only, no-op on
/// other platforms).
final foregroundServiceProvider = Provider<ForegroundServiceManager>((ref) {
  final manager = ForegroundServiceManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// User-visible Connected count — derived from the Rust registry's
/// `ConnectionActiveCountChanged` bus event so the UI gets the same
/// count the Android foreground-service binding sees, in lock-step.
/// Yields `0` until the first event arrives.
final connectionActiveCountProvider = StreamProvider<int>((ref) async* {
  yield 0;
  await for (final event in AppBus.instance.subscribe(
    rust_bus.BusTopic.connection,
  )) {
    if (event is rust_bus.BusEvent_ConnectionActiveCountChanged) {
      yield event.count.toInt();
    }
  }
});

/// Side-effect listener that bridges the Rust active-count event
/// to the Android foreground-service binding. Watch from the app's
/// root scope (`main.dart`) so the listener is alive for the
/// process lifetime.
final foregroundActiveCountListenerProvider = Provider<void>((ref) {
  final foreground = ref.watch(foregroundServiceProvider);
  ref.listen<AsyncValue<int>>(connectionActiveCountProvider, (prev, next) {
    next.whenData((count) {
      foreground.onConnectionCountChanged(count);
    });
  });
});

/// Active SSH connections — Riverpod-native [NotifierProvider].
///
/// `state` is the live `List<Connection>` (excludes internal
/// bastion hops the orchestrator opens for ProxyJump). Mutations
/// (`connectAsync` / `reconnect` / `disconnect` /
/// `notifyStateChanged`) live on the [ConnectionsNotifier]; UI
/// consumers reach them via `ref.read(connectionsProvider.notifier)`.
///
/// The notifier subscribes to `BusTopic.connection` so every Rust
/// actor state transition (`ConnectionStateChanged`,
/// `ConnectionRemoved`, `ConnectionError`) re-emits state without
/// the workspace needing to poll. Tests inject a static list via
/// [StaticConnectionsNotifier].
final connectionsProvider =
    NotifierProvider<ConnectionsNotifier, List<Connection>>(
      ConnectionsNotifier.new,
    );

/// Test-only seam — overrides [connectionsProvider] with a static
/// list. Tests pass a `List&lt;Connection&gt;` to the constructor and
/// register the override via
/// `connectionsProvider.overrideWith(() => StaticConnectionsNotifier(list))`.
@visibleForTesting
class StaticConnectionsNotifier extends ConnectionsNotifier {
  StaticConnectionsNotifier(this._initial);
  final List<Connection> _initial;

  @override
  List<Connection> build() => _initial;
}

/// Projection of [connectionsProvider] into only the
/// per-connection state the UI actually renders: which sessions
/// are connected or connecting, and how many connections are in
/// each bucket.
///
/// Consumers use this instead of [connectionsProvider] to avoid
/// rebuilding on unrelated [Connection] mutations (cached
/// passphrase stored, live transport swapped, progress steps
/// appended). Two emits produce the same [ConnectionSummary] iff
/// the displayed state is unchanged, so Riverpod short-circuits
/// the rebuild via value equality.
@immutable
class ConnectionSummary {
  /// Session ids of connections currently in the `connected`
  /// state. Filtered to entries whose `sessionId` is non-null —
  /// i.e. the set a session tree row would use to paint a green
  /// dot. Connections without a sessionId (quick-connect) are not
  /// included here; they still contribute to [connectedTotal].
  final Set<String> connectedSessionIds;

  /// Same as [connectedSessionIds] for the transient `connecting`
  /// state.
  final Set<String> connectingSessionIds;

  /// Total number of connections in the `connected` state
  /// (including those without a session id — quick-connect
  /// connections).
  final int connectedTotal;

  /// Total number of connections in the `connecting` state.
  final int connectingTotal;

  const ConnectionSummary({
    required this.connectedSessionIds,
    required this.connectingSessionIds,
    required this.connectedTotal,
    required this.connectingTotal,
  });

  static const empty = ConnectionSummary(
    connectedSessionIds: <String>{},
    connectingSessionIds: <String>{},
    connectedTotal: 0,
    connectingTotal: 0,
  );

  int get activeTotal => connectedTotal + connectingTotal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSummary &&
          connectedTotal == other.connectedTotal &&
          connectingTotal == other.connectingTotal &&
          setEquals(connectedSessionIds, other.connectedSessionIds) &&
          setEquals(connectingSessionIds, other.connectingSessionIds);

  @override
  int get hashCode => Object.hash(
    connectedTotal,
    connectingTotal,
    Object.hashAllUnordered(connectedSessionIds),
    Object.hashAllUnordered(connectingSessionIds),
  );
}

/// Derived summary of the connection list. Re-emits only when any
/// of the four observed fields changes — unrelated [Connection]
/// mutations are dropped at this boundary so consumers don't
/// rebuild.
final connectionSummaryProvider = Provider<ConnectionSummary>((ref) {
  final list = ref.watch(connectionsProvider);
  if (list.isEmpty) return ConnectionSummary.empty;

  final connectedSessionIds = <String>{};
  final connectingSessionIds = <String>{};
  var connectedTotal = 0;
  var connectingTotal = 0;
  for (final c in list) {
    if (c.isConnected) {
      connectedTotal++;
      final sid = c.sessionId;
      if (sid != null) connectedSessionIds.add(sid);
    } else if (c.isConnecting) {
      connectingTotal++;
      final sid = c.sessionId;
      if (sid != null) connectingSessionIds.add(sid);
    }
  }
  return ConnectionSummary(
    connectedSessionIds: Set.unmodifiable(connectedSessionIds),
    connectingSessionIds: Set.unmodifiable(connectingSessionIds),
    connectedTotal: connectedTotal,
    connectingTotal: connectingTotal,
  );
});
