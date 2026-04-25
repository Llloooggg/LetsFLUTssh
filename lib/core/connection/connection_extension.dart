import 'connection.dart';

/// Lifecycle hook for features that ride along with an SSH connection.
///
/// Port forwards, ProxyJump bastion keepalives, session recording sinks,
/// agent forwarding, and similar add-ons all need the same three
/// moments: just after the underlying transport became live, just
/// before it tears down (orderly), and again on every reconnect cycle
/// once the new transport is up.
///
/// The interface keeps that contract in one place so [Connection] does
/// not grow a fan of feature-specific fields and so feature wiring does
/// not have to re-implement reconnect-survival logic. Each feature
/// registers an extension via [Connection.addExtension] at construction
/// time; [Connection] / [ConnectionManager] call the hooks at the
/// canonical moments.
///
/// **Hook order on a successful connect:**
/// 1. [onConnected] — fired once `state == connected` and the SSH
///    transport is wired up. Extensions open their channels here.
/// 2. ... user activity ...
/// 3. [onDisconnecting] — fired on explicit `ConnectionManager.disconnect`,
///    on `disconnectAll`, and just before `reconnect` tears down the
///    old transport. Extensions close their channels here. Idempotent —
///    safe to call when nothing was ever opened.
///
/// **On reconnect:**
/// 1. [onDisconnecting] — old transport is closing.
/// 2. [onReconnecting] — fired right before the new generation starts;
///    a chance to reset transient state without losing user-facing
///    config (a forward rule list survives the reconnect, the live
///    `SSHForwardChannel` references do not).
/// 3. [onConnected] — fired again once the new transport authenticates.
///
/// Hooks are async-friendly: implementations can return [Future] but
/// the framework does not await them — failures must not block the
/// connection lifecycle. Log and recover instead.
abstract class ConnectionExtension {
  /// Stable identifier for diagnostics. Used in log lines and to make
  /// duplicate-registration mistakes obvious.
  String get id;

  /// SSH transport just became live. The [connection] argument carries
  /// the active transport via [Connection.transport]. Returning a
  /// `Future` is permitted but not awaited.
  void onConnected(Connection connection);

  /// SSH transport is about to tear down (explicit disconnect or
  /// reconnect cycle). Close channels here. Must be idempotent — the
  /// framework also calls this on connections that never reached
  /// `onConnected` so cleanup paths stay symmetric.
  void onDisconnecting(Connection connection);

  /// Reconnect generation has started. Reset transient state that
  /// references the old transport (channel handles, in-flight futures)
  /// without dropping persistent configuration. Default implementation
  /// is a no-op so simple extensions only override what they need.
  void onReconnecting(Connection connection) {}
}
