import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/ssh_client.dart';
import 'split_node.dart';
import 'tiling_view.dart';

/// Terminal tab widget: tiling layout of terminal panes.
///
/// Supports splitting via context menu (right-click → Split Right / Split Down).
/// Each pane can have its own Connection (different servers in one tab).
class TerminalTab extends StatefulWidget {
  final String tabId;
  final Connection connection;
  final VoidCallback? onDisconnected;

  const TerminalTab({
    super.key,
    required this.tabId,
    required this.connection,
    this.onDisconnected,
  });

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
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

    final sshConn = widget.connection.sshConnection;
    if (sshConn == null || !sshConn.isConnected) {
      _connectionReady = false;
      _connectionError = 'Not connected';
    }
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

  Future<void> _reconnect() async {
    setState(() {
      _connectionError = null;
      _connectionReady = false;
    });

    final sshConn = widget.connection.sshConnection;
    if (sshConn == null || !sshConn.isConnected) {
      try {
        final newConn = SSHConnection(
          config: widget.connection.sshConfig,
          knownHosts: widget.connection.sshConnection!.knownHosts,
        );
        await newConn.connect();
        widget.connection.sshConnection = newConn;
        widget.connection.state = SSHConnectionState.connected;
      } catch (e) {
        setState(() => _connectionError = 'Reconnect failed: $e');
        return;
      }
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            _connectionError!,
            style: TextStyle(color: Colors.red[300]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _reconnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: widget.onDisconnected,
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
