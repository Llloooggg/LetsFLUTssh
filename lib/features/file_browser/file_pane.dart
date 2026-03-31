import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/cross_marquee_controller.dart';
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

  const FilePane({
    super.key,
    required this.controller,
    this.paneId = '',
    this.onTransfer,
    this.onTransferMultiple,
    this.onDropReceived,
    this.onOsDropReceived,
    this.onPaneActivated,
    this.crossMarquee,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final _focusNode = FocusNode();
  final _fileListKey = GlobalKey();
  final _pathController = TextEditingController();
  bool _editingPath = false;
  bool _osDragging = false;

  // Resizable column widths
  double _sizeColWidth = 64;
  double _modifiedColWidth = 80;
  double _modeColWidth = 80;
  double _ownerColWidth = 60;

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
    _pathController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCrossMarquee() {
    final cm = widget.crossMarquee!;
    if (!cm.active) {
      // Cross-marquee ended
      if (_marqueeActive) {
        setState(() {
          _marqueeAnchor = null;
          _marqueeStart = null;
          _marqueeCurrent = null;
          _preMarqueeSelection = null;
          _marqueeActive = false;
        });
      }
      return;
    }

    // Translate global position to our file list local coordinates
    final box = _fileListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final local = box.globalToLocal(cm.globalPosition!);

    if (cm.phase == CrossMarqueePhase.start) {
      // Start cross-marquee: anchor at the entry point
      _marqueeActive = true;
      _marqueeAnchor = local;
      _preMarqueeSelection = _isCtrlHeld ? Set.from(ctrl.selected) : null;
      if (!_isCtrlHeld) ctrl.clearSelection();
    }

    setState(() {
      _marqueeStart = _marqueeAnchor;
      _marqueeCurrent = local;
    });
    _updateMarqueeSelection();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.delete) return KeyEventResult.ignored;
    if (ctrl.selected.isEmpty) return KeyEventResult.ignored;
    _confirmDelete(context, ctrl.selectedEntries);
    return KeyEventResult.handled;
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
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  )
                : null,
            child: Column(
              children: [
                _buildHeader(theme),
                _buildColumnHeaders(theme),
                Expanded(child: _buildDropTarget(_buildFileList(theme))),
                _buildFooter(theme),
              ],
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Text(
            ctrl.label.toUpperCase(),
            style: AppFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildBreadcrumb()),
          const SizedBox(width: 4),
          _navButton(Icons.arrow_back, ctrl.canGoBack ? ctrl.goBack : null, 'Back'),
          _navButton(Icons.arrow_forward, ctrl.canGoForward ? ctrl.goForward : null, 'Forward'),
          _navButton(Icons.arrow_upward, ctrl.navigateUp, 'Up'),
          _navButton(Icons.refresh, ctrl.refresh, 'Refresh'),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    if (_editingPath) {
      return SizedBox(
        height: 22,
        child: TextField(
          controller: _pathController,
          autofocus: true,
          style: AppFonts.mono(fontSize: 10, color: AppTheme.fg),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppTheme.bg3,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppTheme.borderLight),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: AppTheme.accent),
            ),
            hintText: ctrl.currentPath,
            hintStyle: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint),
          ),
          onSubmitted: (val) {
            setState(() => _editingPath = false);
            if (val.trim().isNotEmpty) {
              ctrl.navigateTo(val.trim());
            }
          },
          onTapOutside: (_) {
            setState(() => _editingPath = false);
          },
        ),
      );
    }

    final currentPath = ctrl.currentPath;
    // Detect Windows paths (e.g. C:\Users or C:/)
    final isWindows = currentPath.length >= 2 &&
        currentPath[1] == ':' &&
        RegExp(r'^[A-Za-z]$').hasMatch(currentPath[0]);
    final separator = isWindows ? RegExp(r'[/\\]') : RegExp(r'/');
    final parts = currentPath.split(separator)..removeWhere((p) => p.isEmpty);
    final rootPath = isWindows && parts.isNotEmpty ? '${parts[0]}\\' : '/';
    final rootLabel = isWindows && parts.isNotEmpty ? parts[0] : null;
    final navParts = isWindows ? parts.skip(1).toList() : parts;

    return Row(
      children: [
        InkWell(
          onTap: () => ctrl.navigateTo(rootPath),
          child: rootLabel != null
              ? Text(rootLabel, style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint))
              : const Icon(Icons.home, size: 10, color: AppTheme.fgFaint),
        ),
        for (var i = 0; i < navParts.length; i++) ...[
          Text(isWindows ? ' \\ ' : ' / ', style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint)),
          InkWell(
            onTap: () {
              if (isWindows) {
                ctrl.navigateTo([parts[0], ...navParts.sublist(0, i + 1)].join('\\'));
              } else {
                ctrl.navigateTo('/${navParts.sublist(0, i + 1).join('/')}');
              }
            },
            child: Text(
              navParts[i],
              style: AppFonts.mono(
                fontSize: 10,
                color: i == navParts.length - 1 ? AppTheme.fg : AppTheme.fgDim,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            _pathController.text = ctrl.currentPath;
            setState(() => _editingPath = true);
          },
          child: const Icon(Icons.edit, size: 9, color: AppTheme.fgFaint),
        ),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return SizedBox(
      width: 20,
      height: 20,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 11, color: AppTheme.fgFaint),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Column headers ──

  Widget _buildColumnHeaders(ThemeData theme) {
    final headerStyle = AppFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    Widget headerCell(String label, SortColumn column, {double? width, TextAlign? textAlign}) {
      final isActive = ctrl.sortColumn == column;
      return InkWell(
        onTap: () => ctrl.setSort(column),
        child: SizedBox(
          width: width,
          child: Row(
            mainAxisSize: width != null ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: textAlign == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: isActive
                      ? headerStyle.copyWith(color: AppTheme.accent)
                      : headerStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Icon(
                  ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10,
                  color: AppTheme.accent,
                ),
            ],
          ),
        ),
      );
    }

    final hasOwner = ctrl.entries.any((e) => e.owner.isNotEmpty);

    Widget colDivider(void Function(double) onDrag) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragUpdate: (d) => setState(() => onDrag(d.delta.dx)),
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
      color: AppTheme.bg3,
      child: Row(
        children: [
          const SizedBox(width: 20), // icon space
          Expanded(child: headerCell('Name', SortColumn.name)),
          colDivider((dx) => _sizeColWidth = (_sizeColWidth + dx).clamp(40, 120)),
          headerCell('Size', SortColumn.size, width: _sizeColWidth),
          colDivider((dx) => _modifiedColWidth = (_modifiedColWidth + dx).clamp(50, 150)),
          headerCell('Modified', SortColumn.modified, width: _modifiedColWidth),
          colDivider((dx) => _modeColWidth = (_modeColWidth + dx).clamp(50, 120)),
          headerCell('Mode', SortColumn.mode, width: _modeColWidth),
          if (hasOwner) ...[
            colDivider((dx) => _ownerColWidth = (_ownerColWidth + dx).clamp(40, 100)),
            headerCell('Owner', SortColumn.owner, width: _ownerColWidth),
          ],
        ],
      ),
    );
  }

  // ── Marquee & drag state ──

  Offset? _marqueeAnchor;
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeActive = false;
  bool _dragActive = false;
  final _scrollController = ScrollController();
  Set<String>? _preMarqueeSelection;
  DateTime _lastMarqueeUpdate = DateTime(0);

  static const _rowHeight = 26.0;
  static const _marqueeThreshold = 5.0;

  bool get _isCtrlHeld =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlRight);

  int _rowIndexAt(double localY) {
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    return ((localY + scrollOffset) / _rowHeight).floor();
  }

  // ── File list ──

  Widget _buildFileList(ThemeData theme) {
    if (ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.error != null) {
      return _buildErrorState(theme);
    }
    if (ctrl.entries.isEmpty) {
      return _buildEmptyState();
    }
    return _buildFileListContent(theme);
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppTheme.bg3),
            child: const Icon(Icons.error_outline, size: 22, color: AppTheme.red),
          ),
          const SizedBox(height: 12),
          Text(
            'Connection error',
            style: AppFonts.inter(fontSize: 13, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 4),
          Text(
            ctrl.error!,
            style: AppFonts.inter(fontSize: 11, color: AppTheme.fgFaint),
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
                  fontSize: 11,
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
          style: AppFonts.inter(fontSize: 11, color: AppTheme.fgFaint),
        ),
      ),
    );
  }

  Widget _buildFileListContent(ThemeData theme) {
    return Listener(
      onPointerDown: _onListPointerDown,
      onPointerMove: _onListPointerMove,
      onPointerUp: _onListPointerUp,
      child: GestureDetector(
        onSecondaryTapUp: (d) => _showBackgroundContextMenu(context, d.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          key: _fileListKey,
          children: [
            ListView.builder(
              controller: _scrollController,
              itemCount: ctrl.entries.length,
              itemExtent: _rowHeight,
              itemBuilder: (context, index) =>
                  _buildFileListItem(context, index, theme),
            ),
            if (_marqueeActive &&
                _marqueeStart != null &&
                _marqueeCurrent != null)
              _buildMarqueeOverlay(theme),
          ],
        ),
      ),
    );
  }

  void _onListPointerDown(PointerDownEvent e) {
    _focusNode.requestFocus();
    widget.onPaneActivated?.call();
    if (e.buttons != kPrimaryButton) return;

    final rowIdx = _rowIndexAt(e.localPosition.dy);
    final onRow = rowIdx >= 0 && rowIdx < ctrl.entries.length;
    final onSelected = onRow && ctrl.selected.contains(ctrl.entries[rowIdx].path);

    if (onSelected) return;

    setState(() {
      _marqueeAnchor = e.localPosition;
      _preMarqueeSelection = _isCtrlHeld ? Set.from(ctrl.selected) : null;
    });
  }

  void _onListPointerMove(PointerMoveEvent e) {
    if (_dragActive || _marqueeAnchor == null) return;

    final distance = (e.localPosition - _marqueeAnchor!).distance;

    if (!_marqueeActive) {
      if (distance < _marqueeThreshold) return;
      _marqueeActive = true;
      if (!_isCtrlHeld && _preMarqueeSelection == null) {
        ctrl.clearSelection();
      }
    }

    setState(() {
      _marqueeStart = _marqueeAnchor;
      _marqueeCurrent = e.localPosition;
    });
    _updateMarqueeSelection();
  }

  void _onListPointerUp(PointerUpEvent _) {
    if (_marqueeActive) {
      setState(() {
        _marqueeAnchor = null;
        _marqueeStart = null;
        _marqueeCurrent = null;
        _preMarqueeSelection = null;
        _marqueeActive = false;
      });
    } else {
      // Click (no drag) on empty space below files — clear selection
      if (_marqueeAnchor != null && !_isCtrlHeld) {
        final rowIdx = _rowIndexAt(_marqueeAnchor!.dy);
        if (rowIdx < 0 || rowIdx >= ctrl.entries.length) {
          ctrl.clearSelection();
        }
      }
      _marqueeAnchor = null;
      _preMarqueeSelection = null;
    }
  }

  Widget _buildFileListItem(BuildContext context, int index, ThemeData theme) {
    final entry = ctrl.entries[index];
    final isSelected = ctrl.selected.contains(entry.path);

    final row = FileRow(
      entry: entry,
      isSelected: isSelected,
      sizeWidth: _sizeColWidth,
      modifiedWidth: _modifiedColWidth,
      modeWidth: _modeColWidth,
      ownerWidth: _ownerColWidth,
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
      onDragStarted: () => _dragActive = true,
      onDragEnd: (_) => _dragActive = false,
      onDraggableCanceled: (_, _) => _dragActive = false,
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
            Icon(_dragIcon(dragEntries, entry), size: 14),
            const SizedBox(width: 4),
            Text(
              dragEntries.length > 1
                  ? '${dragEntries.length} items'
                  : entry.name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarqueeOverlay(ThemeData theme) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            painter: MarqueePainter(
              start: _marqueeStart!,
              end: _marqueeCurrent!,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  void _updateMarqueeSelection() {
    if (_marqueeStart == null || _marqueeCurrent == null) return;

    // Throttle selection updates to every 50ms to reduce Set allocations
    final now = DateTime.now();
    if (now.difference(_lastMarqueeUpdate).inMilliseconds < 50) return;
    _lastMarqueeUpdate = now;

    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final startY = _marqueeStart!.dy + scrollOffset;
    final endY = _marqueeCurrent!.dy + scrollOffset;
    final minY = startY < endY ? startY : endY;
    final maxY = startY > endY ? startY : endY;

    final firstIndex =
        (minY / _rowHeight).floor().clamp(0, ctrl.entries.length - 1);
    final lastIndex =
        (maxY / _rowHeight).floor().clamp(0, ctrl.entries.length - 1);

    final newSelection = <String>{};
    if (_preMarqueeSelection != null) {
      newSelection.addAll(_preMarqueeSelection!);
    }
    for (var i = firstIndex; i <= lastIndex; i++) {
      newSelection.add(ctrl.entries[i].path);
    }
    ctrl.selectPaths(newSelection);
  }

  // ── Footer ──

  Widget _buildFooter(ThemeData theme) {
    final count = ctrl.entries.length;
    final selCount = ctrl.selected.length;
    final style = AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint);

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bg0,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Text('$count items, ${formatSize(ctrl.totalFileSize)}', style: style),
          if (selCount > 0) ...[
            const SizedBox(width: 8),
            Text('($selCount selected)', style: style),
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
            shortcut: 'F2',
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
