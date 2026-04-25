// SshTransport — abstraction over the SSH layer, backed by the
// Rust security/transport core (`lib/src/rust/api/*`) via the
// flutter_rust_bridge bindings. RustTransport is the only impl;
// the abstraction stays so test mocks can swap in.
//
// Surface:
//   - connect (password / pubkey / cert / agent) + ProxyJump variants
//   - openShell with PTY size + bidirectional bytes
//   - openSftp returning an engine-agnostic SFTP client
//   - direct-tcpip channel for `-L` / `-D` / ProxyJump primitive
//   - server-side `-R` request + inbound queue
//   - graceful disconnect
//
// What's NOT in this interface (yet):
//   - host-key verification — Rust core accepts every server key today
//     (TOFU + known_hosts integration is a follow-up).
//   - keep-alive — protocol-level concern handled by russh internally.
//   - terminal-resize → shell.resize is on the shell handle, not the
//     transport.

import 'dart:async';
import 'dart:typed_data';

/// A bidirectional, engine-agnostic SSH connection.
///
/// Lifecycle: build a [SshConnectRequest] → call [connect] → use
/// [openShell] / [openSftp] / [openDirectTcpip] / [requestRemoteForward]
/// for sub-channels → [disconnect] when done. `Drop`-equivalent
/// cleanup runs through `disconnect`; relying on garbage collection
/// is engine-specific (russh tears the channel down on Drop;
/// Drop-equivalent cleanup runs through `disconnect`; relying on
/// garbage collection is engine-specific.
abstract class SshTransport {
  /// Connect + authenticate. Returns when the SSH userauth phase
  /// completes successfully; throws [SshAuthFailed] / [SshConnectError]
  /// on failure.
  Future<void> connect(SshConnectRequest request);

  /// Open a PTY-backed interactive shell channel. Multiple shells
  /// can coexist on one transport; each one gets its own
  /// [SshShellChannel] handle.
  Future<SshShellChannel> openShell({required int cols, required int rows});

  /// Open an SFTP subsystem on a fresh channel. Returns the engine
  /// SFTP client (today: `rust_sftp.SshSftp` from the Rust core).
  /// `RustSftpFs.create(transport)` is the call site that wraps it
  /// for the file_browser surface.
  Future<dynamic> openSftp();

  /// Open a direct-tcpip channel — the russh primitive behind
  /// `-L` local forwards and ProxyJump bastion hops.
  Future<SshDirectTcpipChannel> openDirectTcpip({
    required String hostToConnect,
    required int portToConnect,
    required String originatorAddress,
    required int originatorPort,
  });

  /// Ask the server to listen on `address:port` and forward incoming
  /// connections back over this transport (`-R`). Returns the actual
  /// bound port (server picks one when [port] is 0).
  Future<int> requestRemoteForward(String address, int port);

  /// Withdraw a previously-requested remote forward. Idempotent.
  Future<void> cancelRemoteForward(String address, int port);

  /// Inbound `-R` connections drain through this stream — one event
  /// per connection the server forwards back. Drains for the life of
  /// the transport; closes on [disconnect].
  Stream<SshForwardedConnection> get forwardedConnections;

  /// Cleanly tear down the transport. Sends `SSH_MSG_DISCONNECT`
  /// where supported; idempotent (repeated calls are no-ops).
  Future<void> disconnect();

  /// True iff the transport has connected + authenticated and not
  /// yet been disconnected.
  bool get isConnected;
}

/// Auth + connection parameters fed into [SshTransport.connect].
class SshConnectRequest {
  final String host;
  final int port;
  final String user;
  final SshAuthMethod auth;
  final Duration? inactivityTimeout;

  const SshConnectRequest({
    required this.host,
    required this.port,
    required this.user,
    required this.auth,
    this.inactivityTimeout,
  });
}

/// Auth method discriminator. Each variant carries its own payload.
sealed class SshAuthMethod {
  const SshAuthMethod();
}

class SshAuthPassword extends SshAuthMethod {
  final String password;
  const SshAuthPassword(this.password);
}

class SshAuthPubkey extends SshAuthMethod {
  /// OpenSSH PEM (`-----BEGIN OPENSSH PRIVATE KEY-----`) or PuTTY PPK.
  final Uint8List privateKey;

  /// Required iff the key file is encrypted.
  final String? passphrase;
  const SshAuthPubkey(this.privateKey, {this.passphrase});
}

class SshAuthPubkeyCert extends SshAuthMethod {
  final Uint8List privateKey;
  final String? passphrase;

  /// OpenSSH cert blob (`id_*-cert.pub`).
  final Uint8List cert;
  const SshAuthPubkeyCert(this.privateKey, this.cert, {this.passphrase});
}

class SshAuthAgent extends SshAuthMethod {
  /// Agent-mediated. On Unix uses `$SSH_AUTH_SOCK`; on Windows
  /// OpenSSH-Agent named pipe / Pageant. Covers FIDO2 sk-* keys
  /// when registered (`ssh-add -K`).
  const SshAuthAgent();
}

/// Reference-shaped variants — plaintext bytes live in the Rust
/// core's SecretStore; Dart hands over IDs only. Mixing a Ref
/// variant into a [SshConnectRequest] tells [RustTransport.connect]
/// to call the `ssh_connect_*_with_secret` FRB variants which
/// resolve the IDs Rust-side without round-tripping plaintext.

class SshAuthPasswordRef extends SshAuthMethod {
  final String passwordSecretId;
  const SshAuthPasswordRef(this.passwordSecretId);
}

class SshAuthPubkeyRef extends SshAuthMethod {
  final String keySecretId;

  /// Required iff the key file is encrypted.
  final String? passphraseSecretId;
  const SshAuthPubkeyRef(this.keySecretId, {this.passphraseSecretId});
}

class SshAuthPubkeyCertRef extends SshAuthMethod {
  final String keySecretId;
  final String certSecretId;
  final String? passphraseSecretId;
  const SshAuthPubkeyCertRef(
    this.keySecretId,
    this.certSecretId, {
    this.passphraseSecretId,
  });
}

/// PTY-backed interactive shell channel.
abstract class SshShellChannel {
  /// Stdin: write user keystrokes / pasted bytes.
  Future<void> write(Uint8List data);

  /// Stdout / stderr / EOF / exit-status / exit-signal events.
  /// Single-subscriber per channel.
  Stream<SshShellEvent> get events;

  /// Notify the remote of a terminal-window resize.
  Future<void> resize({required int cols, required int rows});

  /// Half-close stdin. Server typically interprets this as
  /// "user closed stdin" and exits the foreground program.
  Future<void> eof();

  /// Tear down the channel. Idempotent.
  Future<void> close();
}

/// Events delivered by [SshShellChannel.events].
sealed class SshShellEvent {
  const SshShellEvent();
}

class SshShellOutput extends SshShellEvent {
  final Uint8List bytes;
  const SshShellOutput(this.bytes);
}

class SshShellExtendedOutput extends SshShellEvent {
  final Uint8List bytes;
  const SshShellExtendedOutput(this.bytes);
}

class SshShellEof extends SshShellEvent {
  const SshShellEof();
}

class SshShellExitStatus extends SshShellEvent {
  final int code;
  const SshShellExitStatus(this.code);
}

class SshShellExitSignal extends SshShellEvent {
  final String signal;
  const SshShellExitSignal(this.signal);
}

/// Bidirectional byte channel from a `direct-tcpip` open (`-L` /
/// ProxyJump primitive).
abstract class SshDirectTcpipChannel {
  Future<void> write(Uint8List data);

  /// Returns `null` once the channel is fully closed.
  Future<Uint8List?> read();

  Future<void> eof();
  Future<void> close();
}

/// One inbound `-R` forwarded connection delivered through
/// [SshTransport.forwardedConnections]. Caller bridges the channel
/// to a local socket of choice.
class SshForwardedConnection {
  final String connectedAddress;
  final int connectedPort;
  final String originatorAddress;
  final int originatorPort;
  final SshDirectTcpipChannel channel;

  const SshForwardedConnection({
    required this.connectedAddress,
    required this.connectedPort,
    required this.originatorAddress,
    required this.originatorPort,
    required this.channel,
  });
}

/// Connection + handshake failed — TCP refused, host-key rejected,
/// timeout. Distinguished from [SshAuthFailed] so the UI can show
/// "host unreachable" vs "wrong password" without parsing strings.
class SshConnectError implements Exception {
  final String message;
  const SshConnectError(this.message);
  @override
  String toString() => 'SshConnectError: $message';
}

/// Authentication failed — every supplied method was rejected. UI
/// should prompt for re-entry / different auth.
class SshAuthFailed implements Exception {
  const SshAuthFailed();
  @override
  String toString() => 'SshAuthFailed';
}

/// Host-key verification rejected the server's key. Distinct from
/// [SshConnectError] so callers can surface a TOFU mismatch
/// confirm-dialog instead of a generic error toast.
class SshHostKeyRejected implements Exception {
  final String fingerprint;
  const SshHostKeyRejected(this.fingerprint);
  @override
  String toString() => 'SshHostKeyRejected: $fingerprint';
}
