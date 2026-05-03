// RustTransport — `SshTransport` implementation backed by the Rust
// security/transport core via the FRB bindings (lib/src/rust/api/*).
//
// Wraps the engine-specific FRB types (`rust_ssh.SshSession`,
// `SshShell`, `SshForwardChannel`, `SshSftp`) behind the
// engine-agnostic abstraction. The session itself is built by the
// Rust connection actor; this Dart wrapper exists to bridge the
// channel-ops surface (`openShell` / `openSftp` /
// `openDirectTcpip` / `requestRemoteForward`) into the engine-
// agnostic `SshTransport` abstraction the rest of the app binds to.
//
// See docs/RUST_CORE_MIGRATION_PLAN.md §13.

import 'dart:async';
import 'dart:typed_data';

import '../../../src/rust/api/forward.dart' as rust_forward;
import '../../../src/rust/api/sftp.dart' as rust_sftp;
import '../../../src/rust/api/ssh.dart' as rust_ssh;
import '../../../utils/logger.dart';
import 'ssh_transport.dart';

class RustTransport implements SshTransport {
  rust_ssh.SshSession? _session;
  bool _disconnected = false;

  RustTransport._adopted(rust_ssh.SshSession session) : _session = session;

  /// Adopt an actor-owned `SshSession`. The adopted transport
  /// surfaces `isConnected = true` immediately so channel ops
  /// (`openShell`, `openSftp`, `openDirectTcpip`,
  /// `requestRemoteForward`) start working without a separate
  /// `connect()` round-trip. Tear-down belongs to the actor —
  /// dispatch `ConnectionDisconnect` over the bus.
  factory RustTransport.adopt(rust_ssh.SshSession session) =>
      RustTransport._adopted(session);

  @override
  bool get isConnected => _session != null && !_disconnected;

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
  Future<void> disconnect() async {
    if (_disconnected) return;
    _disconnected = true;
    _session = null;
    // The adopted session belongs to the connection actor — calling
    // `session.disconnect()` here would clear only this wrapper's
    // slot (the actor still holds its own `Arc<Session>` clone),
    // leaving the actor pointing at a half-torn russh handle.
    // Tear-down happens through the bus command
    // (`ConnectionDisconnect`); the Dart wrapper just flips its
    // own `_disconnected` flag.
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
