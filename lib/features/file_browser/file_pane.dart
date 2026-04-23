import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../core/shortcut_registry.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/clipped_row.dart';
import '../../widgets/column_resize_handle.dart';
import '../../widgets/sortable_header_cell.dart';
import '../../utils/format.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/marquee_mixin.dart';
import 'breadcrumb_path.dart';
import 'column_widths.dart';
import 'file_browser_controller.dart';
import 'file_pane_dialogs.dart';
import 'file_row.dart';

/// A single file browser pane (local or remote).
///
/// Supports drag&drop: files can be dragged from this pane and dropped
/// onto the other pane to trigger transfers.
class FilePane extends StatefulWidget {
  final FilePaneController controller;
  final String paneId;
  final void Function(FileEntry entry)? onTransfer;
  final void Function(List<FileEntry> entries)? onTransferMultiple;

  /// Called when the user presses Ctrl+C to copy selected entries.
  final VoidCallback? onCopy;

  /// Called when the user presses Ctrl+V to paste from clipboard.
  final VoidCallback? onPaste;

  /// Called when files are dropped onto this pane from the other pane.
  final void Function(List<FileEntry> entries)? onDropReceived;

  /// Called when files are dropped from the OS file manager.
  final void Function(List<String> paths)? onOsDropReceived;

  /// Called when the user starts interacting with this pane (pointer down).
  /// Used by parent to clear selection in the sibling pane.
  final VoidCallback? onPaneActivated;

  /// Whether to calculate and display folder sizes.
  final bool showFolderSizes;

  const FilePane({
    super.key,
    required this.controller,
    this.paneId = '',
    this.onTransfer,
    this.onTransferMultiple,
    this.onCopy,
    this.onPaste,
    this.onDropReceived,
    this.onOsDropReceived,
    this.onPaneActivated,
    this.showFolderSizes = false,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> with MarqueeMixin {
  final _focusNode = FocusNode();
  final _fileListKey = GlobalKey();
  final _pathController = TextEditingController();
  final _pathFocusNode = FocusNode();
  bool _editingPath = false;
  bool _osDragging = false;

  // Resizable column widths (compact defaults so Name gets more space).
  // Size and Modified share constants with the transfer queue so the
  // two surfaces stay visually aligned — see [FileBrowserColumns].
  double _sizeColWidth = FileBrowserColumns.size;
  double _modifiedColWidth = FileBrowserColumns.modifiedOrTime;
  double _modeColWidth = 65;
  double _ownerColWidth = 50;

  /// Determine which data columns fit within [width], hiding from right to left.
  ({bool size, bool modified, bool mode, bool owner}) _visibleColumns(
    double width,
  ) {
    const base = 36.0; // icon(20) + padding(16)
    final hasOwner = ctrl.entries.any((e) => e.owner.isNotEmpty);
    final s = 10 + _sizeColWidth;
    final m = 10 + _modifiedColWidth;
    final d = 10 + _modeColWidth;
    final o = hasOwner ? 10 + _ownerColWidth : 0.0;
    final avail = width - base;
    if (avail >= s + m + d + o) {
      return (size: true, modified: true, mode: true, owner: hasOwner);
    }
    if (avail >= s + m + d) {
      return (size: true, modified: true, mode: true, owner: false);
    }
    if (avail >= s + m) {
      return (size: true, modified: true, mode: false, owner: false);
    }
    if (avail >= s) {
      return (size: true, modified: false, mode: false, owner: false);
    }
    return (size: false, modified: false, mode: false, owner: false);
  }

  FilePaneController get ctrl => widget.controller;

  static IconData _dragIcon(List<FileEntry> entries, FileEntry entry) {
    if (entries.length > 1) return Icons.file_copy;
    return entry.isDir ? Icons.folder : Icons.insert_drive_file;
  }

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onChanged);
    _pathFocusNode.addListener(_onPathFocusChanged);
  }

  void _onPathFocusChanged() {
    if (!_pathFocusNode.hasFocus && _editingPath) {
      setState(() => _editingPath = false);
    }
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChanged);
    _pathFocusNode.removeListener(_onPathFocusChanged);
    _pathFocusNode.dispose();
    _pathController.dispose();
    disposeMarquee();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final reg = AppShortcutRegistry.instance;

    if (reg.matches(AppShortcut.fileSelectAll, event)) {
      ctrl.selectAll();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.fileCopy, event)) {
      if (ctrl.selected.isNotEmpty) widget.onCopy?.call();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.filePaste, event)) {
      widget.onPaste?.call();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.fileDelete, event)) {
      if (ctrl.selected.isEmpty) return KeyEventResult.ignored;
      _confirmDelete(context, ctrl.selectedEntries);
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.fileRename, event)) {
      if (ctrl.selected.length == 1) {
        _showRenameDialog(context, ctrl.selectedEntries.first);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (reg.matches(AppShortcut.fileRefresh, event)) {
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) {
          ctrl.goBack();
        } else if (event.buttons & kForwardMouseButton != 0) {
          ctrl.goForward();
        }
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _osDragging = true),
          onDragExited: (_) => setState(() => _osDragging = false),
          onDragDone: (details) {
            setState(() => _osDragging = false);
            _focusNode.requestFocus();
            final paths = details.files.map((f) => f.path).toList();
            if (paths.isNotEmpty) {
              widget.onOsDropReceived?.call(paths);
            }
          },
          child: Container(
            decoration: _osDragging
                ? BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: AppTheme.radiusSm,
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  )
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = _visibleColumns(constraints.maxWidth);
                return Column(
                  children: [
                    _buildHeader(theme),
                    _buildColumnHeaders(theme, cols, constraints.maxWidth),
                    Expanded(
                      child: _buildDropTarget(_buildFileList(theme, cols)),
                    ),
                    _buildFooter(theme),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

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
              const SizedBox(width: 8),
              Expanded(child: _buildBreadcrumb()),
              if (showNav) ...[
                const SizedBox(width: 4),
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
              setState(() => _editingPath = true);
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
          setState(() => _editingPath = false);
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
              onDrag: (dx) => setState(() {
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
              onDrag: (dx) => setState(() {
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
              onDrag: (dx) => setState(() {
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
              onDrag: (dx) => setState(() {
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

  // ── MarqueeMixin implementation ──

  static const _rowHeight = 26.0;
  Set<String>? _preMarqueeSelection;

  @override
  double get marqueeRowHeight => _rowHeight;

  @override
  int get marqueeItemCount => ctrl.entries.length;

  @override
  bool isMarqueeItemSelected(int index) =>
      ctrl.selected.contains(ctrl.entries[index].path);

  @override
  void applyMarqueeSelection(
    int firstIndex,
    int lastIndex, {
    required bool ctrlHeld,
  }) {
    final newSelection = <String>{};
    if (_preMarqueeSelection != null) {
      newSelection.addAll(_preMarqueeSelection!);
    }
    for (var i = firstIndex; i <= lastIndex; i++) {
      newSelection.add(ctrl.entries[i].path);
    }
    ctrl.selectPaths(newSelection);
  }

  @override
  void onMarqueePointerDown() {
    _focusNode.requestFocus();
    widget.onPaneActivated?.call();
    _preMarqueeSelection = isCtrlHeld ? Set.from(ctrl.selected) : null;
  }

  @override
  void onMarqueeActivated() {
    if (!isCtrlHeld && _preMarqueeSelection == null) {
      ctrl.clearSelection();
    }
  }

  @override
  void onMarqueeDeactivated() {
    _preMarqueeSelection = null;
  }

  @override
  void onMarqueeClickEmpty(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= ctrl.entries.length) {
      ctrl.clearSelection();
    }
    _preMarqueeSelection = null;
  }

  // ── File list ──

  Widget _buildFileList(
    ThemeData theme,
    ({bool size, bool modified, bool mode, bool owner}) cols,
  ) {
    if (ctrl.loading) {
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
          const SizedBox(height: 12),
          Text(
            S.of(context).connectionError,
            style: AppFonts.inter(fontSize: AppFonts.lg, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 4),
          Text(
            localizeError(S.of(context), ctrl.error!),
            style: AppFonts.inter(
              fontSize: AppFonts.sm,
              color: AppTheme.fgFaint,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
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
              itemExtent: _rowHeight,
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
    final isSelected = ctrl.selected.contains(entry.path);

    // Directories with the size column enabled subscribe to the folder-size
    // revision directly, so a completed background dir-size probe refreshes
    // just this row's trailing text instead of going through the pane's
    // main ChangeNotifier (which would rebuild the entire 700+ line tree).
    if (entry.isDir && widget.showFolderSizes) {
      return ValueListenableBuilder<int>(
        valueListenable: ctrl.folderSizeRevision,
        builder: (context, _, child) {
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
    }

    return _buildFileRowWrapper(context, theme, entry, isSelected, cols, null);
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
            Icon(_dragIcon(dragEntries, entry), size: 14),
            const SizedBox(width: 4),
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
    final selCount = ctrl.selected.length;
    final style = AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint);

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
          if (selCount > 0) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '($selCount selected)',
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

  // ── Context menus ──

  void _showBackgroundContextMenu(BuildContext context, Offset position) {
    ctrl.clearSelection();
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        StandardMenuAction.newFolder.item(
          context,
          onTap: () => _showNewFolderDialog(context),
        ),
        StandardMenuAction.refresh.item(
          context,
          shortcut: AppShortcut.fileRefresh,
          onTap: () => ctrl.refresh(),
        ),
      ],
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    FileEntry entry,
  ) {
    if (!ctrl.selected.contains(entry.path)) {
      ctrl.selectSingle(entry.path);
    }

    final selectedEntries = ctrl.selectedEntries;
    final hasMultiple = selectedEntries.length > 1;

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (!hasMultiple && entry.isDir)
          StandardMenuAction.open.item(
            context,
            onTap: () => ctrl.navigateTo(entry.path),
          ),
        StandardMenuAction.transfer.item(
          context,
          labelOverride: hasMultiple
              ? S.of(context).transferNItems(selectedEntries.length)
              : null,
          onTap: () {
            if (hasMultiple) {
              widget.onTransferMultiple?.call(selectedEntries);
            } else {
              widget.onTransfer?.call(entry);
            }
          },
        ),
        const ContextMenuItem.divider(),
        StandardMenuAction.newFolder.item(
          context,
          onTap: () => _showNewFolderDialog(context),
        ),
        if (!hasMultiple)
          StandardMenuAction.rename.item(
            context,
            shortcut: AppShortcut.fileRename,
            onTap: () => _showRenameDialog(context, entry),
          ),
        StandardMenuAction.delete.item(
          context,
          labelOverride: hasMultiple
              ? S.of(context).deleteNItems(selectedEntries.length)
              : null,
          onTap: () => _confirmDelete(context, selectedEntries),
        ),
      ],
    );
  }

  // ── Dialogs (delegated to FilePaneDialogs) ──

  Future<void> _showNewFolderDialog(BuildContext context) =>
      FilePaneDialogs.showNewFolder(context, ctrl);

  Future<void> _showRenameDialog(BuildContext context, FileEntry entry) =>
      FilePaneDialogs.showRename(context, ctrl, entry);

  Future<void> _confirmDelete(BuildContext context, List<FileEntry> entries) =>
      FilePaneDialogs.confirmDelete(context, ctrl, entries);
}
