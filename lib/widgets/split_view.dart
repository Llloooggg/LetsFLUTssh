import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Resizable horizontal split pane with a draggable divider.
class SplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double initialLeftWidth;
  final double minLeftWidth;
  final double maxLeftWidth;

  const SplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialLeftWidth = 220,
    this.minLeftWidth = 150,
    this.maxLeftWidth = 400,
  });

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  late double _leftWidth;

  @override
  void initState() {
    super.initState();
    _leftWidth = widget.initialLeftWidth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Clamp left width to valid range
        final maxLeft = (constraints.maxWidth - 100).clamp(
          widget.minLeftWidth,
          widget.maxLeftWidth,
        );
        _leftWidth = _leftWidth.clamp(widget.minLeftWidth, maxLeft);

        return Row(
          children: [
            SizedBox(width: _leftWidth, child: widget.left),
            Semantics(
              label: S.of(context).resizePanelDivider,
              slider: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _leftWidth = (_leftWidth + details.delta.dx).clamp(
                        widget.minLeftWidth,
                        maxLeft,
                      );
                    });
                  },
                  child: Container(width: 4, color: theme.dividerColor),
                ),
              ),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
