import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/hover_region.dart';
import '../../utils/platform.dart';
import '../../widgets/marquee_mixin.dart';
import '../../widgets/tag_dots.dart';
import '../../widgets/threshold_draggable.dart';

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

  /// IDs of sessions that currently have an active (connected) connection.
  final Set<String> connectedSessionIds;

  /// IDs of sessions that are currently connecting (SSH handshake in progress).
  final Set<String> connectingSessionIds;

  /// Called when a session is selected (single-click on desktop).
  /// Used by parent to track the focused session for keyboard shortcuts.
  final void Function(String sessionId)? onSessionSelected;

  /// Currently focused session (single-click highlight on desktop).
  /// Managed by parent — tree view uses it for row highlighting only.
  final String? focusedSessionId;

  /// Currently focused folder (single-click highlight on desktop).
  /// Managed by parent — tree view uses it for row highlighting only.
  final String? focusedFolderPath;

  /// Whether the parent panel currently has keyboard focus.
  /// When true, the focused row uses a prominent highlight.
  /// When false, it shows a subtle "pinned" indicator instead.
  final bool panelHasFocus;

  /// Called when a folder row is clicked (single-click on desktop).
  /// Used by parent to show folder details in the info panel.
  final void Function(String folderPath, int sessionCount)? onFolderSelected;

  /// Called when empty space is clicked (no session or folder).
  /// Used by parent to clear focused session/folder.
  final VoidCallback? onEmptySpaceTap;

  /// Folder paths that should start collapsed (persisted across restarts).
  final Set<String> collapsedFolders;

  /// Called when a folder is expanded/collapsed so the parent can persist.
  final void Function(String folderPath)? onToggleFolderCollapsed;

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
    this.connectedSessionIds = const {},
    this.connectingSessionIds = const {},
    this.onSessionSelected,
    this.focusedSessionId,
    this.focusedFolderPath,
    this.panelHasFocus = true,
    this.onFolderSelected,
    this.onEmptySpaceTap,
    this.collapsedFolders = const {},
    this.onToggleFolderCollapsed,
  });

  @override
  State<SessionTreeView> createState() => _SessionTreeViewState();
}

class _SessionTreeViewState extends State<SessionTreeView> with MarqueeMixin {
  final _expandedFolders = <String>{};
  String? _dropTargetFolder; // highlight on drag hover

  // ── Manual double-tap detection (avoids GestureDetector.onDoubleTap
  //    which delays onTap by ~300 ms and conflicts with Draggable) ──
  DateTime _lastTapTime = DateTime(0);
  String? _lastTapSessionId;

  bool get _hasAnySelection =>
      widget.selectedIds.isNotEmpty || widget.selectedFolderPaths.isNotEmpty;

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
    _expandedFolders.removeAll(widget.collapsedFolders);
  }

  @override
  void didUpdateWidget(covariant SessionTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Expand newly added folders (unless they are persisted as collapsed).
    _expandNewFolders(widget.tree);
  }

  void _expandNewFolders(List<SessionTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isGroup) {
        if (!_expandedFolders.contains(node.fullPath) &&
            !widget.collapsedFolders.contains(node.fullPath)) {
          _expandedFolders.add(node.fullPath);
        }
        _expandNewFolders(node.children);
      }
    }
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
    // Report both multi-selected (checked) and single-focused rows as
    // "selected" so [handleMarqueePointerDown] skips the marquee anchor
    // for any visibly highlighted row. The row is then free for the
    // Draggable wrapper to claim the pointer sequence.
    final flatNodes = _cachedFlatNodes;
    if (flatNodes == null || index < 0 || index >= flatNodes.length) {
      return false;
    }
    final node = flatNodes[index].$1;
    if (node.session != null) {
      final id = node.session!.id;
      return widget.selectedIds.contains(id) || widget.focusedSessionId == id;
    }
    if (node.isGroup) {
      return widget.selectedFolderPaths.contains(node.fullPath) ||
          widget.focusedFolderPath == node.fullPath;
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
    widget.onEmptySpaceTap?.call();
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

  // ── Pointer handlers ──

  void _onPointerDown(PointerDownEvent e) {
    if (_mobile) return;
    handleMarqueePointerDown(e);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mobile) return;
    handleMarqueePointerMove(e);
    if (marqueeActive && marqueeStart != null && marqueeCurrent != null) {
      final a = _clampedIndex(marqueeStart!.dy);
      final b = _clampedIndex(marqueeCurrent!.dy);
      applyMarqueeSelection(a < b ? a : b, a > b ? a : b, ctrlHeld: isCtrlHeld);
    }
  }

  int _clampedIndex(double localY) {
    final maxIdx = marqueeItemCount - 1;
    if (maxIdx < 0) return 0;
    return marqueeRowIndexAt(localY).clamp(0, maxIdx);
  }

  void _onPointerUp(PointerUpEvent e) => handleMarqueePointerUp(e);

  @override
  Widget build(BuildContext context) {
    if (widget.tree.isEmpty) {
      return AppEmptyState(message: S.of(context).noSessions);
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

  /// Common row container shared by folder and session tiles.
  Widget _buildTreeRow({
    required List<Widget> children,
    Color? color,
    BoxDecoration? decoration,
  }) {
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.only(right: 8),
      decoration: decoration,
      color: decoration == null ? color : null,
      child: Row(children: children),
    );
  }

  BoxDecoration _rowDecoration(
    bool isDropTarget,
    bool hovered,
    bool isSelected,
    bool isFocused,
    ThemeData theme,
  ) {
    final Color? bg;
    Border? border;
    if (isDropTarget) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.15);
      border = Border.all(color: theme.colorScheme.primary, width: 1);
    } else if (isSelected) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (isFocused) {
      if (widget.panelHasFocus) {
        bg = theme.colorScheme.primary.withValues(alpha: 0.15);
      } else {
        bg = theme.colorScheme.onSurface.withValues(alpha: 0.08);
      }
    } else if (hovered) {
      bg = AppTheme.hover;
    } else {
      bg = null;
    }
    return BoxDecoration(
      color: bg,
      border: border,
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
              isBulk ? S.of(context).dragItemCount(totalCount) : label,
              style: TextStyle(fontSize: AppFonts.sm),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration? _sessionRowDecoration(
    bool highlighted,
    bool hovered,
    ThemeData theme,
  ) {
    if (highlighted && !widget.selectMode) {
      if (widget.panelHasFocus) {
        return BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          borderRadius: AppTheme.radiusSm,
        );
      }
      return BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: AppTheme.radiusSm,
      );
    }
    if (hovered) {
      return BoxDecoration(
        color: AppTheme.hover,
        borderRadius: AppTheme.radiusSm,
      );
    }
    return null;
  }

  /// Builds indent guide lines + leading icon for a tree row.
  ///
  /// Layout: [8px pad] [depth × 16px guides] [arrow? + 4px] [icon] [6px]
  /// Shared by folder and session rows to guarantee identical alignment.
  List<Widget> _buildRowLeading({
    required int depth,
    required Widget icon,
    Widget? expandArrow,
  }) {
    final guideColor = AppTheme.borderLight;
    return [
      if (depth == 0)
        const SizedBox(width: 8)
      else
        SizedBox(
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
        ),
      if (expandArrow != null) ...[expandArrow, const SizedBox(width: 4)],
      icon,
      const SizedBox(width: 6),
    ];
  }

  Widget _buildFolderContent(
    SessionTreeNode node,
    int depth,
    bool isDropTarget,
  ) {
    final expanded = _expandedFolders.contains(node.fullPath);
    final theme = Theme.of(context);
    final isSelected = widget.selectedFolderPaths.contains(node.fullPath);
    final isFocused = node.fullPath == widget.focusedFolderPath;

    return Semantics(
      label: node.name,
      button: true,
      selected: isSelected,
      expanded: expanded,
      child: HoverRegion(
        onTap: () => _onFolderTap(node, expanded),
        onCtrlTap: !_mobile
            ? () => widget.onToggleFolderSelected?.call(node.fullPath)
            : null,
        onSecondaryTapUp: (d) {
          widget.onFolderContextMenu?.call(node.fullPath, d.globalPosition);
        },
        onLongPressStart: _mobile
            ? (d) => widget.onFolderContextMenu?.call(
                node.fullPath,
                d.globalPosition,
              )
            : null,
        builder: (hovered) => _buildTreeRow(
          decoration: _rowDecoration(
            isDropTarget,
            hovered,
            isSelected,
            isFocused,
            theme,
          ),
          children: _buildFolderRowChildren(node, depth, expanded, theme),
        ),
      ),
    );
  }

  void _onFolderTap(SessionTreeNode node, bool expanded) {
    final fullPath = node.fullPath;

    // Plain click clears any existing selection (Ctrl+click handled by HoverRegion).
    if (!_mobile && _hasAnySelection) {
      widget.onMarqueeSelect?.call({}, {});
    }

    // Two-phase click: first tap focuses the folder (row highlight +
    // turns it into the `pasteCopiedSession` / "move here" target)
    // without changing its expand state; second tap on the already-
    // focused folder toggles expand. Finder's column view uses the
    // same pattern. Without the split, "click folder to select as
    // paste target" also collapsed whatever the user was pointing at
    // — user reported this as "хочу ткнуть в папку для копии, но
    // она сворачивается".
    final alreadyFocused = widget.focusedFolderPath == fullPath;

    if (!_mobile) {
      widget.onFolderSelected?.call(fullPath, node.sessionCount);
    }

    if (_mobile || alreadyFocused) {
      setState(() {
        if (expanded) {
          _expandedFolders.remove(fullPath);
        } else {
          _expandedFolders.add(fullPath);
        }
      });
      widget.onToggleFolderCollapsed?.call(fullPath);
    }
  }

  List<Widget> _buildFolderRowChildren(
    SessionTreeNode node,
    int depth,
    bool expanded,
    ThemeData theme,
  ) {
    return [
      ..._buildRowLeading(
        depth: depth,
        icon: Icon(
          expanded ? Icons.folder_open : Icons.folder,
          size: _iconSize,
          color: AppTheme.yellow,
        ),
        expandArrow: Transform.rotate(
          angle: expanded ? 0 : -1.5708,
          child: Icon(
            Icons.expand_more,
            size: _iconSize,
            color: AppTheme.fgDim,
          ),
        ),
      ),
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
    // Draggable wraps a folder if it is either multi-selected (checked)
    // or single-click focused. An unhighlighted folder must stay plain
    // so the pointer-down there starts a marquee instead of a drag —
    // matching the UX rule "drag from highlighted, marquee from empty".
    final isFolderChecked = widget.selectedFolderPaths.contains(node.fullPath);
    final isFolderFocused = widget.focusedFolderPath == node.fullPath;
    final isFolderHighlighted = isFolderChecked || isFolderFocused;

    // DragTarget is always present so items can be dropped onto folders.
    final Widget target = DragTarget<SessionDragData>(
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
    );

    // Only wrap in Draggable when the folder is highlighted (checked
    // or single-focused) — unhighlighted folders must stay unwrapped
    // so marquee can start from them.
    if (!isFolderHighlighted) return target;

    final isBulk = _hasBulkSelection;
    final SessionDragData dragData = isBulk
        ? BulkDrag(
            sessionIds: widget.selectedIds,
            folderPaths: widget.selectedFolderPaths,
          )
        : FolderDrag(node.fullPath);

    return ThresholdDraggable<SessionDragData>(
      data: dragData,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDraggableCanceled: onDragCanceled,
      feedback: _buildDragFeedback(theme, isBulk, Icons.folder, node.name),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildFolderContent(node, depth, false),
      ),
      child: target,
    );
  }

  void _onSessionTap(Session session) {
    if (widget.selectMode) {
      widget.onToggleSelected?.call(session.id);
      return;
    }

    // Plain click clears any existing selection (Ctrl+click handled by HoverRegion).
    if (!_mobile && _hasAnySelection) {
      widget.onMarqueeSelect?.call({}, {});
    }

    // Manual double-tap detection for desktop — avoids GestureDetector's
    // onDoubleTap which delays onTap by ~300 ms and conflicts with Draggable.
    if (!_mobile) {
      final now = DateTime.now();
      if (_lastTapSessionId == session.id &&
          now.difference(_lastTapTime).inMilliseconds < 400) {
        _lastTapTime = DateTime(0);
        _lastTapSessionId = null;
        widget.onSessionDoubleTap?.call(session);
        return;
      }
      _lastTapTime = now;
      _lastTapSessionId = session.id;
    }

    if (_mobile) {
      widget.onSessionDoubleTap?.call(session);
    } else {
      widget.onSessionSelected?.call(session.id);
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
      iconColor = AppTheme.connected;
    } else if (isConnecting) {
      iconColor = AppTheme.connecting;
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
        ..._buildRowLeading(
          depth: depth,
          icon: Icon(Icons.terminal, size: _authIconSize, color: iconColor),
        ),
      if (!session.isValid)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: S.of(context).credentialsNotSet,
            child: Icon(
              Icons.warning_amber,
              size: _authIconSize,
              color: AppTheme.connecting,
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
            SessionTagDots(sessionId: session.id),
          ],
        ),
      ),
    ];
  }

  Widget _buildSessionTile(SessionTreeNode node, int depth) {
    final session = node.session!;
    final isSelected = session.id == widget.focusedSessionId;
    final isChecked = widget.selectedIds.contains(session.id);
    final theme = Theme.of(context);
    final canInteract = !_mobile && !widget.selectMode;

    final Widget content = Semantics(
      label: session.displayName,
      button: true,
      selected: isSelected,
      child: HoverRegion(
        onTap: () => _onSessionTap(session),
        onCtrlTap: canInteract
            ? () => widget.onToggleSelected?.call(session.id)
            : null,
        onSecondaryTapUp: canInteract
            ? (details) => widget.onSessionContextMenu?.call(
                session,
                details.globalPosition,
              )
            : null,
        onLongPressStart: (_mobile && !widget.selectMode)
            ? (d) =>
                  widget.onSessionContextMenu?.call(session, d.globalPosition)
            : null,
        builder: (hovered) => _buildTreeRow(
          decoration: _sessionRowDecoration(
            isSelected || isChecked,
            hovered,
            theme,
          ),
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

    // Desktop: wrap in Draggable when the row is highlighted — either
    // multi-selected (checked) or single-click focused. Plain rows stay
    // unwrapped so a pointer-down on them starts a marquee instead of a
    // drag, matching the UX rule "drag from highlighted, marquee from
    // empty".
    if (!isChecked && !isSelected) return content;

    final isBulk = _hasBulkSelection;
    final SessionDragData dragData = isBulk
        ? BulkDrag(
            sessionIds: widget.selectedIds,
            folderPaths: widget.selectedFolderPaths,
          )
        : SessionDrag(session);

    return ThresholdDraggable<SessionDragData>(
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
