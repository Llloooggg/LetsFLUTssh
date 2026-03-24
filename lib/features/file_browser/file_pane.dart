import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../utils/format.dart';
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

  const FilePane({
    super.key,
    required this.controller,
    this.paneId = '',
    this.onTransfer,
    this.onTransferMultiple,
    this.onDropReceived,
    this.onOsDropReceived,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final _pathController = TextEditingController();
  final _focusNode = FocusNode();
  bool _editingPath = false;
  bool _osDragging = false;

  FilePaneController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onChanged);
    _pathController.text = ctrl.currentPath;
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChanged);
    _pathController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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
      setState(() {
        if (!_editingPath) {
          _pathController.text = ctrl.currentPath;
        }
      });
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
                _buildPathBar(theme),
                const Divider(height: 1),
                _buildColumnHeaders(theme),
                const Divider(height: 1),
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
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Text(
            ctrl.label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const Spacer(),
          _iconButton(Icons.arrow_back, ctrl.canGoBack ? ctrl.goBack : null, 'Back'),
          _iconButton(Icons.arrow_forward, ctrl.canGoForward ? ctrl.goForward : null, 'Forward'),
          _iconButton(Icons.arrow_upward, ctrl.navigateUp, 'Up'),
          _iconButton(Icons.refresh, ctrl.refresh, 'Refresh'),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Path bar ──

  Widget _buildPathBar(ThemeData theme) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _editingPath
                ? TextField(
                    controller: _pathController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (val) {
                      _editingPath = false;
                      ctrl.navigateTo(val);
                    },
                    onTapOutside: (_) {
                      setState(() {
                        _editingPath = false;
                        _pathController.text = ctrl.currentPath;
                      });
                    },
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editingPath = true),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ctrl.currentPath,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Column headers ──

  Widget _buildColumnHeaders(ThemeData theme) {
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    const headerStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

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
                  style: headerStyle.copyWith(
                    color: isActive ? theme.colorScheme.primary : dimColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Icon(
                  ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      );
    }

    final hasOwner = ctrl.entries.any((e) => e.owner.isNotEmpty);

    final divider = Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: theme.dividerColor,
    );

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          const SizedBox(width: 22), // icon space
          Expanded(flex: 3, child: headerCell('Name', SortColumn.name)),
          divider,
          headerCell('Size', SortColumn.size, width: 70, textAlign: TextAlign.right),
          divider,
          headerCell('Modified', SortColumn.modified, width: 120),
          divider,
          headerCell('Mode', SortColumn.mode, width: 90),
          if (hasOwner) ...[
            divider,
            headerCell('Owner', SortColumn.owner, width: 60),
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

  static const _rowHeight = 28.0;
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(ctrl.error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: ctrl.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (ctrl.entries.isEmpty) {
      return GestureDetector(
        onSecondaryTapUp: (d) => _showBackgroundContextMenu(context, d.globalPosition),
        child: const Center(child: Text('Empty directory', style: TextStyle(fontSize: 13))),
      );
    }

    return Listener(
      onPointerDown: (e) {
        _focusNode.requestFocus();
        if (e.buttons != kPrimaryButton) return;

        final rowIdx = _rowIndexAt(e.localPosition.dy);
        final onRow = rowIdx >= 0 && rowIdx < ctrl.entries.length;
        final onSelected = onRow && ctrl.selected.contains(ctrl.entries[rowIdx].path);

        if (onSelected) return;

        setState(() {
          _marqueeAnchor = e.localPosition;
          _preMarqueeSelection = _isCtrlHeld ? Set.from(ctrl.selected) : null;
        });
      },
      onPointerMove: (e) {
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
      },
      onPointerUp: (_) {
        if (_marqueeActive) {
          setState(() {
            _marqueeAnchor = null;
            _marqueeStart = null;
            _marqueeCurrent = null;
            _preMarqueeSelection = null;
            _marqueeActive = false;
          });
        } else {
          _marqueeAnchor = null;
          _preMarqueeSelection = null;
        }
      },
      child: GestureDetector(
        onSecondaryTapUp: (d) => _showBackgroundContextMenu(context, d.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              itemCount: ctrl.entries.length,
              itemExtent: _rowHeight,
              itemBuilder: (context, index) {
                final entry = ctrl.entries[index];
                final isSelected = ctrl.selected.contains(entry.path);

                final row = FileRow(
                  entry: entry,
                  isSelected: isSelected,
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
                final dragEntries = selected.length > 1
                    ? selected
                    : [entry];

                return Draggable<PaneDragData>(
                  data: PaneDragData(
                    sourcePaneId: widget.paneId,
                    entries: dragEntries,
                  ),
                  onDragStarted: () => _dragActive = true,
                  onDragEnd: (_) => _dragActive = false,
                  onDraggableCanceled: (_, __) => _dragActive = false,
                  feedback: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            dragEntries.length > 1
                                ? Icons.file_copy
                                : (entry.isDir
                                    ? Icons.folder
                                    : Icons.insert_drive_file),
                            size: 14,
                          ),
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
                  ),
                  child: row,
                );
              },
            ),
            if (_marqueeActive &&
                _marqueeStart != null &&
                _marqueeCurrent != null)
              Positioned.fill(
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
              ),
          ],
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

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            '$count items, ${formatSize(ctrl.totalFileSize)}',
            style: const TextStyle(fontSize: 11),
          ),
          if (selCount > 0) ...[
            const SizedBox(width: 8),
            Text(
              '($selCount selected)',
              style: const TextStyle(fontSize: 11),
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
    showMenu(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        PopupMenuItem(
          onTap: () => _showNewFolderDialog(context),
          child: const MenuRow(icon: Icons.create_new_folder, text: 'New Folder'),
        ),
        PopupMenuItem(
          onTap: () => ctrl.refresh(),
          child: const MenuRow(icon: Icons.refresh, text: 'Refresh'),
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

    showMenu(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: <PopupMenuEntry>[
        if (!hasMultiple && entry.isDir)
          PopupMenuItem(
            onTap: () => ctrl.navigateTo(entry.path),
            child: const MenuRow(icon: Icons.folder_open, text: 'Open'),
          ),
        PopupMenuItem(
          onTap: () {
            if (hasMultiple) {
              widget.onTransferMultiple?.call(selectedEntries);
            } else {
              widget.onTransfer?.call(entry);
            }
          },
          child: MenuRow(
            icon: Icons.swap_horiz,
            text: hasMultiple ? 'Transfer ${selectedEntries.length} items' : 'Transfer',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => _showNewFolderDialog(context),
          child: const MenuRow(icon: Icons.create_new_folder, text: 'New Folder'),
        ),
        if (!hasMultiple)
          PopupMenuItem(
            onTap: () => _showRenameDialog(context, entry),
            child: const MenuRow(icon: Icons.edit, text: 'Rename'),
          ),
        PopupMenuItem(
          onTap: () => _confirmDelete(context, selectedEntries),
          child: MenuRow(
            icon: Icons.delete,
            text: hasMultiple ? 'Delete ${selectedEntries.length} items' : 'Delete',
          ),
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
