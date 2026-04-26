// RustTransport — `SshTransport` implementation backed by the Rust
// security/transport core via the FRB bindings (lib/src/rust/api/*).
//
// Wraps the engine-specific FRB types (`rust_ssh.SshSession`,
// `SshShell`, `SshForwardChannel`, `SshSftp`) behind the
// engine-agnostic abstraction. The unified Dart-side dispatch in
// session_connect.dart picks this transport when the
// `useRustSshTransport` flag is on.
//
// Sub-phase 1.5+ of the Rust core migration (see
// docs/RUST_CORE_MIGRATION_PLAN.md §13).

import 'dart:async';
import 'dart:typed_data';

import '../../../src/rust/api/forward.dart' as rust_forward;
import '../../../src/rust/api/sftp.dart' as rust_sftp;
import '../../../src/rust/api/ssh.dart' as rust_ssh;
import '../../../utils/logger.dart';
import 'ssh_transport.dart';

class RustTransport implements SshTransport {
  rust_ssh.SshSession? _session;
  final StreamController<SshForwardedConnection> _forwardCtrl =
      StreamController<SshForwardedConnection>.broadcast();
  Future<void>? _forwardPump;
  bool _disconnected = false;

  @override
  bool get isConnected => _session != null && !_disconnected;

  @override
  Future<void> connect(SshConnectRequest request) async {
    if (_session != null) {
      throw StateError('RustTransport.connect called twice');
    }
    final auth = request.auth;
    try {
      _session = await switch (auth) {
        SshAuthPassword() => rust_ssh.sshConnectPassword(
          host: request.host,
          port: request.port,
          user: request.user,
          password: auth.password,
        ),
        SshAuthPubkey() => rust_ssh.sshConnectPubkey(
          host: request.host,
          port: request.port,
          user: request.user,
          privateKey: auth.privateKey,
          passphrase: auth.passphrase,
        ),
        SshAuthPubkeyCert() => rust_ssh.sshConnectPubkeyCert(
          host: request.host,
          port: request.port,
          user: request.user,
          privateKey: auth.privateKey,
          passphrase: auth.passphrase,
          cert: auth.cert,
        ),
        SshAuthAgent() => rust_ssh.sshConnectAgent(
          host: request.host,
          port: request.port,
          user: request.user,
        ),
        // Secret-store-backed variants. The plaintext never crosses
        // the FRB boundary at connect time; Rust resolves the IDs
        // against the SecretStore.
        SshAuthPasswordRef() => rust_ssh.sshConnectPasswordWithSecret(
          host: request.host,
          port: request.port,
          user: request.user,
          passwordSecretId: auth.passwordSecretId,
        ),
        SshAuthPubkeyRef() => rust_ssh.sshConnectPubkeyWithSecret(
          host: request.host,
          port: request.port,
          user: request.user,
          keySecretId: auth.keySecretId,
          passphraseSecretId: auth.passphraseSecretId,
        ),
        SshAuthPubkeyCertRef() => rust_ssh.sshConnectPubkeyCertWithSecret(
          host: request.host,
          port: request.port,
          user: request.user,
          keySecretId: auth.keySecretId,
          certSecretId: auth.certSecretId,
          passphraseSecretId: auth.passphraseSecretId,
        ),
      };
    } catch (e) {
      throw _classifyConnectError(e);
    }
    _startForwardPump();
  }

  /// Connect this transport over a `direct-tcpip` channel on
  /// [parent] — the ProxyJump bastion-chain primitive. Composable:
  /// the resulting transport can itself act as a parent for the next
  /// hop. Reuses the standard auth dispatch on the Rust side so cert
  /// / agent / pubkey auth work identically over a ProxyJump tunnel
  /// and over a direct TCP dial.
  Future<void> connectViaProxy(
    RustTransport parent,
    SshConnectRequest request,
  ) async {
    if (_session != null) {
      throw StateError('RustTransport.connectViaProxy called twice');
    }
    final parentSession = parent._session;
    if (parentSession == null || parent._disconnected) {
      throw const SshConnectError('proxy parent not connected');
    }
    final auth = request.auth;
    try {
      _session = await switch (auth) {
        SshAuthPassword() => rust_ssh.sshConnectPasswordViaProxy(
          parent: parentSession,
          host: request.host,
          port: request.port,
          user: request.user,
          password: auth.password,
        ),
        SshAuthPubkey() => rust_ssh.sshConnectPubkeyViaProxy(
          parent: parentSession,
          host: request.host,
          port: request.port,
          user: request.user,
          privateKey: auth.privateKey,
          passphrase: auth.passphrase,
        ),
        SshAuthPubkeyCert() => rust_ssh.sshConnectPubkeyCertViaProxy(
          parent: parentSession,
          host: request.host,
          port: request.port,
          user: request.user,
          privateKey: auth.privateKey,
          passphrase: auth.passphrase,
          cert: auth.cert,
        ),
        SshAuthAgent() => throw const SshConnectError(
          'ssh-agent auth via ProxyJump is not supported on this build — '
          'the agent client futures are not Send and the proxy variant '
          'cannot be wrapped through FRB. Use a key (or key+cert) on the '
          'inner hop, or run the agent on the bastion itself.',
        ),
        // Secret-store-backed ProxyJump variants are not yet
        // exposed on the Rust side. The proxy connect path is rare
        // enough that adding the parallel surface waits for a real
        // user need; for now ConnectionManager falls through to the
        // plaintext variants when a Ref slips through.
        SshAuthPasswordRef() ||
        SshAuthPubkeyRef() ||
        SshAuthPubkeyCertRef() => throw const SshConnectError(
          'secret-ref auth via ProxyJump is not yet wired — '
          'fall back to the plaintext SshAuthPassword / '
          'SshAuthPubkey / SshAuthPubkeyCert variants on the '
          'inner hop.',
        ),
      };
    } catch (e) {
      throw _classifyConnectError(e);
    }
    _startForwardPump();
  }

  Object _classifyConnectError(Object e) {
    final msg = e.toString();
    if (msg.contains('authentication failed') || msg.contains('AuthFailed')) {
      return const SshAuthFailed();
    }
    if (msg.contains('host key')) {
      return const SshHostKeyRejected('');
    }
    if (msg.contains('connect failed') || msg.contains('Connect')) {
      return SshConnectError(msg);
    }
    return SshConnectError(msg);
  }

  @override
  Future<SshShellChannel> openShell({
    required int cols,
    required int rows,
  }) async {
    final session = _requireSession();
    final t0 = DateTime.now();
    AppLogger.instance.log(
      'RustTransport.openShell: requesting (${cols}x$rows)',
      name: 'RustTransport',
    );
    final shell = await session.openShell(cols: cols, rows: rows);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    AppLogger.instance.log(
      'RustTransport.openShell: got SshShell in ${ms}ms',
      name: 'RustTransport',
    );
    return _RustShell(shell);
  }

  @override
  Future<rust_sftp.SshSftp> openSftp() async {
    final session = _requireSession();
    final t0 = DateTime.now();
    AppLogger.instance.log(
      'RustTransport.openSftp: requesting',
      name: 'RustTransport',
    );
    final sftp = await rust_sftp.sshOpenSftp(session: session);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    AppLogger.instance.log(
      'RustTransport.openSftp: got SshSftp in ${ms}ms',
      name: 'RustTransport',
    );
    return sftp;
  }

  @override
  Future<SshDirectTcpipChannel> openDirectTcpip({
    required String hostToConnect,
    required int portToConnect,
    required String originatorAddress,
    required int originatorPort,
  }) async {
    final session = _requireSession();
    final ch = await rust_forward.sshOpenDirectTcpip(
      session: session,
      hostToConnect: hostToConnect,
      portToConnect: portToConnect,
      originatorAddress: originatorAddress,
      originatorPort: originatorPort,
    );
    return _RustDirectTcpip(ch);
  }

  @override
  Future<int> requestRemoteForward(String address, int port) async {
    final session = _requireSession();
    return await rust_forward.sshRequestRemoteForward(
      session: session,
      address: address,
      port: port,
    );
  }

  @override
  Future<void> cancelRemoteForward(String address, int port) async {
    final session = _requireSession();
    await rust_forward.sshCancelRemoteForward(
      session: session,
      address: address,
      port: port,
    );
  }

  @override
  Stream<SshForwardedConnection> get forwardedConnections =>
      _forwardCtrl.stream;

  /// Long-running pump that polls `ssh_next_forwarded_connection` and
  /// republishes each connection as a Dart-side event. Quits when
  /// the receiver returns null (session closed) or the transport
  /// disconnects.
  void _startForwardPump() {
    final session = _session;
    if (session == null) return;
    _forwardPump = () async {
      while (!_disconnected) {
        final fwd = await rust_forward.sshNextForwardedConnection(
          session: session,
        );
        if (fwd == null) break;
        final inner = await _RustForwardedChannel.fromConnection(fwd);
        _forwardCtrl.add(
          SshForwardedConnection(
            connectedAddress: fwd.connectedAddress,
            connectedPort: fwd.connectedPort,
            originatorAddress: fwd.originatorAddress,
            originatorPort: fwd.originatorPort,
            channel: inner,
          ),
        );
      }
    }();
  }

  @override
  Future<void> disconnect() async {
    if (_disconnected) return;
    _disconnected = true;
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.disconnect();
      } catch (_) {
        // Best-effort — session already torn down.
      }
    }
    await _forwardPump;
    await _forwardCtrl.close();
  }

  rust_ssh.SshSession _requireSession() {
    final s = _session;
    if (s == null) {
      throw const SshConnectError('transport not connected');
    }
    return s;
  }
}

class _RustShell implements SshShellChannel {
  _RustShell(this._inner) {
    _eventsCtrl = StreamController<SshShellEvent>(
      onListen: () {
        // Pump only on first listener — `events_stream` is single-
        // subscriber per shell on the Rust side because the read
        // half is serialised behind a Mutex.
        _eventsSub = _inner.eventsStream().listen((event) {
          _eventsCtrl.add(_mapEvent(event));
        }, onDone: _eventsCtrl.close);
      },
      onCancel: () async {
        await _eventsSub?.cancel();
        await _eventsCtrl.close();
      },
    );
  }

  final rust_ssh.SshShell _inner;
  late final StreamController<SshShellEvent> _eventsCtrl;
  StreamSubscription<rust_ssh.SshShellEvent>? _eventsSub;

  static SshShellEvent _mapEvent(rust_ssh.SshShellEvent event) {
    return event.when(
      output: (b) => SshShellOutput(b),
      extendedOutput: (b) => SshShellExtendedOutput(b),
      eof: () => const SshShellEof(),
      exitStatus: (c) => SshShellExitStatus(c),
      exitSignal: (s) => SshShellExitSignal(s),
    );
  }

  @override
  Stream<SshShellEvent> get events => _eventsCtrl.stream;

  @override
  Future<void> write(Uint8List data) => _inner.write(data: data);

  @override
  Future<void> resize({required int cols, required int rows}) =>
      _inner.resize(cols: cols, rows: rows);

  @override
  Future<void> eof() => _inner.eof();

  @override
  Future<void> close() async {
    await _eventsSub?.cancel();
    await _eventsCtrl.close();
    // Rust shell drops automatically when the wrapper goes out of
    // scope — no explicit close call needed at the FRB layer.
  }
}

class _RustDirectTcpip implements SshDirectTcpipChannel {
  _RustDirectTcpip(this._inner);
  final rust_forward.SshForwardChannel _inner;

  @override
  Future<void> write(Uint8List data) => _inner.write(data: data);

  @override
  Future<Uint8List?> read() async {
    final bytes = await _inner.read();
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> eof() => _inner.eof();

  @override
  Future<void> close() async {
    // FRB opaque drops the underlying channel.
  }
}

class _RustForwardedChannel implements SshDirectTcpipChannel {
  _RustForwardedChannel._(this._inner);
  final rust_forward.SshForwardedConnection _inner;

  static Future<_RustForwardedChannel> fromConnection(
    rust_forward.SshForwardedConnection inner,
  ) async {
    return _RustForwardedChannel._(inner);
  }

  @override
  Future<void> write(Uint8List data) => _inner.write(data: data);

  @override
  Future<Uint8List?> read() async {
    final bytes = await _inner.read();
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> eof() => _inner.eof();

  @override
  Future<void> close() async {
    // FRB opaque drops the underlying channel.
  }
}
