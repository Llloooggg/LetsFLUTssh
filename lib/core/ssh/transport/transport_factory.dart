// SSH transport factory — always returns the Rust-backed transport.
// The dartssh2 escape hatch was removed once the Rust path stabilised
// across shell / SFTP / port-forward / ProxyJump flows.

import '../known_hosts.dart';
import 'rust_transport.dart';
import 'ssh_transport.dart';

/// Build a fresh transport for one connection. `knownHosts` is currently
/// unused on the Rust path (host-key verification lands in a follow-up);
/// kept on the signature so call sites that still pass it stay green.
SshTransport createSshTransport({KnownHostsManager? knownHosts}) {
  return RustTransport();
}
