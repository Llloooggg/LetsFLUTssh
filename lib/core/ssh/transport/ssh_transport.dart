// SshTransport — abstraction over the SSH layer, backed by the
// Rust security/transport core (`lib/src/rust/api/*`) via the
// flutter_rust_bridge bindings. RustTransport is the only impl;
// the abstraction stays so test mocks can swap in.
//
// Surface:
//   - openShell with PTY size + bidirectional bytes
//   - openSftp returning an engine-agnostic SFTP client
//   - direct-tcpip channel for `-L` / `-D` / ProxyJump primitive
//   - server-side `-R` request (the inbound dispatch + bridging
//     lives in `lfs_core::portforward::driver::spawn_remote_forward`,
//     driven by `portForwardStartRemote` — there is no Dart-side
//     forwarded-connections queue to subscribe to)
//   - graceful disconnect
//
// Connecting + authenticating happens Rust-side in the connection
// actor (see `core/connection/connection_manager.dart` +
// `lfs_core::connection::actor`). The Dart wrapper adopts the
// already-authenticated session via `RustTransport.adopt(session)`
// — there is no Dart-driven `connect` method any more.

import 'dart:async';
import 'dart:typed_data';

/// A bidirectional, engine-agnostic SSH connection.
///
/// Lifecycle: the Rust connection actor produces an authenticated
/// `SshSession`; Dart adopts it via `RustTransport.adopt(session)`
/// and uses [openShell] / [openSftp] / [openDirectTcpip] /
/// [requestRemoteForward] for sub-channels → [disconnect] when
/// done. Drop-equivalent cleanup runs through `disconnect`.
abstract class SshTransport {
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

  /// Cleanly tear down the transport. Sends `SSH_MSG_DISCONNECT`
  /// where supported; idempotent (repeated calls are no-ops).
  Future<void> disconnect();

  /// True iff the transport has connected + authenticated and not
  /// yet been disconnected.
  bool get isConnected;
}

/// Auth method discriminator. Each variant carries the resolved
/// reference into the Rust SecretStore; the connection actor reads
/// the bytes Rust-side without ever pulling plaintext credentials
/// across the FRB boundary.
sealed class SshAuthMethod {
  const SshAuthMethod();
}

class SshAuthAgent extends SshAuthMethod {
  /// Agent-mediated. On Unix uses `$SSH_AUTH_SOCK`; on Windows
  /// OpenSSH-Agent named pipe / Pageant. Covers FIDO2 sk-* keys
  /// when registered (`ssh-add -K`).
  const SshAuthAgent();
}

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

/// FIDO2 hardware-bound `sk-*` SSH key resolved from the manager.
///
/// `publicOpenssh` carries the captured `id_*.pub` body so the Rust
/// connect path can recover the SSH `Algorithm` without a second FRB
/// hop. `credentialId` is the opaque CTAP2 blob the device matches
/// against on every assertion. `application` is the SSH RP-id (the
/// `ssh:` literal in every default `ssh-keygen -t ed25519-sk` flow,
/// but the user can override at generation time).
///
/// `pinSecretId` resolves a transient PIN staged by the Dart-side
/// caller before dispatch (via `connection_prepare_auth` with `pin`
/// populated). `null` for touch-only credentials — the device fires
/// its presence prompt without a PIN round trip.
class SshAuthPubkeySkRef extends SshAuthMethod {
  final String publicOpenssh;
  final Uint8List credentialId;
  final String application;
  final String? pinSecretId;
  const SshAuthPubkeySkRef({
    required this.publicOpenssh,
    required this.credentialId,
    required this.application,
    this.pinSecretId,
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
