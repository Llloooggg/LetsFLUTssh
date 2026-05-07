import 'dart:async';

import '../../src/rust/api/forward.dart' as rust_fwd;
import '../../utils/logger.dart';
import '../connection/connection.dart';
import 'port_forward_rule.dart';

/// Spawns Rust-side port-forward listeners (`-L` / `-D` / `-R`)
/// for every enabled rule when an SSH transport becomes live, and
/// asks them to stop on disconnect / reconnect.
///
/// Listener accept loops, SOCKS5 handshake, the `direct-tcpip`
/// channel bridges, and the inbound dispatcher for `-R` all live
/// in `lfs_core::portforward::driver`. The shim's only job is to
/// translate `ConnectionExtension` lifecycle hooks into FRB
/// `port_forward_start_*` / `port_forward_stop_*` calls keyed by
/// rule id so a teardown can stop exactly the rules this runtime
/// armed.
///
/// Status events (`Listening` / `Error`) flow on the Rust event
/// bus under the rule id; UI subscribers read them off the bus
/// rather than off this object.
class PortForwardRuntime implements ConnectionExtension {
  @override
  final String id = 'port-forward-runtime';

  /// Mutable rule list — the UI calls [setRules] after each save so
  /// a reconnect picks up edits without a roundtrip. Replacing the
  /// list does not re-arm listeners; the next [onConnected] does.
  List<PortForwardRule> _rules;

  /// Rule ids that this runtime has armed against the Rust drivers
  /// for the current transport generation. Drained on [_teardown]
  /// by issuing the matching stop call per kind.
  final _armed = <String, PortForwardKind>{};

  PortForwardRuntime({List<PortForwardRule> rules = const []})
    : _rules = List.unmodifiable(rules);

  void setRules(List<PortForwardRule> rules) {
    _rules = List.unmodifiable(rules);
  }

  List<PortForwardRule> get rules => _rules;

  @override
  void onConnected(Connection connection) {
    if (connection.transport == null) return;
    for (final rule in _rules.where((r) => r.enabled)) {
      final reason = rule.validate();
      if (reason != null) {
        AppLogger.instance.log(
          'Port-forward rule rejected: $reason',
          name: 'PortForward',
          level: LogLevel.warn,
        );
        continue;
      }
      _armed[rule.id] = rule.kind;
      unawaited(_startRule(connection.id, rule));
    }
  }

  @override
  void onDisconnecting(Connection connection) => _teardown();

  @override
  void onReconnecting(Connection connection) => _teardown();

  Future<void> _startRule(String connectionId, PortForwardRule rule) async {
    try {
      switch (rule.kind) {
        case PortForwardKind.local:
          await rust_fwd.portForwardStartLocal(
            ruleId: rule.id,
            connectionId: connectionId,
            bindHost: rule.bindHost,
            bindPort: rule.bindPort,
            targetHost: rule.remoteHost,
            targetPort: rule.remotePort,
          );
          break;
        case PortForwardKind.dynamic_:
          await rust_fwd.portForwardStartDynamic(
            ruleId: rule.id,
            connectionId: connectionId,
            bindHost: rule.bindHost,
            bindPort: rule.bindPort,
          );
          break;
        case PortForwardKind.remote:
          await rust_fwd.portForwardStartRemote(
            ruleId: rule.id,
            connectionId: connectionId,
            bindHost: rule.bindHost,
            bindPort: rule.bindPort,
            targetHost: rule.remoteHost,
            targetPort: rule.remotePort,
          );
          break;
      }
    } catch (e) {
      // Drop the rule from the armed set so a later teardown does
      // not try to stop a listener that never bound. The Rust
      // driver already published an `Error` status event on the
      // bus before throwing, so the UI sees the failure regardless.
      _armed.remove(rule.id);
      AppLogger.instance.log(
        'Failed to start ${rule.kind.wireName} forward (Rust)',
        name: 'PortForward',
        error: e,
      );
    }
  }

  void _teardown() {
    if (_armed.isEmpty) return;
    final snapshot = Map<String, PortForwardKind>.from(_armed);
    _armed.clear();
    for (final entry in snapshot.entries) {
      unawaited(_stopRule(entry.key, entry.value));
    }
  }

  Future<void> _stopRule(String ruleId, PortForwardKind kind) async {
    try {
      switch (kind) {
        case PortForwardKind.local:
          await rust_fwd.portForwardStopLocal(ruleId: ruleId);
          break;
        case PortForwardKind.dynamic_:
          await rust_fwd.portForwardStopDynamic(ruleId: ruleId);
          break;
        case PortForwardKind.remote:
          await rust_fwd.portForwardStopRemote(ruleId: ruleId);
          break;
      }
    } catch (e) {
      AppLogger.instance.log(
        'Failed to stop ${kind.wireName} forward (Rust)',
        name: 'PortForward',
        error: e,
      );
    }
  }

  /// Symmetric with the legacy runtime so callers (provider
  /// onDispose, tests) keep the same teardown shape. Drops any
  /// in-flight armed rules without waiting on the stop calls.
  void dispose() => _teardown();
}
