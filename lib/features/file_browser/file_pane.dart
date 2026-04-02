import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/clipped_row.dart';
import '../../utils/format.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../widgets/marquee_mixin.dart';
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

  /// Cross-widget marquee controller — receives events when a marquee drag
  /// starts in the session panel and crosses into this file pane.
  final CrossMarqueeController? crossMarquee;

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
    this.crossMarquee,
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

  // Resizable column widths (compact defaults so Name gets more space)
  double _sizeColWidth = 55;
  double _modifiedColWidth = 105;
  double _modeColWidth = 65;
  double _ownerColWidth = 50;

  /// Determine which data columns fit within [width], hiding from right to left.
  ({bool size, bool modified, bool mode, bool owner}) _visibleColumns(double width) {
    const base = 36.0; // icon(20) + padding(16)
    final hasOwner = ctrl.entries.any((e) => e.owner.isNotEmpty);
    final s = 10 + _sizeColWidth;
    final m = 10 + _modifiedColWidth;
    final d = 10 + _modeColWidth;
    final o = hasOwner ? 10 + _ownerColWidth : 0.0;
    final avail = width - base;
    if (avail >= s + m + d + o) return (size: true, modified: true, mode: true, owner: hasOwner);
    if (avail >= s + m + d) return (size: true, modified: true, mode: true, owner: false);
    if (avail >= s + m) return (size: true, modified: true, mode: false, owner: false);
    if (avail >= s) return (size: true, modified: false, mode: false, owner: false);
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
    widget.crossMarquee?.addListener(_onCrossMarquee);
    _pathFocusNode.addListener(_onPathFocusChanged);
  }

  void _onPathFocusChanged() {
    if (!_pathFocusNode.hasFocus && _editingPath) {
      setState(() => _editingPath = false);
    }
  }

  @override
  void didUpdateWidget(covariant FilePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.crossMarquee != widget.crossMarquee) {
      oldWidget.crossMarquee?.removeListener(_onCrossMarquee);
      widget.crossMarquee?.addListener(_onCrossMarquee);
    }
  }

  @override
  void dispose() {
    widget.crossMarquee?.removeListener(_onCrossMarquee);
    ctrl.removeListener(_onChanged);
    _pathFocusNode.removeListener(_onPathFocusChanged);
    _pathFocusNode.dispose();
    _pathController.dispose();
    disposeMarquee();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCrossMarquee() {
    final cm = widget.crossMarquee!;
    if (!cm.active) {
      if (marqueeActive) {
        setState(() {
          marqueeAnchor = null;
          marqueeStart = null;
          marqueeCurrent = null;
          _preMarqueeSelection = null;
          marqueeActive = false;
        });
      }
      return;
    }

    final box = _fileListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final local = box.globalToLocal(cm.globalPosition!);

    if (cm.phase == CrossMarqueePhase.start) {
      marqueeActive = true;
      marqueeAnchor = local;
      _preMarqueeSelection = isCtrlHeld ? Set.from(ctrl.selected) : null;
      if (!isCtrlHeld) ctrl.clearSelection();
    }

    setState(() {
      marqueeStart = marqueeAnchor;
      marqueeCurrent = local;
    });
    _crossMarqueeUpdateSelection();
  }

  void _crossMarqueeUpdateSelection() {
    if (marqueeStart == null || marqueeCurrent == null) return;
    final scroll = marqueeScrollController.hasClients
        ? marqueeScrollController.offset
        : 0.0;
    final startY = marqueeStart!.dy + scroll;
    final endY = marqueeCurrent!.dy + scroll;
    final minY = startY < endY ? startY : endY;
    final maxY = startY > endY ? startY : endY;
    final maxIdx = ctrl.entries.length - 1;
    if (maxIdx < 0) return;
    final firstIndex = (minY / _rowHeight).floor().clamp(0, maxIdx);
    final lastIndex = (maxY / _rowHeight).floor().clamp(0, maxIdx);
    applyMarqueeSelection(firstIndex, lastIndex, ctrlHeld: isCtrlHeld);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.logicalKeysPressed
        .intersection({LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight})
        .isNotEmpty;

    return isCtrl ? _handleCtrlKey(event.logicalKey) : _handlePlainKey(event.logicalKey);
  }

  KeyEventResult _handleCtrlKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyA) {
      ctrl.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (ctrl.selected.isNotEmpty) widget.onCopy?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      widget.onPaste?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePlainKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.delete) {
      if (ctrl.selected.isEmpty) return KeyEventResult.ignored;
      _confirmDelete(context, ctrl.selectedEntries);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      if (ctrl.selected.length == 1) {
        _showRenameDialog(context, ctrl.selectedEntries.first);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.f5) {
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
                    _buildColumnHeaders(theme, cols),
                    Expanded(child: _buildDropTarget(_buildFileList(theme, cols))),
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

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: AppTheme.borderBottom,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showNav = constraints.maxWidth > 160;
          return Row(
            children: [
              Text(
                ctrl.label.toUpperCase(),
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
                _navButton(Icons.arrow_back, ctrl.canGoBack ? ctrl.goBack : null, 'Back'),
                _navButton(Icons.arrow_forward, ctrl.canGoForward ? ctrl.goForward : null, 'Forward'),
                _navButton(Icons.arrow_upward, ctrl.navigateUp, 'Up'),
                _navButton(Icons.refresh, ctrl.refresh, 'Refresh'),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildBreadcrumb() {
    if (_editingPath) return _buildPathEditor();

    final currentPath = ctrl.currentPath;
    final isWindows = _isWindowsPath(currentPath);
    final separator = isWindows ? RegExp(r'[/\\]') : RegExp(r'/');
    final parts = currentPath.split(separator)..removeWhere((p) => p.isEmpty);
    final rootPath = isWindows && parts.isNotEmpty ? '${parts[0]}\\' : '/';
    final rootLabel = isWindows && parts.isNotEmpty ? parts[0] : null;
    final navParts = isWindows ? parts.skip(1).toList() : parts;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: [
        if (rootLabel != null)
          InkWell(
            onTap: () => ctrl.navigateTo(rootPath),
            child: Text(rootLabel, style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint)),
          )
        else
          AppIconButton(
            icon: Icons.home,
            onTap: () => ctrl.navigateTo(rootPath),
            tooltip: 'Root',
            size: 11,
            boxSize: 20,
            color: AppTheme.fgFaint,
          ),
        for (var i = 0; i < navParts.length; i++) ...[
          Text(isWindows ? ' \\ ' : ' / ', style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint)),
          InkWell(
            onTap: () => _navigateToPart(isWindows, parts, navParts, i),
            child: Text(
              navParts[i],
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: i == navParts.length - 1 ? AppTheme.fg : AppTheme.fgDim,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        AppIconButton(
          icon: Icons.edit,
          onTap: () {
            _pathController.text = ctrl.currentPath;
            setState(() => _editingPath = true);
          },
          tooltip: 'Edit Path',
          size: 11,
          boxSize: 20,
          color: AppTheme.fgFaint,
        ),
      ],
      ),
    );
  }

  static bool _isWindowsPath(String path) =>
      path.length >= 2 &&
      path[1] == ':' &&
      RegExp(r'^[A-Za-z]$').hasMatch(path[0]);

  void _navigateToPart(bool isWindows, List<String> parts, List<String> navParts, int i) {
    if (isWindows) {
      ctrl.navigateTo([parts[0], ...navParts.sublist(0, i + 1)].join('\\'));
    } else {
      ctrl.navigateTo('/${navParts.sublist(0, i + 1).join('/')}');
    }
  }

  Widget _buildPathEditor() {
    return SizedBox(
      height: 22,
      child: TextField(
        controller: _pathController,
        focusNode: _pathFocusNode,
        autofocus: true,
        style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fg),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bg3,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.accent),
          ),
          hintText: ctrl.currentPath,
          hintStyle: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
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
      size: 11,
      boxSize: 20,
      color: AppTheme.fgFaint,
    );
  }

  // ── Column headers ──

  Widget _buildColumnHeaders(ThemeData theme, ({bool size, bool modified, bool mode, bool owner}) cols) {
    final headerStyle = AppFonts.inter(
      fontSize: AppFonts.xs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    Widget headerCell(String label, SortColumn column, {double? width, TextAlign? textAlign}) {
      final isActive = ctrl.sortColumn == column;
      String sortSuffix = '';
      if (isActive) {
        sortSuffix = ctrl.sortAscending ? ' ↑' : ' ↓';
      }
      return InkWell(
        onTap: () => ctrl.setSort(column),
        child: SizedBox(
          width: width,
          child: Text(
            '$label$sortSuffix',
            style: isActive
                ? headerStyle.copyWith(color: AppTheme.accent)
                : headerStyle,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
        ),
      );
    }

    Widget colHandle(void Function(double dx) onDrag) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(() => onDrag(d.delta.dx)),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: SizedBox(
            width: 10,
            height: 24,
            child: Center(
              child: Container(
                width: 1,
                height: 14,
                color: AppTheme.fgFaint.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: AppTheme.bg3),
      child: Row(
        children: [
          const SizedBox(width: 20), // icon space
          Expanded(child: headerCell('Name', SortColumn.name)),
          if (cols.size) ...[
            colHandle((dx) => _sizeColWidth = (_sizeColWidth - dx).clamp(40, 200)),
            headerCell('Size', SortColumn.size, width: _sizeColWidth),
          ],
          if (cols.modified) ...[
            colHandle((dx) => _modifiedColWidth = (_modifiedColWidth - dx).clamp(50, 200)),
            headerCell('Modified', SortColumn.modified, width: _modifiedColWidth),
          ],
          if (cols.mode) ...[
            colHandle((dx) => _modeColWidth = (_modeColWidth - dx).clamp(50, 200)),
            headerCell('Mode', SortColumn.mode, width: _modeColWidth),
          ],
          if (cols.owner) ...[
            colHandle((dx) => _ownerColWidth = (_ownerColWidth - dx).clamp(40, 200)),
            headerCell('Owner', SortColumn.owner, width: _ownerColWidth),
          ],
        ],
      ),
    );
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
  void applyMarqueeSelection(int firstIndex, int lastIndex,
      {required bool ctrlHeld}) {
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

  Widget _buildFileList(ThemeData theme, ({bool size, bool modified, bool mode, bool owner}) cols) {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppTheme.bg3),
            child: Icon(Icons.error_outline, size: 22, color: AppTheme.red),
          ),
          const SizedBox(height: 12),
          Text(
            'Connection error',
            style: AppFonts.inter(fontSize: AppFonts.lg, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 4),
          Text(
            ctrl.error!,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: ctrl.refresh,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: AppTheme.bg3,
              alignment: Alignment.center,
              child: Text(
                'Retry',
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
      onSecondaryTapUp: (d) => _showBackgroundContextMenu(context, d.globalPosition),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Text(
          'Empty directory',
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
        ),
      ),
    );
  }

  Widget _buildFileListContent(ThemeData theme, ({bool size, bool modified, bool mode, bool owner}) cols) {
    return Listener(
      onPointerDown: handleMarqueePointerDown,
      onPointerMove: handleMarqueePointerMove,
      onPointerUp: handleMarqueePointerUp,
      child: GestureDetector(
        onSecondaryTapUp: (d) => _showBackgroundContextMenu(context, d.globalPosition),
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
            if (marqueeVisible)
              buildMarqueeOverlay(theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildFileListItem(BuildContext context, int index, ThemeData theme, ({bool size, bool modified, bool mode, bool owner}) cols) {
    final entry = ctrl.entries[index];
    final isSelected = ctrl.selected.contains(entry.path);

    // Trigger async folder size calculation for directories (if enabled)
    String? folderSizeText;
    if (entry.isDir && widget.showFolderSizes) {
      final cachedSize = ctrl.folderSize(entry.path);
      if (cachedSize != null) {
        folderSizeText = formatSize(cachedSize);
      } else {
        ctrl.requestFolderSize(entry.path);
        folderSizeText = '...';
      }
    }

    final row = FileRow(
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
      onContextMenu: (offset) =>
          _showContextMenu(context, offset, entry),
    );

    if (!isSelected) return row;

    final selected = ctrl.selectedEntries;
    final dragEntries = selected.length > 1 ? selected : [entry];

    return Draggable<PaneDragData>(
      data: PaneDragData(
        sourcePaneId: widget.paneId,
        entries: dragEntries,
      ),
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
                  ? '${dragEntries.length} items'
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
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        border: AppTheme.borderTop,
      ),
      child: ClippedRow(
        children: [
          Flexible(
            child: Text('$count items, ${formatSize(ctrl.totalFileSize)}', style: style, overflow: TextOverflow.ellipsis),
          ),
          if (selCount > 0) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text('($selCount selected)', style: style, overflow: TextOverflow.ellipsis),
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
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
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
        ContextMenuItem(
          label: 'New Folder',
          icon: Icons.create_new_folder,
          onTap: () => _showNewFolderDialog(context),
        ),
        ContextMenuItem(
          label: 'Refresh',
          icon: Icons.refresh,
          onTap: () => ctrl.refresh(),
        ),
      ],
    );
  }

  void _showContextMenu(BuildContext context, Offset position, FileEntry entry) {
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
          ContextMenuItem(
            label: 'Open',
            icon: Icons.folder_open,
            onTap: () => ctrl.navigateTo(entry.path),
          ),
        ContextMenuItem(
          label: hasMultiple ? 'Transfer ${selectedEntries.length} items' : 'Transfer',
          icon: Icons.swap_horiz,
          onTap: () {
            if (hasMultiple) {
              widget.onTransferMultiple?.call(selectedEntries);
            } else {
              widget.onTransfer?.call(entry);
            }
          },
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: 'New Folder',
          icon: Icons.create_new_folder,
          onTap: () => _showNewFolderDialog(context),
        ),
        if (!hasMultiple)
          ContextMenuItem(
            label: 'Rename',
            icon: Icons.edit,
            onTap: () => _showRenameDialog(context, entry),
          ),
        ContextMenuItem(
          label: hasMultiple ? 'Delete ${selectedEntries.length} items' : 'Delete',
          icon: Icons.delete,
          color: const Color(0xFFE06C75),
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

