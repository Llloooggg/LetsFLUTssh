part of 'file_pane.dart';

/// Per-pane widget builders extracted from the State body — header
/// (label + breadcrumb + nav buttons + path editor), column headers,
/// the file-list rendering chain (list + error / empty states + items
/// + drag feedback), the footer status row, and the drop-target wrap.
/// Lives as an extension on [_FilePaneState] so the helpers reach
/// `ctrl` / `widget` / the per-pane fields directly without going
/// through a public surface; `part of` joins the file into the same
/// library so library-private names stay reachable.
///
/// `setState` is `@protected` and not callable from extensions, so
/// the State exposes a thin `rebuild(VoidCallback)` wrapper that the
/// builders go through whenever they flip a UI flag.
extension _Layout on _FilePaneState {
  // ── Header ──

  Widget _buildHeader(ThemeData theme) {
    final isLocal = ctrl.label.toUpperCase() == 'LOCAL';
    final labelColor = isLocal ? AppTheme.blue : AppTheme.green;
    final displayLabel = isLocal ? S.of(context).local : S.of(context).remote;

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showNav = constraints.maxWidth > 160;
          return ClippedRow(
            children: [
              Text(
                displayLabel.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _buildBreadcrumb()),
              if (showNav) ...[
                const SizedBox(width: AppSpacing.xs),
                _navButton(
                  Icons.arrow_back,
                  ctrl.canGoBack ? ctrl.goBack : null,
                  S.of(context).back,
                ),
                _navButton(
                  Icons.arrow_forward,
                  ctrl.canGoForward ? ctrl.goForward : null,
                  S.of(context).forward,
                ),
                _navButton(
                  Icons.arrow_upward,
                  ctrl.navigateUp,
                  S.of(context).up,
                ),
                _navButton(Icons.refresh, ctrl.refresh, S.of(context).refresh),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildBreadcrumb() {
    if (_editingPath) return _buildPathEditor();

    final bc = parseBreadcrumbPath(ctrl.currentPath);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildRootSegment(bc.rootLabel, bc.rootPath),
          ..._buildPathSegments(bc),
          AppIconButton(
            icon: Icons.edit,
            onTap: () {
              _pathController.text = ctrl.currentPath;
              rebuild(() => _editingPath = true);
            },
            tooltip: S.of(context).editPath,
            dense: true,
            color: AppTheme.fgFaint,
          ),
        ],
      ),
    );
  }

  Widget _buildRootSegment(String? rootLabel, String rootPath) {
    if (rootLabel != null) {
      return HoverRegion(
        cursor: SystemMouseCursors.click,
        onTap: () => ctrl.navigateTo(rootPath),
        builder: (hovered) => Text(
          rootLabel,
          style: AppFonts.mono(
            fontSize: AppFonts.xs,
            color: hovered ? AppTheme.fg : AppTheme.fgFaint,
          ),
        ),
      );
    }
    return AppIconButton(
      icon: Icons.home,
      onTap: () => ctrl.navigateTo(rootPath),
      tooltip: S.of(context).root,
      dense: true,
      color: AppTheme.fgFaint,
    );
  }

  List<Widget> _buildPathSegments(BreadcrumbPath bc) {
    final separatorText = bc.isWindows ? ' \\ ' : ' / ';
    final sepStyle = AppFonts.mono(
      fontSize: AppFonts.xs,
      color: AppTheme.fgFaint,
    );
    return [
      for (var i = 0; i < bc.navParts.length; i++) ...[
        Text(separatorText, style: sepStyle),
        HoverRegion(
          cursor: SystemMouseCursors.click,
          onTap: () => ctrl.navigateTo(buildPathForSegment(bc, i)),
          builder: (hovered) {
            final isLast = i == bc.navParts.length - 1;
            final baseColor = isLast ? AppTheme.fg : AppTheme.fgDim;
            final color = hovered ? AppTheme.accent : baseColor;
            return Text(
              bc.navParts[i],
              style: AppFonts.mono(fontSize: AppFonts.xs, color: color),
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ],
    ];
  }

  Widget _buildPathEditor() {
    return SizedBox(
      height: AppTheme.itemHeightXs,
      child: TextField(
        controller: _pathController,
        focusNode: _pathFocusNode,
        autofocus: true,
        style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fg),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bg3,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.accent),
          ),
          hintText: ctrl.currentPath,
          hintStyle: AppFonts.mono(
            fontSize: AppFonts.xs,
            color: AppTheme.fgFaint,
          ),
        ),
        onSubmitted: (val) {
          rebuild(() => _editingPath = false);
          if (val.trim().isNotEmpty) {
            ctrl.navigateTo(val.trim());
          }
        },
        onTapOutside: (_) => _pathFocusNode.unfocus(),
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return AppIconButton(
      icon: icon,
      onTap: onPressed,
      tooltip: tooltip,
      dense: true,
      color: AppTheme.fgFaint,
    );
  }

  // ── Column headers ──

  Widget _buildColumnHeaders(
    ThemeData theme,
    ({bool size, bool modified, bool mode, bool owner}) cols,
    double availableWidth,
  ) {
    final headerStyle = AppFonts.inter(
      fontSize: AppFonts.xs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    // Dynamic max: ensure the Name column keeps at least 60 px.
    const minName = 60.0;
    const overhead = 36.0; // icon(20) + padding(16)
    final totalOtherCols = _totalColumnWidths(cols);

    double maxFor(double colWidth, double minWidth) {
      final others = totalOtherCols - (10 + colWidth);
      return (availableWidth - overhead - others - 10 - minName).clamp(
        minWidth,
        200.0,
      );
    }

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppTheme.bg3),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          const SizedBox(width: 20), // icon space
          Expanded(
            child: _sortableCell(
              S.of(context).name,
              SortColumn.name,
              headerStyle,
            ),
          ),
          if (cols.size) ...[
            ColumnResizeHandle(
              onDrag: (dx) => rebuild(() {
                final max = maxFor(_sizeColWidth, 40);
                _sizeColWidth = (_sizeColWidth - dx).clamp(40, max);
              }),
            ),
            _sortableCell(
              S.of(context).size,
              SortColumn.size,
              headerStyle,
              width: _sizeColWidth,
            ),
          ],
          if (cols.modified) ...[
            ColumnResizeHandle(
              onDrag: (dx) => rebuild(() {
                final max = maxFor(_modifiedColWidth, 50);
                _modifiedColWidth = (_modifiedColWidth - dx).clamp(50, max);
              }),
            ),
            _sortableCell(
              S.of(context).modified,
              SortColumn.modified,
              headerStyle,
              width: _modifiedColWidth,
            ),
          ],
          if (cols.mode) ...[
            ColumnResizeHandle(
              onDrag: (dx) => rebuild(() {
                final max = maxFor(_modeColWidth, 50);
                _modeColWidth = (_modeColWidth - dx).clamp(50, max);
              }),
            ),
            _sortableCell(
              S.of(context).mode,
              SortColumn.mode,
              headerStyle,
              width: _modeColWidth,
            ),
          ],
          if (cols.owner) ...[
            ColumnResizeHandle(
              onDrag: (dx) => rebuild(() {
                final max = maxFor(_ownerColWidth, 40);
                _ownerColWidth = (_ownerColWidth - dx).clamp(40, max);
              }),
            ),
            _sortableCell(
              S.of(context).owner,
              SortColumn.owner,
              headerStyle,
              width: _ownerColWidth,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sortableCell(
    String label,
    SortColumn column,
    TextStyle style, {
    double? width,
    TextAlign? textAlign,
  }) {
    return SortableHeaderCell(
      label: label,
      isActive: ctrl.sortColumn == column,
      sortAscending: ctrl.sortAscending,
      onTap: () => ctrl.setSort(column),
      style: style,
      width: width,
      textAlign: textAlign,
    );
  }

  double _totalColumnWidths(
    ({bool size, bool modified, bool mode, bool owner}) cols,
  ) {
    double total = 0;
    if (cols.size) total += 10 + _sizeColWidth;
    if (cols.modified) total += 10 + _modifiedColWidth;
    if (cols.mode) total += 10 + _modeColWidth;
    if (cols.owner) total += 10 + _ownerColWidth;
    return total;
  }

  // ── File list ──

  Widget _buildFileList(
    ThemeData theme,
    ({bool size, bool modified, bool mode, bool owner}) cols,
  ) {
    // Only show the full-pane spinner on the first load, when there is
    // nothing to display yet. A refresh of an already-populated pane (after a
    // download lands, a mkdir, a rename) keeps the current list rendered — it
    // updates in place once `refresh()` returns, so the scroll controller
    // stays attached and the user keeps their scroll position instead of being
    // thrown back to the top.
    if (ctrl.loading && ctrl.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.error != null) {
      return _buildErrorState(theme);
    }
    if (ctrl.entries.isEmpty) {
      return _buildEmptyState();
    }
    return _buildFileListContent(theme, cols);
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppTheme.itemHeightLg,
            height: AppTheme.itemHeightLg,
            decoration: BoxDecoration(color: AppTheme.bg3),
            child: Icon(Icons.error_outline, size: 22, color: AppTheme.red),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            S.of(context).connectionError,
            style: AppFonts.inter(fontSize: AppFonts.lg, color: AppTheme.fgDim),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            localizeError(S.of(context), ctrl.error!),
            style: AppFonts.inter(
              fontSize: AppFonts.sm,
              color: AppTheme.fgFaint,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: ctrl.refresh,
            child: Container(
              height: AppTheme.controlHeightXs,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: AppTheme.bg3,
              alignment: Alignment.center,
              child: Text(
                S.of(context).retry,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.fgDim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return GestureDetector(
      onTap: () {
        ctrl.clearSelection();
        widget.onPaneActivated?.call();
      },
      onSecondaryTapUp: (d) =>
          _showBackgroundContextMenu(context, d.globalPosition),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Text(
          S.of(context).emptyDirectory,
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
        ),
      ),
    );
  }

  Widget _buildFileListContent(
    ThemeData theme,
    ({bool size, bool modified, bool mode, bool owner}) cols,
  ) {
    return Listener(
      onPointerDown: handleMarqueePointerDown,
      onPointerMove: handleMarqueePointerMove,
      onPointerUp: handleMarqueePointerUp,
      child: GestureDetector(
        onSecondaryTapUp: (d) =>
            _showBackgroundContextMenu(context, d.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          key: _fileListKey,
          children: [
            ListView.builder(
              controller: marqueeScrollController,
              itemCount: ctrl.entries.length,
              itemExtent: _FilePaneState._rowHeight,
              itemBuilder: (context, index) =>
                  _buildFileListItem(context, index, theme, cols),
            ),
            if (marqueeVisible) buildMarqueeOverlay(theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildFileListItem(
    BuildContext context,
    int index,
    ThemeData theme,
    ({bool size, bool modified, bool mode, bool owner}) cols,
  ) {
    final entry = ctrl.entries[index];

    // Selection state is read off `selectedListenable` so a per-row
    // toggle redraws only the affected rows, not the whole pane.
    // Selection mutators bump the listenable without firing the
    // broad ChangeNotifier — see `FilePaneController` selection-
    // mutator note. Folder-size rows compose two listenables in
    // tandem (selection + size revision).
    if (entry.isDir && widget.showFolderSizes) {
      return ValueListenableBuilder<Set<String>>(
        valueListenable: ctrl.selectedListenable,
        builder: (context, sel, _) {
          final isSelected = sel.contains(entry.path);
          return ValueListenableBuilder<int>(
            valueListenable: ctrl.folderSizeRevision,
            builder: (context, _, _) {
              final cachedSize = ctrl.folderSize(entry.path);
              final folderSizeText = switch (cachedSize) {
                FolderSizeOk(:final bytes) => formatSize(bytes),
                FolderSizeFailed() => '?',
                null => () {
                  ctrl.requestFolderSize(entry.path);
                  return '...';
                }(),
              };
              return _buildFileRowWrapper(
                context,
                theme,
                entry,
                isSelected,
                cols,
                folderSizeText,
              );
            },
          );
        },
      );
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: ctrl.selectedListenable,
      builder: (context, sel, _) {
        final isSelected = sel.contains(entry.path);
        return _buildFileRowWrapper(
          context,
          theme,
          entry,
          isSelected,
          cols,
          null,
        );
      },
    );
  }

  Widget _buildFileRowWrapper(
    BuildContext context,
    ThemeData theme,
    FileEntry entry,
    bool isSelected,
    ({bool size, bool modified, bool mode, bool owner}) cols,
    String? folderSizeText,
  ) {
    final row = FileRow(
      key: ValueKey(entry.path),
      entry: entry,
      isSelected: isSelected,
      sizeWidth: cols.size ? _sizeColWidth : 0,
      modifiedWidth: cols.modified ? _modifiedColWidth : 0,
      modeWidth: cols.mode ? _modeColWidth : 0,
      ownerWidth: cols.owner ? _ownerColWidth : 0,
      folderSizeText: folderSizeText,
      onTap: () => ctrl.selectSingle(entry.path),
      onCtrlTap: () => ctrl.toggleSelect(entry.path),
      onDoubleTap: () {
        if (entry.isDir) {
          ctrl.navigateTo(entry.path);
        } else {
          widget.onTransfer?.call(entry);
        }
      },
      onContextMenu: (offset) => _showContextMenu(context, offset, entry),
    );

    if (!isSelected) return row;

    final selected = ctrl.selectedEntries;
    final dragEntries = selected.length > 1 ? selected : [entry];

    return Draggable<PaneDragData>(
      data: PaneDragData(sourcePaneId: widget.paneId, entries: dragEntries),
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      onDraggableCanceled: onDragCanceled,
      feedback: _buildDragFeedback(theme, entry, dragEntries),
      child: row,
    );
  }

  Widget _buildDragFeedback(
    ThemeData theme,
    FileEntry entry,
    List<FileEntry> dragEntries,
  ) {
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
            Icon(_FilePaneState._dragIcon(dragEntries, entry), size: 14),
            const SizedBox(width: AppSpacing.xs),
            Text(
              dragEntries.length > 1
                  ? S.of(context).dragItemCount(dragEntries.length)
                  : entry.name,
              style: TextStyle(fontSize: AppFonts.md),
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer ──

  Widget _buildFooter(ThemeData theme) {
    final count = ctrl.entries.length;
    final style = AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint);

    // Selection-count chip subscribes to `selectedListenable` so a
    // per-row toggle redraws only the chip, not the whole footer.
    // The leading "N items / total size" text doesn't depend on
    // selection — it stays outside the listenable rebuild scope.
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.bg3,
      child: ClippedRow(
        children: [
          Flexible(
            child: Text(
              S
                  .of(context)
                  .itemCountWithSize(count, formatSize(ctrl.totalFileSize)),
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // `ValueListenableBuilder` returns a Flexible directly so
          // the parent `ClippedRow` (Flex-derived) accepts the
          // FlexParentData. Empty selection collapses to a
          // SizedBox.shrink — also Flexible-compatible since the
          // builder return type is uniform.
          Flexible(
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: ctrl.selectedListenable,
              builder: (context, sel, _) {
                if (sel.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    '(${sel.length} selected)',
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Drop target ──

  Widget _buildDropTarget(Widget child) {
    return DragTarget<PaneDragData>(
      onWillAcceptWithDetails: (details) {
        if (widget.onDropReceived == null) return false;
        return details.data.sourcePaneId != widget.paneId;
      },
      onAcceptWithDetails: (details) {
        _focusNode.requestFocus();
        widget.onDropReceived?.call(details.data.entries);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          decoration: isHovering
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: AppTheme.radiusSm,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                )
              : null,
          child: child,
        );
      },
    );
  }
}
