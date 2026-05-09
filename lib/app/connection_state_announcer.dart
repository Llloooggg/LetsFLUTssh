import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection.dart';
import '../l10n/app_localizations.dart';
import '../providers/connection_provider.dart';

/// Fires `SemanticsService.announce` whenever a connection's state
/// transitions, so screen-reader users hear "Connecting to host",
/// "Connected to host", "Disconnected from host", or "Connection to
/// host failed" without having to navigate to the affected row.
///
/// Mounted as a zero-size sibling of the workspace so it has a
/// `BuildContext` for [`AppLocalizations`] (the assistive
/// announcement is a localized string). Tracks per-id last known
/// state in its own `State` so a list-level rebuild that doesn't
/// flip any state stays silent.
///
/// Renders `SizedBox.shrink()` — pure side-effect widget.
class ConnectionStateAnnouncer extends ConsumerStatefulWidget {
  const ConnectionStateAnnouncer({super.key});

  @override
  ConsumerState<ConnectionStateAnnouncer> createState() =>
      _ConnectionStateAnnouncerState();
}

class _ConnectionStateAnnouncerState
    extends ConsumerState<ConnectionStateAnnouncer> {
  /// Per-id snapshot of the last state we announced. New ids land
  /// here on first sight without an announcement (the
  /// `connecting → connected` transition fires it; the initial
  /// `disconnected` placeholder is silent).
  final Map<String, _Snapshot> _last = {};

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(connectionsProvider);
    final l10n = S.of(context);
    final dir = Directionality.of(context);
    final view = View.of(context);
    final seen = <String>{};
    for (final conn in list) {
      seen.add(conn.id);
      final prev = _last[conn.id];
      final next = _Snapshot.from(conn);
      if (prev == null) {
        // First time we see this connection. Bring it under
        // tracking but stay silent — the start state is already
        // visible to the user (they just opened the tab).
        _last[conn.id] = next;
        continue;
      }
      if (prev.state == next.state && prev.failed == next.failed) continue;
      _last[conn.id] = next;
      final host = _displayHost(conn);
      final message = _messageFor(l10n, prev, next, host);
      if (message != null) {
        SemanticsService.sendAnnouncement(view, message, dir);
      }
    }
    // Drop entries for connections that left the registry so the
    // map doesn't grow without bound.
    _last.removeWhere((id, _) => !seen.contains(id));
    return const SizedBox.shrink();
  }

  String _displayHost(Connection conn) {
    final label = conn.label.trim();
    if (label.isNotEmpty) return label;
    return conn.sshConfig.host;
  }

  String? _messageFor(S l10n, _Snapshot prev, _Snapshot next, String host) {
    // Failure is signalled by transitioning into `disconnected`
    // with `connectionError != null`. Distinguish from a clean
    // teardown so screen-reader users know whether to retry.
    if (next.state == SSHConnectionState.disconnected && next.failed) {
      return l10n.a11yConnectionFailed(host);
    }
    if (prev.state == next.state) return null;
    switch (next.state) {
      case SSHConnectionState.connecting:
        return l10n.a11yConnectingTo(host);
      case SSHConnectionState.connected:
        return l10n.a11yConnectedTo(host);
      case SSHConnectionState.disconnected:
        return l10n.a11yDisconnectedFrom(host);
    }
  }
}

class _Snapshot {
  final SSHConnectionState state;
  final bool failed;

  const _Snapshot(this.state, this.failed);

  factory _Snapshot.from(Connection conn) =>
      _Snapshot(conn.state, conn.connectionError != null);
}
