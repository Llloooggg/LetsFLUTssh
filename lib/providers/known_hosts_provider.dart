import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ssh/known_hosts.dart';

/// Process-singleton [KnownHostsManager] — owns the host-key
/// pin-on-trust state + the bus subscription that listens for
/// known-host prompt requests fired by the Rust SSH transport.
///
/// Lives in its own file so both `connection_provider.dart` (which
/// defines the connection notifier provider) and
/// `core/connection/connections_notifier.dart` (which implements
/// the notifier) can depend on it without creating a circular
/// import between them.
final knownHostsProvider = Provider<KnownHostsManager>((ref) {
  final manager = KnownHostsManager();
  ref.onDispose(manager.dispose);
  return manager;
});
