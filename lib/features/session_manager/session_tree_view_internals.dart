part of 'session_tree_view.dart';

/// Drag-and-drop + pointer handlers + per-row widget builders for the
/// session tree. Lives as an extension on [_SessionTreeViewState] so
/// the helpers reach `widget`, `_expandedFolders`, the cached flat
/// list, and the MarqueeMixin overrides without going through a
/// public surface; `part of` joins the file into the same library so
/// library-private names stay reachable.
///
/// `setState` is `@protected` and not callable from extensions, so
/// the State exposes a `rebuild(VoidCallback)` wrapper that the
/// builders / handlers go through whenever they flip a UI flag.
extension _Internals on _SessionTreeViewState {
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

  Widget _buildDragTarget(List<(SessionTreeNode, int)> flatNodes) {
    return DragTarget<SessionDragData>(
      onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data, ''),
      onAcceptWithDetails: (details) {
        rebuild(() => _dropTargetFolder = null);
        _handleDrop(details.data, '');
      },
      onMove: (_) {
        if (_dropTargetFolder != '') {
          rebuild(() => _dropTargetFolder = '');
        }
      },
      onLeave: (_) {
        if (_dropTargetFolder == '') {
          rebuild(() => _dropTargetFolder = null);
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
      padding: const EdgeInsetsDirectional.only(end: 8),
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
            const SizedBox(width: AppSpacing.xs),
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
        const SizedBox(width: AppSpacing.sm)
      else
        SizedBox(
          width: 8.0 + depth * 16.0,
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.sm),
              for (var i = 0; i < depth; i++)
                SizedBox(
                  width: 16,
                  child: Center(child: Container(width: 1, color: guideColor)),
                ),
            ],
          ),
        ),
      if (expandArrow != null) ...[
        expandArrow,
        const SizedBox(width: AppSpacing.xs),
      ],
      icon,
      const SizedBox(width: AppSpacing.xxs),
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
      rebuild(() {
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
            fontFamily: AppFonts.interFamily,
            fontSize: _fontSize,
            fontWeight: FontWeight.w500,
            color: AppTheme.fgDim,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
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
        rebuild(() => _dropTargetFolder = null);
        _handleDrop(details.data, node.fullPath);
      },
      onMove: (_) {
        if (_dropTargetFolder != node.fullPath) {
          rebuild(() => _dropTargetFolder = node.fullPath);
        }
      },
      onLeave: (_) {
        if (_dropTargetFolder == node.fullPath) {
          rebuild(() => _dropTargetFolder = null);
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

  /// Per-protocol row icon. SSH stays on `Icons.terminal` because
  /// the row leads into a shell + SFTP browser; WebDAV gets an
  /// outlined cloud to signal an HTTP-backed file store; S3 gets
  /// the outlined inventory glyph to read as a bucket / object
  /// store. All three are outline-weight so they sit consistently
  /// among the connected / connecting / faint state tints.
  IconData _iconForKind(SessionKind kind) {
    switch (kind) {
      case SessionKind.ssh:
        return Icons.terminal;
      case SessionKind.webdav:
        return Icons.cloud_outlined;
      case SessionKind.s3:
        return Icons.inventory_2_outlined;
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
          icon: Icon(
            _iconForKind(session.kind),
            size: _authIconSize,
            color: iconColor,
          ),
        ),
      if (!session.isValid)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
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
                  fontFamily: AppFonts.interFamily,
                  fontSize: _fontSize,
                  color: isActive ? AppTheme.fg : AppTheme.fgDim,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SessionTagDots(sessionId: session.id),
            SessionViaBadge(session: session),
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
    // Parent folder of this row — used as the drop target when the user
    // drags something onto the row's empty area (i.e. onto "the space of
    // the expanded folder" rather than directly onto the folder row).
    // Without this wrap the drop event bubbled to the root DragTarget
    // and the dragged session landed at the tree root, which users read
    // as "drag into folder only works when I hit the folder header".
    final String parentFolder = session.folder;

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

    // The row itself is a DragTarget for its parent folder. Hovering a
    // drop over this session row highlights the enclosing folder (via
    // `_dropTargetFolder`) and drops land inside `parentFolder`, so the
    // "drag onto any child inside an expanded folder" affordance works
    // instead of silently dropping at the tree root. The folder's own
    // DragTarget still takes priority when hovered directly because
    // DragTarget nesting resolves innermost-wins in the hit test.
    final Widget wrapped = DragTarget<SessionDragData>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptDrop(details.data, parentFolder),
      onAcceptWithDetails: (details) {
        rebuild(() => _dropTargetFolder = null);
        _handleDrop(details.data, parentFolder);
      },
      onMove: (_) {
        if (_dropTargetFolder != parentFolder) {
          rebuild(() => _dropTargetFolder = parentFolder);
        }
      },
      onLeave: (_) {
        if (_dropTargetFolder == parentFolder) {
          rebuild(() => _dropTargetFolder = null);
        }
      },
      builder: (context, _, _) => content,
    );

    // Desktop: wrap in Draggable when the row is highlighted — either
    // multi-selected (checked) or single-click focused. Plain rows stay
    // unwrapped so a pointer-down on them starts a marquee instead of a
    // drag, matching the UX rule "drag from highlighted, marquee from
    // empty".
    if (!isChecked && !isSelected) return wrapped;

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
      child: wrapped,
    );
  }
}
