import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/connection/connection.dart';
import '../core/connection/connection_manager.dart';
import '../core/connection/foreground_service.dart';
import '../core/ssh/known_hosts.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/connection.dart' as rust_conn;
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
///
/// Active-count notifications no longer pass through the manager —
/// the Rust connection registry publishes
/// [rust_bus.BusEvent_ConnectionActiveCountChanged] on every state
/// transition, and [foregroundActiveCountListenerProvider] below
/// drives `ForegroundServiceManager.onConnectionCountChanged`
/// straight off the bus.
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final knownHosts = ref.watch(knownHostsProvider);
  final credentialCache = ref.watch(sessionCredentialCacheProvider);
  final manager = ConnectionManager(
    knownHosts: knownHosts,
    credentialCache: credentialCache,
  );
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

/// Side-effect listener that bridges the Rust active-count event to
/// the Android foreground-service binding. Watch from the app's root
/// scope (`main.dart`) so the listener is alive for the process
/// lifetime.
final foregroundActiveCountListenerProvider = Provider<void>((ref) {
  final foreground = ref.watch(foregroundServiceProvider);
  ref.listen<AsyncValue<int>>(connectionActiveCountProvider, (prev, next) {
    next.whenData((count) {
      foreground.onConnectionCountChanged(count);
    });
  });
});

/// Reactive list of active connections.
///
/// Hydrates from the manager's in-memory list and re-emits on
/// every state change. Two trigger sources fold into one stream:
///
/// 1. `manager.onChange` — Dart-side mutations (a new Connection
///    enters the map via `connectAsync`, leaves via `disconnect`,
///    or the workspace UI calls `notifyStateChanged` after a
///    shell open / close that the bus does not see).
/// 2. `BusTopic.connection` events — every Rust actor state
///    transition (`ConnectionStateChanged`, `ConnectionRemoved`,
///    `ConnectionError`) that the workspace status dots track.
///
/// The bus subscription is a forward-looking hedge: as the
/// `ConnectionManager` retires in favour of a Rust-backed
/// registry, more state changes will flow through the bus only
/// without a Dart `onChange` ping. Listening here today means
/// the eventual cutover doesn't need to walk every consumer.
final connectionsProvider = StreamProvider<List<Connection>>((ref) async* {
  final manager = ref.watch(connectionManagerProvider);
  final controller = StreamController<void>.broadcast();
  final dartSub = manager.onChange.listen((_) => controller.add(null));
  final busSub = AppBus.instance
      .subscribe(rust_bus.BusTopic.connection)
      .listen((_) => controller.add(null));
  ref.onDispose(() {
    unawaited(dartSub.cancel());
    unawaited(busSub.cancel());
    unawaited(controller.close());
  });
  yield manager.connections;
  await for (final _ in controller.stream) {
    yield manager.connections;
  }
});

/// Rust-driven snapshot of every connection actor in the
/// registry. Mirrors `connectionsProvider` but sources from
/// `connection_snapshot_all` + the bus, with no dependency on
/// the Dart `ConnectionManager`. Stepping stone for the future
/// retire of the manager — consumers that don't need
/// `Connection`'s Dart-only state (transport, extensions,
/// cachedPassphrase) can subscribe here today.
///
/// Yields an empty list immediately, then re-snapshots on every
/// `BusTopic.connection` event. Falls back to an empty list +
/// no further yields when the FRB native lib isn't loaded
/// (flutter_test).
final connectionRustSnapshotsProvider =
    StreamProvider<List<rust_conn.DbConnectionSnapshot>>((ref) async* {
      List<rust_conn.DbConnectionSnapshot> snapshot() {
        try {
          return rust_conn.connectionSnapshotAll();
        } catch (_) {
          return const <rust_conn.DbConnectionSnapshot>[];
        }
      }

      yield snapshot();
      final Stream<rust_bus.BusEvent> stream;
      try {
        stream = AppBus.instance.subscribe(rust_bus.BusTopic.connection);
      } catch (_) {
        // FRB native lib unavailable (flutter_test) — yield once
        // and stop; consumers fall back to the empty list.
        return;
      }
      await for (final _ in stream) {
        yield snapshot();
      }
    });

/// Projection of [connectionsProvider] into only the per-connection state
/// the UI actually renders: which sessions are connected or connecting,
/// and how many connections are in each bucket.
///
/// Consumers use this instead of [connectionsProvider] to avoid rebuilding
/// on unrelated [Connection] mutations (cached passphrase stored, live
/// transport swapped, progress steps appended). Two emits produce the
/// same [ConnectionSummary] iff the displayed state is unchanged, so
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
