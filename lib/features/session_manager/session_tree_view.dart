import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hover_region.dart';
import '../../utils/platform.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../widgets/marquee_mixin.dart';

/// Drag data: either a session, a folder path, or a bulk selection.
sealed class SessionDragData {}

class SessionDrag extends SessionDragData {
  final Session session;
  SessionDrag(this.session);
}

class FolderDrag extends SessionDragData {
  final String folderPath;
  FolderDrag(this.folderPath);
}

class BulkDrag extends SessionDragData {
  final Set<String> sessionIds;
  final Set<String> folderPaths;
  BulkDrag({required this.sessionIds, required this.folderPaths});
  int get totalCount => sessionIds.length + folderPaths.length;
}

/// Hierarchical tree view of sessions with nested folders.
/// Supports drag&drop: sessions into folders, folders into folders.
class SessionTreeView extends StatefulWidget {
  final List<SessionTreeNode> tree;
  final void Function(Session session)? onSessionTap;
  final void Function(Session session)? onSessionDoubleTap;
  final void Function(Session session, Offset position)? onSessionContextMenu;
  final void Function(String folderPath, Offset position)? onFolderContextMenu;

  /// Context menu on empty space (no folder path).
  final void Function(Offset position)? onBackgroundContextMenu;

  /// Called when a session is dropped onto a folder (or root).
  final void Function(String sessionId, String targetFolder)? onSessionMoved;

  /// Called when a folder is dropped onto another folder (or root).
  final void Function(String folderPath, String targetParent)? onFolderMoved;

  /// Called when a bulk selection is dropped onto a folder (or root).
  final void Function(
    Set<String> sessionIds,
    Set<String> folderPaths,
    String targetFolder,
  )?
  onBulkMoved;

  /// Multi-select mode: show checkboxes, tap toggles selection.
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String sessionId)? onToggleSelected;

  /// Selected folder paths (for bulk operations).
  final Set<String> selectedFolderPaths;
  final void Function(String folderPath)? onToggleFolderSelected;

  /// Called when marquee selection starts on desktop — parent should
  /// enter select mode and provide [selectedIds] + [onToggleSelected].
  final void Function(Set<String> ids, Set<String> folderPaths)?
  onMarqueeSelect;

  /// Called when a marquee drag begins (threshold crossed).
  final VoidCallback? onMarqueeStart;

  /// Called when a marquee drag ends (pointer up or leaves bounds).
  final VoidCallback? onMarqueeEnd;

  /// Cross-widget marquee controller — when the pointer exits session panel
  /// bounds during a marquee drag, events are forwarded to the file pane.
  final CrossMarqueeController? crossMarquee;

  /// IDs of sessions that currently have an active (connected) connection.
  final Set<String> connectedSessionIds;

  /// IDs of sessions that are currently connecting (SSH handshake in progress).
  final Set<String> connectingSessionIds;

  /// Called when a session is selected (single-click on desktop).
  /// Used by parent to track the focused session for keyboard shortcuts.
  final void Function(String sessionId)? onSessionSelected;

  const SessionTreeView({
    super.key,
    required this.tree,
    this.onSessionTap,
    this.onSessionDoubleTap,
    this.onSessionContextMenu,
    this.onFolderContextMenu,
    this.onBackgroundContextMenu,
    this.onSessionMoved,
    this.onFolderMoved,
    this.onBulkMoved,
    this.selectMode = false,
    this.selectedIds = const {},
    this.onToggleSelected,
    this.selectedFolderPaths = const {},
    this.onToggleFolderSelected,
    this.onMarqueeSelect,
    this.onMarqueeStart,
    this.onMarqueeEnd,
    this.crossMarquee,
    this.connectedSessionIds = const {},
    this.connectingSessionIds = const {},
    this.onSessionSelected,
  });

  @override
  State<SessionTreeView> createState() => _SessionTreeViewState();
}

class _SessionTreeViewState extends State<SessionTreeView> with MarqueeMixin {
  final _expandedFolders = <String>{};
  String? _selectedSessionId;
  String? _dropTargetFolder; // highlight on drag hover

  // ── Cross-marquee state (session panel only) ──
  bool _crossMarqueeActive = false;

  bool get _hasBulkSelection =>
      widget.selectedIds.length + widget.selectedFolderPaths.length > 1;

  bool get _mobile => isMobilePlatform;
  double get _rowHeight => _mobile ? 48.0 : 28.0;
  double get _fontSize => AppFonts.sm;
  double get _subFontSize => AppFonts.tiny;
  double get _iconSize => _mobile ? 20.0 : 12.0;
  double get _authIconSize => _mobile ? 18.0 : 12.0;

  @override
  void initState() {
    super.initState();
    _expandAllFolders(widget.tree);
  }

  @override
  void dispose() {
    disposeMarquee();
    super.dispose();
  }

  // ── MarqueeMixin implementation ──

  List<(SessionTreeNode, int)>? _cachedFlatNodes;

  @override
  double get marqueeRowHeight => _rowHeight;

  @override
  double get marqueeListPadding => 4.0; // matches ListView padding

  @override
  int get marqueeItemCount => _cachedFlatNodes?.length ?? 0;

  @override
  bool isMarqueeItemSelected(int index) {
    final flatNodes = _cachedFlatNodes;
    if (flatNodes == null || index < 0 || index >= flatNodes.length) {
      return false;
    }
    final node = flatNodes[index].$1;
    if (node.session != null) {
      return widget.selectedIds.contains(node.session!.id);
    }
    if (node.isGroup) {
      return widget.selectedFolderPaths.contains(node.fullPath);
    }
    return false;
  }

  @override
  void applyMarqueeSelection(
    int firstIndex,
    int lastIndex, {
    required bool ctrlHeld,
  }) {
    final flatNodes = _cachedFlatNodes;
    if (flatNodes == null) return;

    final ids = <String>{};
    final folderPaths = <String>{};
    for (var i = firstIndex; i <= lastIndex; i++) {
      final node = flatNodes[i].$1;
      if (node.session != null) {
        ids.add(node.session!.id);
      } else if (node.isGroup) {
        folderPaths.add(node.fullPath);
      }
    }
    if (ctrlHeld) {
      ids.addAll(widget.selectedIds);
      folderPaths.addAll(widget.selectedFolderPaths);
    }
    widget.onMarqueeSelect?.call(ids, folderPaths);
  }

  @override
  void onMarqueeActivated() {
    widget.onMarqueeStart?.call();
  }

  @override
  void onMarqueeDeactivated() {
    widget.onMarqueeEnd?.call();
  }

  @override
  void onMarqueeClickEmpty(int rowIndex) {
    if ((widget.selectedIds.isNotEmpty ||
            widget.selectedFolderPaths.isNotEmpty) &&
        !widget.selectMode) {
      widget.onMarqueeSelect?.call({}, {});
    }
  }

  // ── Tree helpers ──

  void _expandAllFolders(List<SessionTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isGroup) {
        _expandedFolders.add(node.fullPath);
        _expandAllFolders(node.children);
      }
    }
  }

  List<(SessionTreeNode, int)> _flattenVisible(
    List<SessionTreeNode> nodes,
    int depth,
  ) {
    final result = <(SessionTreeNode, int)>[];
    for (final node in nodes) {
      result.add((node, depth));
      if (node.isGroup && _expandedFolders.contains(node.fullPath)) {
        result.addAll(_flattenVisible(node.children, depth + 1));
      }
    }
    return result;
  }

  // ── Drag & drop ──

  bool _canAcceptDrop(SessionDragData data, String targetFolder) {
    if (data is SessionDrag) {
      return data.session.folder != targetFolder;
    } else if (data is FolderDrag) {
      if (data.folderPath == targetFolder) return false;
      if (targetFolder.startsWith('${data.folderPath}/')) return false;
      final parts = data.folderPath.split('/');
      final currentParent = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      return currentParent != targetFolder;
    } else if (data is BulkDrag) {
      return _canAcceptBulkDrop(data, targetFolder);
    }
    return false;
  }

  bool _canAcceptBulkDrop(BulkDrag data, String targetFolder) {
    if (data.folderPaths.contains(targetFolder)) return false;
    for (final gp in data.folderPaths) {
      if (targetFolder.startsWith('$gp/')) return false;
    }
    return true;
  }

  void _handleDrop(SessionDragData data, String targetFolder) {
    if (data is SessionDrag) {
      widget.onSessionMoved?.call(data.session.id, targetFolder);
    } else if (data is FolderDrag) {
      widget.onFolderMoved?.call(data.folderPath, targetFolder);
    } else if (data is BulkDrag) {
      widget.onBulkMoved?.call(data.sessionIds, data.folderPaths, targetFolder);
    }
  }

  // ── Cross-marquee (session panel → file pane) ──

  void _onPointerDown(PointerDownEvent e) {
    if (_mobile) return;
    handleMarqueePointerDown(e);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mobile || marqueeAnchor == null) return;

    final distance = (e.localPosition - marqueeAnchor!).distance;
    if (!marqueeActive && !_crossMarqueeActive) {
      if (distance < 5.0) return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box != null && widget.crossMarquee != null) {
      if (_handleCrossMarquee(e, box)) return;
    }

    if (marqueeDragActive) return;

    if (!marqueeActive) {
      marqueeActive = true;
      onMarqueeActivated();
    }

    setState(() {
      marqueeStart = marqueeAnchor;
      marqueeCurrent = e.localPosition;
    });
    final a = _clampedIndex(marqueeStart!.dy);
    final b = _clampedIndex(marqueeCurrent!.dy);
    applyMarqueeSelection(a < b ? a : b, a > b ? a : b, ctrlHeld: isCtrlHeld);
  }

  int _clampedIndex(double localY) {
    final maxIdx = marqueeItemCount - 1;
    if (maxIdx < 0) return 0;
    return marqueeRowIndexAt(localY).clamp(0, maxIdx);
  }

  bool _handleCrossMarquee(PointerMoveEvent e, RenderBox box) {
    final local = e.localPosition;
    final size = box.size;
    final outside =
        local.dx > size.width ||
        local.dx < 0 ||
        local.dy < 0 ||
        local.dy > size.height;

    if (outside) {
      if (marqueeActive) {
        setState(() {
          marqueeStart = null;
          marqueeCurrent = null;
          marqueeActive = false;
        });
        widget.onMarqueeEnd?.call();
        widget.onMarqueeSelect?.call({}, {});
      }
      if (!_crossMarqueeActive) {
        _crossMarqueeActive = true;
        widget.crossMarquee!.start(e.position);
      } else {
        widget.crossMarquee!.move(e.position);
      }
      return true;
    }

    if (_crossMarqueeActive) {
      _crossMarqueeActive = false;
      widget.crossMarquee!.end();
      marqueeAnchor = e.localPosition;
    }
    return false;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_crossMarqueeActive) {
      _crossMarqueeActive = false;
      widget.crossMarquee?.end();
      marqueeAnchor = null;
      return;
    }
    handleMarqueePointerUp(e);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tree.isEmpty) {
      return Center(
        child: Text(
          S.of(context).noSessions,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
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
        setState(() => _dropTargetFolder = null);
        _handleDrop(details.data, '');
      },
      onMove: (_) {
        if (_dropTargetFolder != '') {
          setState(() => _dropTargetFolder = '');
        }
      },
      onLeave: (_) {
        if (_dropTargetFolder == '') {
          setState(() => _dropTargetFolder = null);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Stack(
          children: [
            ListView.builder(
              controller: marqueeScrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: flatNodes.length,
              itemExtent: _rowHeight,
              itemBuilder: (context, index) {
                final (node, depth) = flatNodes[index];
                if (node.isGroup) {
                  return _buildFolderTile(node, depth);
                } else {
                  return _buildSessionTile(node, depth);
                }
              },
            ),
            if (marqueeVisible)
              buildMarqueeOverlay(Theme.of(context).colorScheme.primary),
          ],
        );
      },
    );
  }

  BoxDecoration _rowDecoration(
    bool isDropTarget,
    bool hovered,
    bool isSelected,
    ThemeData theme,
  ) {
    final Color? bg;
    if (isDropTarget) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (isSelected) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (hovered) {
      bg = AppTheme.hover;
    } else {
      bg = null;
    }
    return BoxDecoration(
      color: bg,
      border: isDropTarget
          ? Border.all(color: theme.colorScheme.primary, width: 1)
          : null,
      borderRadius: AppTheme.radiusSm,
    );
  }

  Widget _buildDragFeedback(
    ThemeData theme,
    bool isBulk,
    IconData icon,
    String label,
  ) {
    final totalCount =
        widget.selectedIds.length + widget.selectedFolderPaths.length;
    return Material(
      elevation: 4,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: AppTheme.radiusMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBulk ? Icons.file_copy : icon,
              size: 12,
              color: AppTheme.fgFaint,
            ),
            const SizedBox(width: 4),
            Text(
              isBulk ? '$totalCount items' : label,
              style: TextStyle(fontSize: AppFonts.sm),
            ),
          ],
        ),
      ),
    );
  }

  Color? _sessionRowColor(bool highlighted, bool hovered, ThemeData theme) {
    if (highlighted && !widget.selectMode) {
      return theme.colorScheme.primary.withValues(alpha: 0.15);
    }
    if (hovered) return AppTheme.hover;
    return null;
  }

  Widget _buildIndentGuides(int depth, ThemeData theme) {
    if (depth == 0) return const SizedBox(width: 8);
    final guideColor = AppTheme.borderLight;
    return SizedBox(
      width: 8.0 + depth * 16.0,
      child: Row(
        children: [
          const SizedBox(width: 8),
          for (var i = 0; i < depth; i++)
            SizedBox(
              width: 16,
              child: Center(child: Container(width: 1, color: guideColor)),
            ),
        ],
      ),
    );
  }

  Widget _buildFolderContent(
    SessionTreeNode node,
    int depth,
    bool isDropTarget,
  ) {
    final expanded = _expandedFolders.contains(node.fullPath);
    final theme = Theme.of(context);
    final isSelected = widget.selectedFolderPaths.contains(node.fullPath);

    return HoverRegion(
      onTap: () => _onFolderTap(node.fullPath, expanded),
      onSecondaryTapUp: (d) {
        widget.onFolderContextMenu?.call(node.fullPath, d.globalPosition);
      },
      onLongPressStart: _mobile
          ? (d) => widget.onFolderContextMenu?.call(
              node.fullPath,
              d.globalPosition,
            )
          : null,
      builder: (hovered) => Container(
        height: _rowHeight,
        padding: EdgeInsets.only(left: _mobile ? 8.0 : 12.0, right: 8),
        decoration: _rowDecoration(isDropTarget, hovered, isSelected, theme),
        child: Row(
          children: _buildFolderRowChildren(node, depth, expanded, theme),
        ),
      ),
    );
  }

  void _onFolderTap(String fullPath, bool expanded) {
    // If there's an active selection, toggle folder selection instead
    if (widget.selectedIds.isNotEmpty ||
        widget.selectedFolderPaths.isNotEmpty) {
      widget.onToggleFolderSelected?.call(fullPath);
      return;
    }
    setState(() {
      if (expanded) {
        _expandedFolders.remove(fullPath);
      } else {
        _expandedFolders.add(fullPath);
      }
    });
  }

  List<Widget> _buildFolderRowChildren(
    SessionTreeNode node,
    int depth,
    bool expanded,
    ThemeData theme,
  ) {
    return [
      if (depth > 0) _buildIndentGuides(depth, theme),
      Transform.rotate(
        angle: expanded ? 0 : -1.5708, // -90° in radians
        child: Icon(Icons.expand_more, size: _iconSize, color: AppTheme.fgDim),
      ),
      const SizedBox(width: 4),
      Icon(
        expanded ? Icons.folder_open : Icons.folder,
        size: _iconSize,
        color: AppTheme.yellow,
      ),
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
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          '${node.sessionCount}',
          style: TextStyle(
            fontSize: _subFontSize,
            color: AppTheme.fgFaint,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ];
  }

  Widget _buildFolderTile(SessionTreeNode node, int depth) {
    // On mobile: no drag&drop, long-press opens context menu (handled in _buildFolderContent)
    if (_mobile) {
      return _buildFolderContent(node, depth, false);
    }

    final theme = Theme.of(context);

    // Desktop: Draggable + DragTarget — if part of a bulk selection, drag all
    final isFolderSelected = widget.selectedFolderPaths.contains(node.fullPath);
    final isBulk = isFolderSelected && _hasBulkSelection;
    final SessionDragData dragData = isBulk
        ? BulkDrag(
            sessionIds: widget.selectedIds,
            folderPaths: widget.selectedFolderPaths,
          )
        : FolderDrag(node.fullPath);

    return Draggable<SessionDragData>(
      data: dragData,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDraggableCanceled: onDragCanceled,
      feedback: _buildDragFeedback(theme, isBulk, Icons.folder, node.name),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildFolderContent(node, depth, false),
      ),
      child: DragTarget<SessionDragData>(
        onWillAcceptWithDetails: (details) =>
            _canAcceptDrop(details.data, node.fullPath),
        onAcceptWithDetails: (details) {
          setState(() => _dropTargetFolder = null);
          _handleDrop(details.data, node.fullPath);
        },
        onMove: (_) {
          if (_dropTargetFolder != node.fullPath) {
            setState(() => _dropTargetFolder = node.fullPath);
          }
        },
        onLeave: (_) {
          if (_dropTargetFolder == node.fullPath) {
            setState(() => _dropTargetFolder = null);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return _buildFolderContent(
            node,
            depth,
            _dropTargetFolder == node.fullPath,
          );
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
    widget.onSessionSelected?.call(session.id);
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
    final isConnected = widget.connectedSessionIds.contains(session.id);
    final isConnecting =
        !isConnected && widget.connectingSessionIds.contains(session.id);
    final Color iconColor;
    if (isConnected) {
      iconColor = AppTheme.connectedColor(theme.brightness);
    } else if (isConnecting) {
      iconColor = AppTheme.connectingColor(theme.brightness);
    } else {
      iconColor = AppTheme.fgFaint;
    }
    final bool isActive = isConnected || isConnecting;

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
      else
        _buildIndentGuides(depth, theme),
      if (!widget.selectMode) ...[
        // Spacer matching the expand arrow width in folder rows
        SizedBox(width: _iconSize + 4),
        Icon(Icons.terminal, size: _authIconSize, color: iconColor),
        const SizedBox(width: 6),
      ],
      if (session.incomplete)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: S.of(context).credentialsNotSet,
            child: Icon(
              Icons.warning_amber,
              size: _authIconSize,
              color: AppTheme.connectingColor(theme.brightness),
            ),
          ),
        ),
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: Text(
                node.name,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: _fontSize,
                  color: isActive ? AppTheme.fg : AppTheme.fgDim,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                session.host,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: AppFonts.xxs,
                  color: AppTheme.fgFaint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

    final Widget content = HoverRegion(
      onTap: () => _onSessionTap(session),
      onDoubleTap: canInteract
          ? () => widget.onSessionDoubleTap?.call(session)
          : null,
      onSecondaryTapUp: canInteract
          ? (details) => widget.onSessionContextMenu?.call(
              session,
              details.globalPosition,
            )
          : null,
      onLongPressStart: (_mobile && !widget.selectMode)
          ? (d) => widget.onSessionContextMenu?.call(session, d.globalPosition)
          : null,
      builder: (hovered) => Container(
        height: _rowHeight,
        padding: const EdgeInsets.only(right: 8),
        color: _sessionRowColor(isSelected || isChecked, hovered, theme),
        child: Row(
          children: _buildSessionRowChildren(
            node,
            session,
            depth,
            isChecked,
            theme,
          ),
        ),
      ),
    );

    // Select mode or mobile: no drag&drop
    if (_mobile || widget.selectMode) return content;

    // Desktop: Draggable — if part of a bulk selection, drag all selected items
    final isBulk = isChecked && _hasBulkSelection;
    final SessionDragData dragData = isBulk
        ? BulkDrag(
            sessionIds: widget.selectedIds,
            folderPaths: widget.selectedFolderPaths,
          )
        : SessionDrag(session);

    return Draggable<SessionDragData>(
      data: dragData,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDraggableCanceled: onDragCanceled,
      feedback: _buildDragFeedback(theme, isBulk, Icons.terminal, node.name),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: content,
    );
  }
}
