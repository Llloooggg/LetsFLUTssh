import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection.dart';
import '../core/connection/connection_manager.dart';
import '../core/connection/foreground_service.dart';
import '../core/ssh/known_hosts.dart';

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
  final manager = ConnectionManager(
    knownHosts: knownHosts,
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
