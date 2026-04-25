import 'dart:async';
import 'dart:io';

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

  /// Subscriptions that pump bytes between a local socket and an SSH
  /// channel. Tracked so a transport teardown can cancel them
  /// without leaking the underlying handles.
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
  }

  Future<void> _openListener(SSHClient client, PortForwardRule rule) async {
    if (rule.kind != PortForwardKind.local) {
      _statusController.add(
        PortForwardStatusEvent(
          rule.id,
          PortForwardStatus.error,
          message: 'Only local (-L) forwards supported in this build',
        ),
      );
      return;
    }
    final reason = rule.validate();
    if (reason != null) {
      _statusController.add(
        PortForwardStatusEvent(
          rule.id,
          PortForwardStatus.error,
          message: reason,
        ),
      );
      return;
    }

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
        onError: (Object e) {
          _statusController.add(
            PortForwardStatusEvent(
              rule.id,
              PortForwardStatus.error,
              message: e.toString(),
            ),
          );
        },
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to open port-forward listener',
        name: 'PortForward',
        error: e,
      );
      _statusController.add(
        PortForwardStatusEvent(
          rule.id,
          PortForwardStatus.error,
          message: e.toString(),
        ),
      );
    }
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

  /// Drop the broadcast controller. Call from `Connection`'s dispose
  /// path or the provider's onDispose to avoid leaking the stream.
  void dispose() {
    _teardown();
    _statusController.close();
  }
}
