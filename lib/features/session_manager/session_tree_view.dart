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
import 'session_via_badge.dart';

// Drag-and-drop, pointer handlers, and the per-row build chain live
// in a part sibling so the State + lifecycle + MarqueeMixin
// scaffolding stays the focus of this file. Same `part of` pattern
// session_panel / file_pane use; setState calls inside the extension
// methods route through the State's `rebuild(VoidCallback)` wrapper.
part 'session_tree_view_internals.dart';

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

  /// Re-renders the tree from a per-section extension method.
  /// `State.setState` is `@protected` so extensions on
  /// `_SessionTreeViewState` cannot call it directly; this wrapper
  /// keeps the rebuild path inside the class while letting the
  /// internals part file mutate the same fields.
  void rebuild(VoidCallback fn) => setState(fn);
}
