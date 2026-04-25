import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../utils/logger.dart';
import '../connection/connection.dart';
import '../connection/connection_extension.dart';
import 'port_forward_rule.dart';

/// Status surfaced for a single rule. UI listens via
/// [PortForwardRuntime.statusStream] to colour-code rule rows.
enum PortForwardStatus { idle, listening, error }

class PortForwardStatusEvent {
  final String ruleId;
  final PortForwardStatus status;
  final String? message;
  const PortForwardStatusEvent(this.ruleId, this.status, {this.message});
}

/// Opens listeners for every enabled [PortForwardRule] when the SSH
/// transport becomes live and tears them down on disconnect /
/// reconnect.
///
/// Implements [ConnectionExtension] so [Connection] / [ConnectionManager]
/// drive the lifecycle without per-feature wiring. The runtime is
/// constructed by the connection provider when a session has any
/// enabled rule; reconnects reuse the same instance so the rule list
/// survives the transport teardown — the live `ServerSocket` and
/// in-flight tunnel streams do not.
///
/// **v1 scope: local forwards (-L) only.** Remote (-R) and dynamic
/// (-D) rules are accepted by the persistence layer but the runtime
/// emits a one-off "unsupported in v1" status event and skips them.
/// The plan in `docs/FEATURE_BACKLOG.md §3.1` covers the follow-up
/// work for remote / dynamic.
class PortForwardRuntime implements ConnectionExtension {
  @override
  final String id = 'port-forward-runtime';

  /// Mutable rule list — the UI calls [setRules] after each save so
  /// reconnects pick up edits without a roundtrip.
  List<PortForwardRule> _rules;

  final _statusController =
      StreamController<PortForwardStatusEvent>.broadcast();

  /// Active local listeners keyed by rule id. Populated on connect,
  /// drained on disconnect / reconnect.
  final _listeners = <String, ServerSocket>{};

  /// Active server-side `tcpip-forward` registrations keyed by rule
  /// id. Closing each cancels the registration with the SSH server
  /// in addition to closing the broadcast stream.
  final _remoteForwards = <String, SSHRemoteForward>{};

  /// Subscriptions that pump bytes between a local socket and an SSH
  /// channel — plus the per-rule "incoming connections" subscriptions
  /// for remote forwards. Tracked so a transport teardown can cancel
  /// them without leaking the underlying handles.
  final _activeTunnels = <StreamSubscription<dynamic>>[];

  PortForwardRuntime({List<PortForwardRule> rules = const []})
    : _rules = List.unmodifiable(rules);

  Stream<PortForwardStatusEvent> get statusStream => _statusController.stream;

  /// Replace the active rule set. The runtime does **not** open new
  /// listeners on the spot — call [reattach] (typically wired into
  /// [Connection.notifyExtensionsConnected] on the next reconnect)
  /// when the connection is alive and the new set should take effect.
  void setRules(List<PortForwardRule> rules) {
    _rules = List.unmodifiable(rules);
  }

  List<PortForwardRule> get rules => _rules;

  @override
  void onConnected(Connection connection) {
    final client = connection.sshConnection?.client;
    if (client == null) return;
    for (final rule in _rules.where((r) => r.enabled)) {
      _openListener(client, rule);
    }
  }

  @override
  void onDisconnecting(Connection connection) => _teardown();

  @override
  void onReconnecting(Connection connection) => _teardown();

  void _teardown() {
    for (final sub in _activeTunnels) {
      // Best-effort cancel — a sub that was already cancelled (its
      // upstream stream closed first) returns a completed future.
      unawaited(sub.cancel());
    }
    _activeTunnels.clear();
    for (final entry in _listeners.entries) {
      final ruleId = entry.key;
      try {
        entry.value.close();
      } catch (e) {
        AppLogger.instance.log(
          'Failed to close port-forward listener',
          name: 'PortForward',
          error: e,
        );
      }
      _statusController.add(
        PortForwardStatusEvent(ruleId, PortForwardStatus.idle),
      );
    }
    _listeners.clear();
    for (final entry in _remoteForwards.entries) {
      final ruleId = entry.key;
      try {
        entry.value.close();
      } catch (e) {
        AppLogger.instance.log(
          'Failed to close remote port-forward',
          name: 'PortForward',
          error: e,
        );
      }
      _statusController.add(
        PortForwardStatusEvent(ruleId, PortForwardStatus.idle),
      );
    }
    _remoteForwards.clear();
  }

  Future<void> _openListener(SSHClient client, PortForwardRule rule) async {
    final reason = rule.validate();
    if (reason != null) {
      _emitError(rule.id, reason);
      return;
    }
    switch (rule.kind) {
      case PortForwardKind.local:
        await _openLocalListener(client, rule);
        break;
      case PortForwardKind.remote:
        await _openRemoteForward(client, rule);
        break;
      case PortForwardKind.dynamic_:
        await _openDynamicListener(client, rule);
        break;
    }
  }

  void _emitError(String ruleId, String message) {
    _statusController.add(
      PortForwardStatusEvent(ruleId, PortForwardStatus.error, message: message),
    );
  }

  Future<void> _openLocalListener(
    SSHClient client,
    PortForwardRule rule,
  ) async {
    try {
      final server = await ServerSocket.bind(
        rule.bindHost,
        rule.bindPort,
        shared: false,
      );
      _listeners[rule.id] = server;
      _statusController.add(
        PortForwardStatusEvent(rule.id, PortForwardStatus.listening),
      );
      AppLogger.instance.log(
        'Port-forward listening: ${rule.bindHost}:${rule.bindPort} -> '
        '<remote>:${rule.remotePort}',
        name: 'PortForward',
      );
      server.listen(
        (socket) => _bridgeIncoming(client, rule, socket),
        onError: (Object e) => _emitError(rule.id, e.toString()),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open port-forward listener',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  /// Open a remote (`-R`) forward — the SSH server listens on
  /// `bindHost:bindPort` and pipes every accepted connection back
  /// through the channel; we dial out locally to
  /// `remoteHost:remotePort` and bridge.
  ///
  /// **`bindHost` semantics on remote forwards.** OpenSSH reserves
  /// wildcard binds (`0.0.0.0` / empty) for the server's
  /// `GatewayPorts yes` configuration. dartssh2 just sends the
  /// `tcpip-forward` request through; the server may refuse with
  /// `SSH_MSG_REQUEST_FAILURE` and we surface that as an error
  /// status event. No client-side filtering — the user's intent is
  /// honoured and the server's policy is what enforces it.
  Future<void> _openRemoteForward(
    SSHClient client,
    PortForwardRule rule,
  ) async {
    try {
      final remote = await client.forwardRemote(
        host: rule.bindHost,
        port: rule.bindPort,
      );
      if (remote == null) {
        _emitError(
          rule.id,
          'Server refused remote forward on ${rule.bindHost}:${rule.bindPort} '
          '(check GatewayPorts / port permissions)',
        );
        return;
      }
      _remoteForwards[rule.id] = remote;
      _statusController.add(
        PortForwardStatusEvent(rule.id, PortForwardStatus.listening),
      );
      AppLogger.instance.log(
        'Remote port-forward registered: server <bind> -> '
        'local <target>',
        name: 'PortForward',
      );
      final sub = remote.connections.listen(
        (channel) => _bridgeRemoteIncoming(rule, channel),
        onError: (Object e) => _emitError(rule.id, e.toString()),
      );
      _activeTunnels.add(sub);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to register remote forward',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  /// Server-side accepted a connection, dartssh2 handed us the
  /// channel — open a local socket to `remoteHost:remotePort` and
  /// bridge bytes both ways. Mirror of [_bridgeIncoming] with the
  /// directions swapped.
  Future<void> _bridgeRemoteIncoming(
    PortForwardRule rule,
    SSHForwardChannel channel,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(rule.remoteHost, rule.remotePort);
    } catch (e) {
      AppLogger.instance.log(
        'Remote forward dial-out failed',
        name: 'PortForward',
        error: e,
      );
      // Best-effort close so the server side does not hang.
      await channel.sink.close();
      return;
    }
    final outbound = channel.stream.listen(
      socket.add,
      onError: (Object e) {
        AppLogger.instance.log(
          'Remote forward outbound error',
          name: 'PortForward',
          error: e,
        );
      },
      onDone: socket.destroy,
      cancelOnError: true,
    );
    final inbound = socket.listen(
      channel.sink.add,
      onError: (Object e) {
        AppLogger.instance.log(
          'Remote forward inbound error',
          name: 'PortForward',
          error: e,
        );
      },
      onDone: () {
        // ignore: discarded_futures
        channel.sink.close();
      },
      cancelOnError: true,
    );
    _activeTunnels
      ..add(outbound)
      ..add(inbound);
  }

  Future<void> _bridgeIncoming(
    SSHClient client,
    PortForwardRule rule,
    Socket socket,
  ) async {
    SSHForwardChannel? channel;
    try {
      channel = await client.forwardLocal(rule.remoteHost, rule.remotePort);
    } catch (e) {
      AppLogger.instance.log(
        'Port-forward channel open failed',
        name: 'PortForward',
        error: e,
      );
      socket.destroy();
      return;
    }
    // Local socket → SSH channel.
    final outbound = socket.listen(
      channel.sink.add,
      onError: (Object e) {
        AppLogger.instance.log(
          'Port-forward outbound error',
          name: 'PortForward',
          error: e,
        );
      },
      onDone: () {
        // ignore: discarded_futures
        channel?.sink.close();
      },
      cancelOnError: true,
    );
    // SSH channel → local socket.
    final inbound = channel.stream.listen(
      socket.add,
      onError: (Object e) {
        AppLogger.instance.log(
          'Port-forward inbound error',
          name: 'PortForward',
          error: e,
        );
      },
      onDone: socket.destroy,
      cancelOnError: true,
    );
    _activeTunnels
      ..add(outbound)
      ..add(inbound);
  }

  /// Open a dynamic (`-D`) SOCKS5 listener. Each accepted local
  /// socket runs through the SOCKS5 greeting + CONNECT request,
  /// and the resolved `(host, port)` target is dialed via
  /// `forwardLocal` so the SSH server reaches it on the user's
  /// behalf.
  ///
  /// **Hand-rolled SOCKS5 CONNECT-only.** RFC 1928 with auth
  /// method `0x00 NO_AUTH` and command `0x01 CONNECT` only — no
  /// BIND, no UDP ASSOCIATE, no GSSAPI. The trimmed surface keeps
  /// us off any pub.dev SOCKS package and preserves the zero-
  /// install rule. Address types covered: IPv4 (`0x01`), domain
  /// (`0x03`), IPv6 (`0x04`).
  Future<void> _openDynamicListener(
    SSHClient client,
    PortForwardRule rule,
  ) async {
    try {
      final server = await ServerSocket.bind(
        rule.bindHost,
        rule.bindPort,
        shared: false,
      );
      _listeners[rule.id] = server;
      _statusController.add(
        PortForwardStatusEvent(rule.id, PortForwardStatus.listening),
      );
      AppLogger.instance.log(
        'SOCKS5 dynamic forward listening: ${rule.bindHost}:${rule.bindPort}',
        name: 'PortForward',
      );
      server.listen(
        (socket) => _handleSocksClient(client, rule.id, socket),
        onError: (Object e) => _emitError(rule.id, e.toString()),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open dynamic forward listener',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  Future<void> _handleSocksClient(
    SSHClient client,
    String ruleId,
    Socket socket,
  ) async {
    final reader = _SocksReader(socket);
    try {
      // Greeting: [VER=0x05][NMETHODS][methods...]
      final greeting = await reader.read(2);
      if (greeting[0] != 0x05) {
        await _socksFail(socket, 0x07); // command not supported
        return;
      }
      final nMethods = greeting[1];
      await reader.read(nMethods); // discard methods — we only do NO_AUTH
      socket.add(<int>[0x05, 0x00]); // method = NO_AUTH

      // Request: [VER=0x05][CMD][RSV=0x00][ATYP][...]
      final reqHead = await reader.read(4);
      if (reqHead[0] != 0x05) {
        await _socksFail(socket, 0x07);
        return;
      }
      final cmd = reqHead[1];
      if (cmd != 0x01) {
        // 0x07 = command not supported
        await _socksFail(socket, 0x07);
        return;
      }
      final atyp = reqHead[3];
      String host;
      switch (atyp) {
        case 0x01: // IPv4
          final addr = await reader.read(4);
          host = addr.join('.');
          break;
        case 0x03: // domain name
          final lenByte = await reader.read(1);
          final domain = await reader.read(lenByte[0]);
          host = utf8.decode(domain);
          break;
        case 0x04: // IPv6
          final addr = await reader.read(16);
          host = _formatIpv6(addr);
          break;
        default:
          await _socksFail(socket, 0x08); // address type not supported
          return;
      }
      final portBytes = await reader.read(2);
      final port = (portBytes[0] << 8) | portBytes[1];

      SSHForwardChannel? channel;
      try {
        channel = await client.forwardLocal(host, port);
      } catch (e) {
        AppLogger.instance.log(
          'SOCKS5 forwardLocal failed',
          name: 'PortForward',
          error: e,
        );
        await _socksFail(socket, 0x05); // connection refused
        return;
      }

      // Reply: [VER=0x05][REP=0x00 success][RSV][ATYP=0x01][BND=0.0.0.0][PORT=0]
      socket.add(<int>[
        0x05,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);

      // Bridge bytes both ways — same shape as -L. The SOCKS
      // reader holds the socket's only subscription (Socket is a
      // single-subscription stream); flush its buffered tail to
      // the SSH channel and rebind its onData/onDone handlers
      // instead of cancelling + relistening.
      final tail = reader.consumeBuffered();
      if (tail.isNotEmpty) {
        channel.sink.add(tail);
      }
      final boundChannel = channel;
      reader.handOver(
        onData: boundChannel.sink.add,
        onError: (Object e) {
          AppLogger.instance.log(
            'SOCKS5 outbound error',
            name: 'PortForward',
            error: e,
          );
        },
        onDone: () {
          // ignore: discarded_futures
          boundChannel.sink.close();
        },
      );
      final inbound = channel.stream.listen(
        socket.add,
        onError: (Object e) {
          AppLogger.instance.log(
            'SOCKS5 inbound error',
            name: 'PortForward',
            error: e,
          );
        },
        onDone: socket.destroy,
        cancelOnError: true,
      );
      _activeTunnels.add(inbound);
    } catch (e) {
      AppLogger.instance.log(
        'SOCKS5 handshake failed',
        name: 'PortForward',
        error: e,
      );
      socket.destroy();
    }
  }

  Future<void> _socksFail(Socket socket, int rep) async {
    socket.add(<int>[
      0x05,
      rep,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
    await socket.flush();
    socket.destroy();
  }

  String _formatIpv6(Uint8List bytes) {
    final groups = <String>[];
    for (var i = 0; i < 16; i += 2) {
      final word = (bytes[i] << 8) | bytes[i + 1];
      groups.add(word.toRadixString(16));
    }
    return groups.join(':');
  }

  /// Drop the broadcast controller. Call from `Connection`'s dispose
  /// path or the provider's onDispose to avoid leaking the stream.
  void dispose() {
    _teardown();
    _statusController.close();
  }
}

/// Pull-style reader over an incoming `Socket` for the SOCKS5
/// handshake. The socket's primary `listen` happens after the
/// handshake completes (the runtime takes over); during the
/// handshake we pull byte-by-byte from a private subscription that
/// we cancel before handing the socket back via [detach].
class _SocksReader {
  _SocksReader(this._socket) {
    _sub = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final _buffer = BytesBuilder(copy: false);
  Completer<void>? _waiter;
  Object? _error;
  bool _done = false;

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    final w = _waiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _onError(Object error) {
    _error = error;
    final w = _waiter;
    if (w != null && !w.isCompleted) w.completeError(error);
  }

  void _onDone() {
    _done = true;
    final w = _waiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> read(int n) async {
    while (_buffer.length < n) {
      if (_error != null) throw _error!;
      if (_done) {
        throw const SocketException('SOCKS5 client closed mid-handshake');
      }
      _waiter = Completer<void>();
      await _waiter!.future;
      _waiter = null;
    }
    final all = _buffer.takeBytes();
    final out = Uint8List.fromList(all.sublist(0, n));
    if (all.length > n) {
      _buffer.add(all.sublist(n));
    }
    return out;
  }

  /// Re-bind the underlying subscription's handlers so post-
  /// handshake bytes flow into the bridge sink. We can't
  /// `socket.listen(...)` again — `Socket` is single-subscription —
  /// so swapping handlers on the live `StreamSubscription` is the
  /// only safe transfer. Any bytes already buffered must have been
  /// drained via [consumeBuffered] BEFORE this call.
  void handOver({
    required void Function(Uint8List) onData,
    required void Function(Object) onError,
    required void Function() onDone,
  }) {
    _sub.onData(onData);
    _sub.onError(onError);
    _sub.onDone(onDone);
  }

  Uint8List consumeBuffered() => _buffer.takeBytes();
}
