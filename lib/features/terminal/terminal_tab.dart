import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/logger.dart';
import 'split_node.dart';
import 'tiling_view.dart';

/// Terminal tab widget: tiling layout of terminal panes.
///
/// Supports splitting via context menu (right-click → Split Right / Split Down).
/// Each pane can have its own Connection (different servers in one tab).
/// Factory for reconnecting SSH — injectable for testing.
typedef ReconnectFactory = Future<void> Function(Connection connection);

class TerminalTab extends ConsumerStatefulWidget {
  final String tabId;
  final Connection connection;
  final VoidCallback? onDisconnected;

  /// Optional factory for testing — bypasses real SSH reconnect.
  final ReconnectFactory? reconnectFactory;

  const TerminalTab({
    super.key,
    required this.tabId,
    required this.connection,
    this.onDisconnected,
    this.reconnectFactory,
  });

  @override
  TerminalTabState createState() => TerminalTabState();
}

class TerminalTabState extends ConsumerState<TerminalTab> {
  late SplitNode _root;
  late String _focusedPaneId;
  final Map<String, Connection> _paneConnections = {};

  @override
  void initState() {
    super.initState();
    final leaf = LeafNode();
    _root = leaf;
    _focusedPaneId = leaf.id;
    _paneConnections[leaf.id] = widget.connection;
    // Always ready — TerminalPane handles waiting for connection internally
  }

  void _closePane(String paneId) {
    final newRoot = removeNode(_root, paneId);
    if (newRoot == null) return;
    _paneConnections.remove(paneId);
    setState(() {
      _root = newRoot;
      final leafIds = collectLeafIds(_root);
      if (!leafIds.contains(_focusedPaneId)) {
        _focusedPaneId = leafIds.first;
      }
    });
  }

  void _onTreeChanged(SplitNode newRoot) {
    setState(() => _root = newRoot);
  }

  /// Re-read the session from the store and update the connection's SSHConfig.
  /// Returns the (possibly updated) config to use for reconnection.
  SSHConfig _refreshConfig() {
    final sessionId = widget.connection.sessionId;
    if (sessionId == null) return widget.connection.sshConfig;

    final sessions = ref.read(sessionProvider);
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) {
      AppLogger.instance.log(
        'Session $sessionId not found in store, using cached config',
        name: 'TerminalTab',
      );
      return widget.connection.sshConfig;
    }

    final freshConfig = sessions[idx].toSSHConfig();
    widget.connection.sshConfig = freshConfig;
    return freshConfig;
  }

  /// Reconnect SSH and reset to a single terminal pane.
  ///
  /// Delegates the actual SSH reconnect to [ConnectionManager.reconnect()].
  /// Immediately resets the pane tree so the new TerminalPane subscribes
  /// to the fresh progressStream and shows the connection log.
  void reconnect() {
    // Re-read session from store to pick up any config changes (e.g. added key).
    final freshConfig = _refreshConfig();

    if (widget.reconnectFactory != null) {
      widget.connection.resetForReconnect();
      widget.connection.state = SSHConnectionState.connecting;
      _runReconnectFactory(widget.connection);
    } else {
      // Delegate to ConnectionManager — handles reset, progress, notify
      final manager = ref.read(connectionManagerProvider);
      manager.reconnect(widget.connection.id, updatedConfig: freshConfig);
    }

    // Reset to single pane — new TerminalPane will show progress
    final leaf = LeafNode();
    _paneConnections.clear();
    _paneConnections[leaf.id] = widget.connection;
    setState(() {
      _root = leaf;
      _focusedPaneId = leaf.id;
    });
  }

  /// Run the test-injected reconnect factory with the same lifecycle
  /// guarantees as [ConnectionManager._doConnect]: set state, error,
  /// and complete ready on success or failure.
  Future<void> _runReconnectFactory(Connection conn) async {
    try {
      await widget.reconnectFactory!(conn);
      conn.state = SSHConnectionState.connected;
    } catch (e) {
      conn.state = SSHConnectionState.disconnected;
      conn.connectionError = e;
    } finally {
      conn.completeReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TilingView(
      tabId: widget.tabId,
      root: _root,
      paneConnections: _paneConnections,
      focusedPaneId: _focusedPaneId,
      onPaneFocused: (id) => setState(() => _focusedPaneId = id),
      onClosePane: _closePane,
      onTreeChanged: _onTreeChanged,
    );
  }
}
