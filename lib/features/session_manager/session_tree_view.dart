import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../file_browser/file_row.dart';

/// Drag data: either a session or a group path.
sealed class SessionDragData {}

class SessionDrag extends SessionDragData {
  final Session session;
  SessionDrag(this.session);
}

class GroupDrag extends SessionDragData {
  final String groupPath;
  GroupDrag(this.groupPath);
}

/// Hierarchical tree view of sessions with nested group folders.
/// Supports drag&drop: sessions into folders, folders into folders.
class SessionTreeView extends StatefulWidget {
  final List<SessionTreeNode> tree;
  final void Function(Session session)? onSessionTap;
  final void Function(Session session)? onSessionDoubleTap;
  final void Function(Session session, Offset position)? onSessionContextMenu;
  final void Function(String groupPath, Offset position)? onGroupContextMenu;
  /// Context menu on empty space (no group path).
  final void Function(Offset position)? onBackgroundContextMenu;
  /// Called when a session is dropped onto a group (or root).
  final void Function(String sessionId, String targetGroup)? onSessionMoved;
  /// Called when a group is dropped onto another group (or root).
  final void Function(String groupPath, String targetParent)? onGroupMoved;

  /// Multi-select mode: show checkboxes, tap toggles selection.
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String sessionId)? onToggleSelected;

  /// Called when marquee selection starts on desktop — parent should
  /// enter select mode and provide [selectedIds] + [onToggleSelected].
  final void Function(Set<String> ids)? onMarqueeSelect;

  /// Called when a marquee drag begins (threshold crossed).
  final VoidCallback? onMarqueeStart;

  /// Called when a marquee drag ends (pointer up or leaves bounds).
  final VoidCallback? onMarqueeEnd;

  /// Cross-widget marquee controller — when the pointer exits session panel
  /// bounds during a marquee drag, events are forwarded to the file pane.
  final CrossMarqueeController? crossMarquee;

  const SessionTreeView({
    super.key,
    required this.tree,
    this.onSessionTap,
    this.onSessionDoubleTap,
    this.onSessionContextMenu,
    this.onGroupContextMenu,
    this.onBackgroundContextMenu,
    this.onSessionMoved,
    this.onGroupMoved,
    this.selectMode = false,
    this.selectedIds = const {},
    this.onToggleSelected,
    this.onMarqueeSelect,
    this.onMarqueeStart,
    this.onMarqueeEnd,
    this.crossMarquee,
  });

  @override
  State<SessionTreeView> createState() => _SessionTreeViewState();
}

class _SessionTreeViewState extends State<SessionTreeView> {
  final _expandedGroups = <String>{};
  String? _selectedSessionId;
  String? _dropTargetGroup; // highlight on drag hover

  // ── Marquee state (desktop only) ──
  Offset? _marqueeAnchor;
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeActive = false;
  bool _crossMarqueeActive = false;
  final _scrollController = ScrollController();
  DateTime _lastMarqueeUpdate = DateTime(0);

  static const _marqueeThreshold = 5.0;

  bool get _isCtrlHeld =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlRight);

  static final bool _mobile = isMobilePlatform;
  double get _rowHeight => _mobile ? 48.0 : 28.0;
  double get _fontSize => _mobile ? 15.0 : 11.0;
  double get _subFontSize => _mobile ? 12.0 : 9.0;
  double get _iconSize => _mobile ? 20.0 : 12.0;
  double get _authIconSize => _mobile ? 18.0 : 12.0;

  @override
  void initState() {
    super.initState();
    _expandAllGroups(widget.tree);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _expandAllGroups(List<SessionTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isGroup) {
        _expandedGroups.add(node.fullPath);
        _expandAllGroups(node.children);
      }
    }
  }

  /// Flattened visible nodes for ListView.builder.
  List<(SessionTreeNode, int)> _flattenVisible(List<SessionTreeNode> nodes, int depth) {
    final result = <(SessionTreeNode, int)>[];
    for (final node in nodes) {
      result.add((node, depth));
      if (node.isGroup && _expandedGroups.contains(node.fullPath)) {
        result.addAll(_flattenVisible(node.children, depth + 1));
      }
    }
    return result;
  }

  bool _canAcceptDrop(SessionDragData data, String targetGroup) {
    if (data is SessionDrag) {
      // Don't drop on own group
      return data.session.group != targetGroup;
    } else if (data is GroupDrag) {
      // Can't drop on self or into own subtree
      if (data.groupPath == targetGroup) return false;
      if (targetGroup.startsWith('${data.groupPath}/')) return false;
      // Can't drop on own current parent
      final parts = data.groupPath.split('/');
      final currentParent = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      return currentParent != targetGroup;
    }
    return false;
  }

  void _handleDrop(SessionDragData data, String targetGroup) {
    if (data is SessionDrag) {
      widget.onSessionMoved?.call(data.session.id, targetGroup);
    } else if (data is GroupDrag) {
      widget.onGroupMoved?.call(data.groupPath, targetGroup);
    }
  }

  // ── Marquee pointer handlers (desktop only) ──

  /// Cached flat nodes for marquee hit testing.
  List<(SessionTreeNode, int)>? _cachedFlatNodes;

  void _onPointerDown(PointerDownEvent e) {
    if (_mobile || e.buttons != kPrimaryButton) return;
    setState(() {
      _marqueeAnchor = e.localPosition;
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mobile || _marqueeAnchor == null) return;

    final distance = (e.localPosition - _marqueeAnchor!).distance;
    if (!_marqueeActive && !_crossMarqueeActive) {
      if (distance < _marqueeThreshold) return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box != null && widget.crossMarquee != null) {
      if (_handleCrossMarquee(e, box)) return;
    }

    if (!_marqueeActive) {
      _marqueeActive = true;
      widget.onMarqueeStart?.call();
    }

    setState(() {
      _marqueeStart = _marqueeAnchor;
      _marqueeCurrent = e.localPosition;
    });
    _updateMarqueeSelection();
  }

  // Returns true if the event was consumed by cross-marquee logic.
  bool _handleCrossMarquee(PointerMoveEvent e, RenderBox box) {
    final local = e.localPosition;
    final size = box.size;
    final outsideBounds =
        local.dx > size.width || local.dx < 0 || local.dy < 0 || local.dy > size.height;

    if (outsideBounds) {
      if (_marqueeActive) {
        setState(() {
          _marqueeStart = null;
          _marqueeCurrent = null;
          _marqueeActive = false;
        });
        widget.onMarqueeEnd?.call();
        widget.onMarqueeSelect?.call({});
      }
      if (!_crossMarqueeActive) {
        _crossMarqueeActive = true;
        widget.crossMarquee!.start(e.position);
      } else {
        widget.crossMarquee!.move(e.position);
      }
      return true;
    }

    // Pointer came back inside — cancel cross-marquee
    if (_crossMarqueeActive) {
      _crossMarqueeActive = false;
      widget.crossMarquee!.end();
      _marqueeAnchor = e.localPosition;
    }
    return false;
  }

  void _onPointerUp(PointerUpEvent _) {
    if (_crossMarqueeActive) {
      _crossMarqueeActive = false;
      widget.crossMarquee?.end();
      _marqueeAnchor = null;
      return;
    }
    if (_marqueeActive) {
      setState(() {
        _marqueeAnchor = null;
        _marqueeStart = null;
        _marqueeCurrent = null;
        _marqueeActive = false;
      });
      widget.onMarqueeEnd?.call();
    } else {
      _marqueeAnchor = null;
      // Click without drag — clear marquee selection
      if (widget.selectedIds.isNotEmpty && !widget.selectMode) {
        widget.onMarqueeSelect?.call({});
      }
    }
  }

  void _updateMarqueeSelection() {
    if (_marqueeStart == null || _marqueeCurrent == null) return;
    final flatNodes = _cachedFlatNodes;
    if (flatNodes == null) return;

    final now = DateTime.now();
    if (now.difference(_lastMarqueeUpdate).inMilliseconds < 50) return;
    _lastMarqueeUpdate = now;

    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    const listPaddingTop = 4.0; // matches ListView padding

    final startY = _marqueeStart!.dy + scrollOffset;
    final endY = _marqueeCurrent!.dy + scrollOffset;
    final minY = (startY < endY ? startY : endY) - listPaddingTop;
    final maxY = (startY > endY ? startY : endY) - listPaddingTop;

    final firstIndex =
        (minY / _rowHeight).floor().clamp(0, flatNodes.length - 1);
    final lastIndex =
        (maxY / _rowHeight).floor().clamp(0, flatNodes.length - 1);

    final ids = <String>{};
    for (var i = firstIndex; i <= lastIndex; i++) {
      final session = flatNodes[i].$1.session;
      if (session != null) {
        ids.add(session.id);
      }
    }

    if (_isCtrlHeld) {
      ids.addAll(widget.selectedIds);
    }
    widget.onMarqueeSelect?.call(ids);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tree.isEmpty) {
      return Center(
        child: Text(
          'No sessions',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    final flatNodes = _flattenVisible(widget.tree, 0);
    _cachedFlatNodes = flatNodes;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: GestureDetector(
            onSecondaryTapUp: (d) {
              widget.onBackgroundContextMenu?.call(d.globalPosition);
            },
            onLongPressStart: _mobile
                ? (d) => widget.onBackgroundContextMenu?.call(d.globalPosition)
                : null,
            behavior: HitTestBehavior.translucent,
            child: _buildDragTarget(flatNodes),
          ),
        );
      },
    );
  }

  Widget _buildDragTarget(List<(SessionTreeNode, int)> flatNodes) {
    return DragTarget<SessionDragData>(
      onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data, ''),
      onAcceptWithDetails: (details) {
        setState(() => _dropTargetGroup = null);
        _handleDrop(details.data, '');
      },
      onMove: (_) {
        if (_dropTargetGroup != '') {
          setState(() => _dropTargetGroup = '');
        }
      },
      onLeave: (_) {
        if (_dropTargetGroup == '') {
          setState(() => _dropTargetGroup = null);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: flatNodes.length,
              itemExtent: _rowHeight,
              itemBuilder: (context, index) {
                final (node, depth) = flatNodes[index];
                if (node.isGroup) {
                  return _buildGroupTile(node, depth);
                } else {
                  return _buildSessionTile(node, depth);
                }
              },
            ),
            if (_marqueeActive && _marqueeStart != null && _marqueeCurrent != null)
              Positioned.fill(
                child: RepaintBoundary(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MarqueePainter(
                        start: _marqueeStart!,
                        end: _marqueeCurrent!,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildIndentGuides(int depth, ThemeData theme) {
    if (depth == 0) return const SizedBox(width: 8);
    final guideColor = theme.colorScheme.onSurface.withValues(alpha: 0.12);
    return SizedBox(
      width: 8.0 + depth * 16.0,
      child: Row(
        children: [
          const SizedBox(width: 8),
          for (var i = 0; i < depth; i++)
            SizedBox(
              width: 16,
              child: Center(
                child: Container(width: 1, color: guideColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupContent(SessionTreeNode node, int depth, bool isDropTarget) {
    final expanded = _expandedGroups.contains(node.fullPath);
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapUp: (d) {
        widget.onGroupContextMenu?.call(node.fullPath, d.globalPosition);
      },
      onLongPressStart: _mobile
          ? (d) => widget.onGroupContextMenu?.call(node.fullPath, d.globalPosition)
          : null,
      child: _HoverBuilder(
        builder: (hovered) => InkWell(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedGroups.remove(node.fullPath);
              } else {
                _expandedGroups.add(node.fullPath);
              }
            });
          },
          hoverColor: Colors.transparent,
          child: Container(
            height: _rowHeight,
            padding: EdgeInsets.only(
              left: _mobile ? 8.0 : 12.0,
              right: 8,
            ),
            decoration: BoxDecoration(
              color: isDropTarget
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : hovered
                      ? AppTheme.hover
                      : null,
              border: isDropTarget
                  ? Border.all(color: theme.colorScheme.primary, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                if (!_mobile && depth > 0) SizedBox(width: depth * 12.0),
                Transform.rotate(
                  angle: expanded ? 0 : -1.5708, // -90° in radians
                  child: Icon(
                    Icons.expand_more,
                    size: _iconSize,
                    color: AppTheme.fgDim,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.folder, size: _iconSize, color: AppTheme.yellow),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: _fontSize,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${node.sessionCount}',
                  style: TextStyle(
                    fontSize: _subFontSize,
                    color: AppTheme.fgFaint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupTile(SessionTreeNode node, int depth) {
    // On mobile: no drag&drop, long-press opens context menu (handled in _buildGroupContent)
    if (_mobile) {
      return _buildGroupContent(node, depth, false);
    }

    final theme = Theme.of(context);

    // Desktop: Draggable + DragTarget
    return Draggable<SessionDragData>(
      data: GroupDrag(node.fullPath),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder, size: 14,
                  color: AppTheme.folderColor(theme.brightness)),
              const SizedBox(width: 4),
              Text(node.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildGroupContent(node, depth, false),
      ),
      child: DragTarget<SessionDragData>(
        onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data, node.fullPath),
        onAcceptWithDetails: (details) {
          setState(() => _dropTargetGroup = null);
          _handleDrop(details.data, node.fullPath);
        },
        onMove: (_) {
          if (_dropTargetGroup != node.fullPath) {
            setState(() => _dropTargetGroup = node.fullPath);
          }
        },
        onLeave: (_) {
          if (_dropTargetGroup == node.fullPath) {
            setState(() => _dropTargetGroup = null);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return _buildGroupContent(node, depth, _dropTargetGroup == node.fullPath);
        },
      ),
    );
  }

  void _onSessionTap(Session session) {
    if (widget.selectMode) {
      widget.onToggleSelected?.call(session.id);
      return;
    }
    setState(() => _selectedSessionId = session.id);
    if (_mobile) {
      widget.onSessionDoubleTap?.call(session);
    } else {
      widget.onSessionTap?.call(session);
    }
  }

  List<Widget> _buildSessionRowChildren(
    SessionTreeNode node,
    Session session,
    int depth,
    bool isChecked,
    ThemeData theme,
  ) {
    // Connected state comes from active connections, but session tree
    // doesn't have that info — use incomplete as a proxy for now.
    // The mockup uses Shield icon instead of auth-type icons.
    final isConnected = !session.incomplete;

    return [
      if (widget.selectMode)
        SizedBox(
          width: 36,
          child: Checkbox(
            value: isChecked,
            onChanged: (_) => widget.onToggleSelected?.call(session.id),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        )
      else if (_mobile)
        _buildIndentGuides(depth, theme)
      else
        SizedBox(width: 28.0 + (depth > 0 ? depth * 12.0 : 0)),
      if (!widget.selectMode) ...[
        Icon(
          Icons.terminal,
          size: _authIconSize,
          color: isConnected ? AppTheme.green : AppTheme.fgFaint,
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Text(
          node.name,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: _fontSize,
            color: isConnected ? AppTheme.fg : AppTheme.fgDim,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (session.incomplete)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: 'Credentials not set',
            child: Icon(
              Icons.warning_amber,
              size: _authIconSize,
              color: AppTheme.connectingColor(theme.brightness),
            ),
          ),
        ),
      Text(
        session.host,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 9,
          color: AppTheme.fgFaint,
        ),
      ),
    ];
  }

  Widget _buildSessionTile(SessionTreeNode node, int depth) {
    final session = node.session!;
    final isSelected = session.id == _selectedSessionId;
    final isChecked = widget.selectedIds.contains(session.id);
    final theme = Theme.of(context);
    final canInteract = !_mobile && !widget.selectMode;

    final Widget content = GestureDetector(
      onDoubleTap: canInteract ? () => widget.onSessionDoubleTap?.call(session) : null,
      onSecondaryTapUp: canInteract
          ? (details) => widget.onSessionContextMenu?.call(session, details.globalPosition)
          : null,
      onLongPressStart: (_mobile && !widget.selectMode)
          ? (d) => widget.onSessionContextMenu?.call(session, d.globalPosition)
          : null,
      child: _HoverBuilder(
        builder: (hovered) => InkWell(
          onTap: () => _onSessionTap(session),
          hoverColor: Colors.transparent,
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.only(right: 8),
            color: (isSelected || isChecked) && !widget.selectMode
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : hovered
                    ? AppTheme.hover
                    : null,
            child: Row(
              children: _buildSessionRowChildren(node, session, depth, isChecked, theme),
            ),
          ),
        ),
      ),
    );

    // Select mode or mobile: no drag&drop
    if (_mobile || widget.selectMode) return content;

    // Desktop: Draggable (immediate drag start, no long-press needed)
    return Draggable<SessionDragData>(
      data: SessionDrag(session),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal, size: 12, color: AppTheme.fgFaint),
              const SizedBox(width: 4),
              Text(node.name, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: content,
    );
  }

}

/// Lightweight hover detector that rebuilds child with hover state.
class _HoverBuilder extends StatefulWidget {
  final Widget Function(bool hovered) builder;

  const _HoverBuilder({required this.builder});

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}
