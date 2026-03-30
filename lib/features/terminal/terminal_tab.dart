import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/ssh_client.dart';
import '../../utils/logger.dart';
import '../../widgets/error_state.dart';
import 'split_node.dart';
import 'tiling_view.dart';

/// Terminal tab widget: tiling layout of terminal panes.
///
/// Supports splitting via context menu (right-click → Split Right / Split Down).
/// Each pane can have its own Connection (different servers in one tab).
/// Factory for reconnecting SSH — injectable for testing.
typedef ReconnectFactory = Future<void> Function(Connection connection);

class TerminalTab extends StatefulWidget {
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

class TerminalTabState extends State<TerminalTab> {
  late SplitNode _root;
  late String _focusedPaneId;
  final Map<String, Connection> _paneConnections = {};
  bool _connectionReady = true;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    final leaf = LeafNode();
    _root = leaf;
    _focusedPaneId = leaf.id;
    _paneConnections[leaf.id] = widget.connection;
    // Always ready — TerminalPane handles waiting for connection internally
  }

  /// Split a pane via context menu (new pane gets same connection as source).
  void _splitPane(String paneId, SplitDirection direction, bool insertBefore) {
    final newLeaf = LeafNode();
    final originalLeaf = LeafNode(id: paneId);
    final branch = BranchNode(
      direction: direction,
      first: insertBefore ? newLeaf : originalLeaf,
      second: insertBefore ? originalLeaf : newLeaf,
    );
    _paneConnections[newLeaf.id] = _paneConnections[paneId]!;
    setState(() {
      _root = replaceNode(_root, paneId, branch);
      _focusedPaneId = newLeaf.id;
    });
  }

  /// The direction of the root-level split, or null if not split.
  SplitDirection? get topLevelSplitDirection {
    final root = _root;
    if (root is BranchNode) return root.direction;
    return null;
  }

  /// Toggle a split in the given direction at the toolbar level.
  ///
  /// If the root is already a [BranchNode] in that direction, collapses back
  /// to a single pane (keeps the first leaf). Otherwise splits the focused pane.
  void splitFocused(SplitDirection direction) {
    final root = _root;
    if (root is BranchNode && root.direction == direction) {
      final keepId = _firstLeafIdOf(root.first);
      _paneConnections.removeWhere((key, _) => key != keepId);
      setState(() {
        _root = LeafNode(id: keepId);
        _focusedPaneId = keepId;
      });
    } else {
      _splitPane(_focusedPaneId, direction, false);
    }
  }

  String _firstLeafIdOf(SplitNode node) {
    if (node is LeafNode) return node.id;
    return _firstLeafIdOf((node as BranchNode).first);
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

  @visibleForTesting
  Future<void> reconnect() async {
    setState(() {
      _connectionError = null;
      _connectionReady = false;
    });

    try {
      if (widget.reconnectFactory != null) {
        await widget.reconnectFactory!(widget.connection);
      } else {
        final sshConn = widget.connection.sshConnection;
        if (sshConn == null || !sshConn.isConnected) {
          final newConn = SSHConnection(
            config: widget.connection.sshConfig,
            knownHosts: widget.connection.knownHosts,
          );
          await newConn.connect();
          widget.connection.sshConnection = newConn;
          widget.connection.state = SSHConnectionState.connected;
        }
      }
    } catch (e) {
      AppLogger.instance.log('Reconnect failed: $e', name: 'TerminalTab', error: e);
      setState(() => _connectionError = 'Reconnect failed: $e');
      return;
    }

    // Reset to single pane with original connection
    final leaf = LeafNode();
    _paneConnections.clear();
    _paneConnections[leaf.id] = widget.connection;
    setState(() {
      _root = leaf;
      _focusedPaneId = leaf.id;
      _connectionReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_connectionError != null) {
      return _buildErrorState();
    }
    if (!_connectionReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return TilingView(
      tabId: widget.tabId,
      root: _root,
      paneConnections: _paneConnections,
      focusedPaneId: _focusedPaneId,
      onPaneFocused: (id) => setState(() => _focusedPaneId = id),
      onSplit: _splitPane,
      onClosePane: _closePane,
      onTreeChanged: _onTreeChanged,
    );
  }

  Widget _buildErrorState() {
    return ErrorState(
      message: _connectionError!,
      onRetry: reconnect,
      retryLabel: 'Reconnect',
      onSecondary: widget.onDisconnected ?? () {},
      secondaryLabel: 'Close',
    );
  }
}
