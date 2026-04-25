import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/logger.dart';
import '../connection/connection.dart';
import '../connection/connection_extension.dart';
import 'port_forward_rule.dart';
import 'transport/ssh_transport.dart';

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
/// Pulls [SshTransport] off `connection.transport` and drives
/// `openDirectTcpip` per accepted local socket (-L / -D), or
/// `requestRemoteForward` + the transport-wide `forwardedConnections`
/// Stream (-R). All three rule kinds (local / remote / dynamic) ride
/// the same primitives.
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

  /// Streaming subscription on `transport.forwardedConnections` that
  /// dispatches inbound `-R` connections to the matching rule. One
  /// subscription per transport — rebuilt on reconnect.
  StreamSubscription<SshForwardedConnection>? _transportForwardSub;

  /// Live transport-side `-R` registrations keyed by rule id. Used at
  /// teardown to call `transport.cancelRemoteForward` for each one.
  final _transportRemoteForwards = <String, ({String address, int port})>{};

  /// Active transport reference — captured so [_teardown] can call
  /// `cancelRemoteForward` without re-routing through `Connection`.
  SshTransport? _transport;

  @override
  void onConnected(Connection connection) {
    final transport = connection.transport;
    if (transport != null) {
      _onConnectedViaTransport(transport);
    }
  }

  void _onConnectedViaTransport(SshTransport transport) {
    _transport = transport;
    // Map remote-forward (server bind host, port) tuples to rule ids
    // so the single transport-wide stream of inbound connections can
    // route each event to the matching rule's bridge. Tuple key is
    // "host:port" (matched after the server confirms the bind).
    final remoteRoutes = <String, PortForwardRule>{};

    for (final rule in _rules.where((r) => r.enabled)) {
      final reason = rule.validate();
      if (reason != null) {
        _emitError(rule.id, reason);
        continue;
      }
      switch (rule.kind) {
        case PortForwardKind.local:
          unawaited(_openLocalListenerViaTransport(transport, rule));
          break;
        case PortForwardKind.remote:
          unawaited(
            _openRemoteForwardViaTransport(transport, rule, remoteRoutes),
          );
          break;
        case PortForwardKind.dynamic_:
          unawaited(_openDynamicListenerViaTransport(transport, rule));
          break;
      }
    }

    _transportForwardSub = transport.forwardedConnections.listen(
      (event) {
        // Match on connectedPort first — bind port is what the server
        // echoes back. Loopback / wildcard binds collapse to the same
        // port, so the host check is best-effort (server may rewrite
        // 0.0.0.0 → empty string per the spec).
        final route =
            remoteRoutes['${event.connectedAddress}:${event.connectedPort}'] ??
            remoteRoutes[':${event.connectedPort}'] ??
            remoteRoutes['*:${event.connectedPort}'];
        if (route == null) {
          AppLogger.instance.log(
            'Inbound -R for unmatched route ${event.connectedAddress}:${event.connectedPort}',
            name: 'PortForward',
          );
          // Drop the channel — server forwarded a connection we have
          // no rule for (likely a stale bind from a previous reconnect).
          unawaited(event.channel.close());
          return;
        }
        unawaited(_bridgeRemoteIncomingViaTransport(route, event.channel));
      },
      onError: (Object e) {
        AppLogger.instance.log(
          'Transport forwardedConnections error',
          name: 'PortForward',
          error: e,
        );
      },
    );
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
    unawaited(_transportForwardSub?.cancel());
    _transportForwardSub = null;
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
    final transport = _transport;
    if (transport != null) {
      for (final entry in _transportRemoteForwards.entries) {
        final ruleId = entry.key;
        final addr = entry.value;
        unawaited(
          transport.cancelRemoteForward(addr.address, addr.port).catchError((
            Object e,
          ) {
            AppLogger.instance.log(
              'cancelRemoteForward failed (rule=$ruleId)',
              name: 'PortForward',
              error: e,
            );
          }),
        );
        _statusController.add(
          PortForwardStatusEvent(ruleId, PortForwardStatus.idle),
        );
      }
    }
    _transportRemoteForwards.clear();
    _transport = null;
  }

  void _emitError(String ruleId, String message) {
    _statusController.add(
      PortForwardStatusEvent(ruleId, PortForwardStatus.error, message: message),
    );
  }

  // ── Listener / bridge implementations ─────────────────────────────
  // Each helper opens a `ServerSocket` (-L / -D) or registers a
  // server-side `tcpip-forward` (-R), then bridges accepted local
  // connections to a `SshDirectTcpipChannel` via a pair of
  // unidirectional pumps.

  Future<void> _openLocalListenerViaTransport(
    SshTransport transport,
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
        'Port-forward listening (Rust): ${rule.bindHost}:${rule.bindPort} -> '
        '<remote>:${rule.remotePort}',
        name: 'PortForward',
      );
      server.listen(
        (socket) => _bridgeIncomingViaTransport(transport, rule, socket),
        onError: (Object e) => _emitError(rule.id, e.toString()),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open port-forward listener (Rust)',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  Future<void> _openDynamicListenerViaTransport(
    SshTransport transport,
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
        'SOCKS5 dynamic forward listening (Rust): ${rule.bindHost}:${rule.bindPort}',
        name: 'PortForward',
      );
      server.listen(
        (socket) => _handleSocksClientViaTransport(transport, rule.id, socket),
        onError: (Object e) => _emitError(rule.id, e.toString()),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open dynamic forward listener (Rust)',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  Future<void> _openRemoteForwardViaTransport(
    SshTransport transport,
    PortForwardRule rule,
    Map<String, PortForwardRule> remoteRoutes,
  ) async {
    try {
      final boundPort = await transport.requestRemoteForward(
        rule.bindHost,
        rule.bindPort,
      );
      _transportRemoteForwards[rule.id] = (
        address: rule.bindHost,
        port: boundPort,
      );
      // Keep both the requested bind host and the wildcard variants
      // so server-side address rewrites (e.g. 0.0.0.0 → empty string)
      // still match in the route lookup.
      remoteRoutes['${rule.bindHost}:$boundPort'] = rule;
      remoteRoutes[':$boundPort'] = rule;
      remoteRoutes['*:$boundPort'] = rule;
      _statusController.add(
        PortForwardStatusEvent(rule.id, PortForwardStatus.listening),
      );
      AppLogger.instance.log(
        'Remote port-forward registered (Rust): server '
        '${rule.bindHost}:$boundPort -> local <target>',
        name: 'PortForward',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to register remote forward (Rust)',
        name: 'PortForward',
        error: e,
      );
      _emitError(rule.id, e.toString());
    }
  }

  Future<void> _bridgeIncomingViaTransport(
    SshTransport transport,
    PortForwardRule rule,
    Socket socket,
  ) async {
    SshDirectTcpipChannel? channel;
    try {
      channel = await transport.openDirectTcpip(
        hostToConnect: rule.remoteHost,
        portToConnect: rule.remotePort,
        originatorAddress: socket.remoteAddress.address,
        originatorPort: socket.remotePort,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Port-forward channel open failed (Rust)',
        name: 'PortForward',
        error: e,
      );
      socket.destroy();
      return;
    }
    _runBidirectionalPump(socket, channel);
  }

  Future<void> _bridgeRemoteIncomingViaTransport(
    PortForwardRule rule,
    SshDirectTcpipChannel channel,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(rule.remoteHost, rule.remotePort);
    } catch (e) {
      AppLogger.instance.log(
        'Remote forward dial-out failed (Rust)',
        name: 'PortForward',
        error: e,
      );
      // Best-effort tear down so the server side does not hang on a
      // half-open channel.
      await channel.close();
      return;
    }
    _runBidirectionalPump(socket, channel);
  }

  /// Spin up the two unidirectional pumps that bridge a local Socket
  /// and an [SshDirectTcpipChannel]. Either direction completing
  /// destroys the counterpart so a half-close on one side closes the
  /// whole tunnel.
  void _runBidirectionalPump(Socket socket, SshDirectTcpipChannel channel) {
    unawaited(_pumpSocketToChannel(socket, channel));
    unawaited(_pumpChannelToSocket(channel, socket));
  }

  Future<void> _pumpSocketToChannel(
    Socket socket,
    SshDirectTcpipChannel channel,
  ) async {
    try {
      // `await for` serialises the writes — Socket events fire one at
      // a time and we await each `channel.write` before pulling the
      // next chunk, so byte order on the channel matches arrival order
      // off the socket.
      await for (final chunk in socket) {
        await channel.write(chunk);
      }
      await channel.eof();
    } catch (e) {
      AppLogger.instance.log(
        'Port-forward outbound error (Rust)',
        name: 'PortForward',
        error: e,
      );
    } finally {
      // Close from this side — the read pump will then see `null` on
      // `channel.read()` and tear the socket down.
      try {
        await channel.close();
      } catch (_) {}
    }
  }

  Future<void> _pumpChannelToSocket(
    SshDirectTcpipChannel channel,
    Socket socket,
  ) async {
    try {
      while (true) {
        final chunk = await channel.read();
        if (chunk == null) break;
        socket.add(chunk);
      }
      await socket.flush();
    } catch (e) {
      AppLogger.instance.log(
        'Port-forward inbound error (Rust)',
        name: 'PortForward',
        error: e,
      );
    } finally {
      socket.destroy();
    }
  }

  Future<void> _handleSocksClientViaTransport(
    SshTransport transport,
    String ruleId,
    Socket socket,
  ) async {
    final reader = _SocksReader(socket);
    try {
      // Greeting: [VER=0x05][NMETHODS][methods...]
      final greeting = await reader.read(2);
      if (greeting[0] != 0x05) {
        await _socksFail(socket, 0x07);
        return;
      }
      final nMethods = greeting[1];
      await reader.read(nMethods);
      socket.add(<int>[0x05, 0x00]);

      // Request: [VER=0x05][CMD][RSV=0x00][ATYP][...]
      final reqHead = await reader.read(4);
      if (reqHead[0] != 0x05) {
        await _socksFail(socket, 0x07);
        return;
      }
      if (reqHead[1] != 0x01) {
        await _socksFail(socket, 0x07);
        return;
      }
      final atyp = reqHead[3];
      String host;
      switch (atyp) {
        case 0x01:
          final addr = await reader.read(4);
          host = addr.join('.');
          break;
        case 0x03:
          final lenByte = await reader.read(1);
          final domain = await reader.read(lenByte[0]);
          host = utf8.decode(domain);
          break;
        case 0x04:
          final addr = await reader.read(16);
          host = _formatIpv6(addr);
          break;
        default:
          await _socksFail(socket, 0x08);
          return;
      }
      final portBytes = await reader.read(2);
      final port = (portBytes[0] << 8) | portBytes[1];

      SshDirectTcpipChannel? channel;
      try {
        channel = await transport.openDirectTcpip(
          hostToConnect: host,
          portToConnect: port,
          originatorAddress: socket.remoteAddress.address,
          originatorPort: socket.remotePort,
        );
      } catch (e) {
        AppLogger.instance.log(
          'SOCKS5 openDirectTcpip failed (Rust)',
          name: 'PortForward',
          error: e,
        );
        await _socksFail(socket, 0x05);
        return;
      }

      // Reply: [VER=0x05][REP=0x00][RSV][ATYP=0x01][BND=0.0.0.0][PORT=0]
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

      // Drain any bytes the SOCKS reader has buffered ahead of the
      // handshake and forward them before the bidirectional pump
      // takes over.
      final tail = reader.consumeBuffered();
      if (tail.isNotEmpty) {
        await channel.write(tail);
      }

      // Hand the live socket subscription off to a write queue so
      // post-handshake bytes flow into the channel in order. We
      // can't `socket.listen(...)` again — single-subscription —
      // so we mutate the existing subscription's handlers via
      // `_SocksReader.handOver`.
      final boundChannel = channel;
      final queue = _ChannelWriteQueue(boundChannel);
      reader.handOver(
        onData: queue.enqueue,
        onError: (Object e) {
          AppLogger.instance.log(
            'SOCKS5 outbound error (Rust)',
            name: 'PortForward',
            error: e,
          );
        },
        onDone: () => unawaited(queue.flushAndEof()),
      );
      unawaited(_pumpChannelToSocket(boundChannel, socket));
    } catch (e) {
      AppLogger.instance.log(
        'SOCKS5 handshake failed (Rust)',
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

/// Serialised write queue for an [SshDirectTcpipChannel]. The Rust
/// transport's `write` is async; binding it directly to `Socket`'s
/// onData would race when chunks arrive faster than writes complete.
/// The queue chains every write onto a single tail Future so byte
/// order matches arrival order, even when callers are sync.
class _ChannelWriteQueue {
  _ChannelWriteQueue(this._channel);

  final SshDirectTcpipChannel _channel;
  Future<void> _tail = Future<void>.value();

  void enqueue(Uint8List data) {
    _tail = _tail.then((_) => _channel.write(data)).catchError((Object e) {
      AppLogger.instance.log(
        'Port-forward queued write failed',
        name: 'PortForward',
        error: e,
      );
    });
  }

  /// Wait for every queued write to land, then half-close the
  /// channel's write side. Caller invokes this when the local socket
  /// signals end-of-stream.
  Future<void> flushAndEof() async {
    try {
      await _tail;
    } catch (_) {
      // Errors already logged in [enqueue]; we still want to attempt
      // the EOF so the peer isn't left dangling.
    }
    try {
      await _channel.eof();
    } catch (_) {}
  }
}
