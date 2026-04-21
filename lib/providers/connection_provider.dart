import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection.dart';
import '../core/connection/connection_manager.dart';
import '../core/connection/foreground_service.dart';
import '../core/ssh/known_hosts.dart';
import 'session_credential_cache_provider.dart';

/// Known hosts manager — singleton.
final knownHostsProvider = Provider<KnownHostsManager>((ref) {
  return KnownHostsManager();
});

/// Foreground service manager — singleton (Android only, no-op on other platforms).
final foregroundServiceProvider = Provider<ForegroundServiceManager>((ref) {
  final manager = ForegroundServiceManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Connection manager — singleton.
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final knownHosts = ref.watch(knownHostsProvider);
  final foreground = ref.watch(foregroundServiceProvider);
  final credentialCache = ref.watch(sessionCredentialCacheProvider);
  final manager = ConnectionManager(
    knownHosts: knownHosts,
    credentialCache: credentialCache,
    onActiveCountChanged: (count) => foreground.onConnectionCountChanged(count),
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Reactive list of active connections.
/// Rebuilds when connections change.
final connectionsProvider = StreamProvider<List<Connection>>((ref) async* {
  final manager = ref.watch(connectionManagerProvider);
  yield manager.connections;
  await for (final _ in manager.onChange) {
    yield manager.connections;
  }
});

/// Projection of [connectionsProvider] into only the per-connection state
/// the UI actually renders: which sessions are connected or connecting,
/// and how many connections are in each bucket.
///
/// Consumers use this instead of [connectionsProvider] to avoid rebuilding
/// on unrelated [Connection] mutations (cached passphrase stored, live
/// [SSHConnection] swapped, progress steps appended). Two emits produce
/// the same [ConnectionSummary] iff the displayed state is unchanged, so
/// Riverpod short-circuits the rebuild via value equality.
@immutable
class ConnectionSummary {
  /// Session ids of connections currently in the `connected` state.
  /// Filtered to entries whose `sessionId` is non-null — i.e. the set a
  /// session tree row would use to paint a green dot. Connections
  /// without a sessionId (quick-connect) are not included here; they
  /// still contribute to [connectedTotal].
  final Set<String> connectedSessionIds;

  /// Same as [connectedSessionIds] for the transient `connecting` state.
  final Set<String> connectingSessionIds;

  /// Total number of connections in the `connected` state (including
  /// those without a session id — quick-connect connections).
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

/// Derived summary of the connection list. Re-emits only when any of the
/// four observed fields changes — unrelated [Connection] mutations are
/// dropped at this boundary so consumers don't rebuild.
final connectionSummaryProvider = Provider<ConnectionSummary>((ref) {
  final list = ref.watch(connectionsProvider).value ?? const [];
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
