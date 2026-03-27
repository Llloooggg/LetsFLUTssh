import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import 'split_node.dart';
import 'terminal_pane.dart';

/// Recursively renders a [SplitNode] tree as tiled terminal panes
/// with draggable resize dividers.
class TilingView extends StatefulWidget {
  final String tabId;
  final SplitNode root;
  final Map<String, Connection> paneConnections;
  final String? focusedPaneId;
  final ValueChanged<String> onPaneFocused;
  final void Function(String paneId, SplitDirection direction, bool insertBefore) onSplit;
  final ValueChanged<String> onClosePane;
  final ValueChanged<SplitNode> onTreeChanged;

  const TilingView({
    super.key,
    required this.tabId,
    required this.root,
    required this.paneConnections,
    required this.focusedPaneId,
    required this.onPaneFocused,
    required this.onSplit,
    required this.onClosePane,
    required this.onTreeChanged,
  });

  @override
  State<TilingView> createState() => _TilingViewState();
}

class _TilingViewState extends State<TilingView> {
  @override
  Widget build(BuildContext context) {
    final hasMultiplePanes = collectLeafIds(widget.root).length > 1;
    return _buildNode(widget.root, hasMultiplePanes);
  }

  Widget _buildNode(SplitNode node, bool hasMultiplePanes) {
    return switch (node) {
      LeafNode() => _buildLeaf(node, hasMultiplePanes),
      BranchNode() => _buildBranch(node, hasMultiplePanes),
    };
  }

  Widget _buildLeaf(LeafNode node, bool hasMultiplePanes) {
    final connection = widget.paneConnections[node.id];
    if (connection == null) return const SizedBox.shrink();

    return TerminalPane(
      key: ValueKey(node.id),
      connection: connection,
      isFocused: widget.focusedPaneId == node.id,
      hasMultiplePanes: hasMultiplePanes,
      onFocused: () => widget.onPaneFocused(node.id),
      onSplitVertical: () => widget.onSplit(node.id, SplitDirection.vertical, false),
      onSplitHorizontal: () => widget.onSplit(node.id, SplitDirection.horizontal, false),
      onClose: hasMultiplePanes ? () => widget.onClosePane(node.id) : null,
    );
  }

  Widget _buildBranch(BranchNode node, bool hasMultiplePanes) {
    final isVertical = node.direction == SplitDirection.vertical;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isVertical ? constraints.maxWidth : constraints.maxHeight;
        const dividerThickness = 4.0;
        final availableSize = totalSize - dividerThickness;
        final firstSize = availableSize * node.ratio;
        final secondSize = availableSize * (1 - node.ratio);

        final children = <Widget>[
          SizedBox(
            width: isVertical ? firstSize : null,
            height: isVertical ? null : firstSize,
            child: _buildNode(node.first, hasMultiplePanes),
          ),
          _buildDivider(node, isVertical, totalSize),
          SizedBox(
            width: isVertical ? secondSize : null,
            height: isVertical ? null : secondSize,
            child: _buildNode(node.second, hasMultiplePanes),
          ),
        ];

        if (isVertical) {
          return Row(children: children);
        } else {
          return Column(children: children);
        }
      },
    );
  }

  Widget _buildDivider(BranchNode node, bool isVertical, double totalSize) {
    const dividerThickness = 4.0;
    const minPaneSize = 80.0;

    return MouseRegion(
      cursor: isVertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final delta = isVertical ? details.delta.dx : details.delta.dy;
          final availableSize = totalSize - dividerThickness;
          final newRatio = (node.ratio + delta / availableSize).clamp(
            minPaneSize / availableSize,
            1.0 - minPaneSize / availableSize,
          );
          if (newRatio != node.ratio) {
            final updated = BranchNode(
              id: node.id,
              direction: node.direction,
              ratio: newRatio,
              first: node.first,
              second: node.second,
            );
            widget.onTreeChanged(replaceNode(widget.root, node.id, updated));
          }
        },
        child: Container(
          width: isVertical ? dividerThickness : double.infinity,
          height: isVertical ? double.infinity : dividerThickness,
          color: Theme.of(context).dividerColor,
        ),
      ),
    );
  }
}
