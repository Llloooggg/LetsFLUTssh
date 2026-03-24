import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection.dart';
import '../core/connection/connection_manager.dart';
import '../core/ssh/known_hosts.dart';

/// Known hosts manager — singleton.
final knownHostsProvider = Provider<KnownHostsManager>((ref) {
  return KnownHostsManager();
});

/// Connection manager — singleton.
final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final knownHosts = ref.watch(knownHostsProvider);
  final manager = ConnectionManager(knownHosts: knownHosts);
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Reactive list of active connections.
/// Rebuilds when connections change.
final connectionsProvider =
    StreamProvider<List<Connection>>((ref) async* {
  final manager = ref.watch(connectionManagerProvider);
  yield manager.connections;
  await for (final _ in manager.onChange) {
    yield manager.connections;
  }
});
