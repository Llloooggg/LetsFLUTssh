import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import '../../theme/app_theme.dart';
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
        return _buildSplitLayout(node, isVertical, totalSize, hasMultiplePanes);
      },
    );
  }

  Widget _buildSplitLayout(
    BranchNode node,
    bool isVertical,
    double totalSize,
    bool hasMultiplePanes,
  ) {
    final firstSize = totalSize * node.ratio;
    final secondSize = totalSize * (1 - node.ratio);

    final firstChild = SizedBox(
      width: isVertical ? firstSize : null,
      height: isVertical ? null : firstSize,
      child: _buildNode(node.first, hasMultiplePanes),
    );
    final secondChild = SizedBox(
      width: isVertical ? secondSize : null,
      height: isVertical ? null : secondSize,
      child: _buildNode(node.second, hasMultiplePanes),
    );

    final layout = isVertical
        ? Row(children: [firstChild, secondChild])
        : Column(children: [firstChild, secondChild]);

    return Stack(
      children: [
        layout,
        Positioned(
          left: isVertical ? firstSize - 3 : 0,
          top: isVertical ? 0 : firstSize - 3,
          right: isVertical ? null : 0,
          bottom: isVertical ? 0 : null,
          child: _buildDivider(node, isVertical, totalSize),
        ),
      ],
    );
  }

  Widget _buildDivider(BranchNode node, bool isVertical, double totalSize) {
    const hitSize = 6.0;
    const minPaneSize = 80.0;

    return MouseRegion(
      cursor: isVertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final delta = isVertical ? details.delta.dx : details.delta.dy;
          final newRatio = (node.ratio + delta / totalSize).clamp(
            minPaneSize / totalSize,
            1.0 - minPaneSize / totalSize,
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
        child: SizedBox(
          width: isVertical ? hitSize : double.infinity,
          height: isVertical ? double.infinity : hitSize,
          child: Center(
            child: Container(
              width: isVertical ? 1 : double.infinity,
              height: isVertical ? double.infinity : 1,
              color: AppTheme.border,
            ),
          ),
        ),
      ),
    );
  }
}
