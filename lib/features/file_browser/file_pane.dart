import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../utils/format.dart';
import '../../widgets/toast.dart';
import 'file_browser_controller.dart';

/// Drag data with source pane identity to prevent same-pane drops.
class PaneDragData {
  final String sourcePaneId;
  final List<FileEntry> entries;
  const PaneDragData({required this.sourcePaneId, required this.entries});
}

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

  const FilePane({
    super.key,
    required this.controller,
    this.paneId = '',
    this.onTransfer,
    this.onTransferMultiple,
    this.onDropReceived,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final _pathController = TextEditingController();
  final _focusNode = FocusNode();
  bool _editingPath = false;

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

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Column(
      children: [
        // Header: label + navigation
        _buildHeader(theme),
        // Path bar
        _buildPathBar(theme),
        const Divider(height: 1),
        // File list (with drop target)
        Expanded(child: _buildDropTarget(_buildFileList(theme))),
          // Footer: selection info
          _buildFooter(theme),
        ],
      ),
    );
  }

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

  // --- Marquee & drag state ---
  Offset? _marqueeAnchor; // raw pointer-down position (before threshold)
  Offset? _marqueeStart; // set after movement exceeds threshold
  Offset? _marqueeCurrent;
  bool _marqueeActive = false;
  bool _dragActive = false; // true while Draggable is in flight
  final _scrollController = ScrollController();
  Set<String>? _preMarqueeSelection;

  static const _rowHeight = 28.0;
  static const _marqueeThreshold = 5.0; // px before marquee activates

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



        // If on a selected row, let Draggable handle a potential drag.
        if (onSelected) return;

        // Record anchor for potential marquee (not yet active).
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
          // Threshold exceeded — activate marquee.
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

                final row = _FileRow(
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

                // Only selected files can be dragged (for transfer).
                if (!isSelected) return row;

                final dragEntries = ctrl.selectedEntries.length > 1
                    ? ctrl.selectedEntries
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
            // Marquee rectangle overlay
            if (_marqueeActive &&
                _marqueeStart != null &&
                _marqueeCurrent != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarqueePainter(
                      start: _marqueeStart!,
                      end: _marqueeCurrent!,
                      color: theme.colorScheme.primary,
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

  Widget _buildFooter(ThemeData theme) {
    final count = ctrl.entries.length;
    final selCount = ctrl.selected.length;
    final totalSize = ctrl.entries
        .where((e) => !e.isDir)
        .fold<int>(0, (sum, e) => sum + e.size);

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
            '$count items, ${formatSize(totalSize)}',
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

  Widget _buildDropTarget(Widget child) {
    return DragTarget<PaneDragData>(
      onWillAcceptWithDetails: (details) {
        if (widget.onDropReceived == null) return false;
        // Reject drops from the same pane.
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

  void _showBackgroundContextMenu(BuildContext context, Offset position) {
    ctrl.clearSelection();
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        PopupMenuItem(
          onTap: () => _showNewFolderDialog(context),
          child: const _MenuRow(icon: Icons.create_new_folder, text: 'New Folder'),
        ),
        PopupMenuItem(
          onTap: () => ctrl.refresh(),
          child: const _MenuRow(icon: Icons.refresh, text: 'Refresh'),
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
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: <PopupMenuEntry>[
        if (!hasMultiple && entry.isDir)
          PopupMenuItem(
            onTap: () => ctrl.navigateTo(entry.path),
            child: const _MenuRow(icon: Icons.folder_open, text: 'Open'),
          ),
        PopupMenuItem(
          onTap: () {
            if (hasMultiple) {
              widget.onTransferMultiple?.call(selectedEntries);
            } else {
              widget.onTransfer?.call(entry);
            }
          },
          child: _MenuRow(
            icon: Icons.swap_horiz,
            text: hasMultiple ? 'Transfer ${selectedEntries.length} items' : 'Transfer',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => _showNewFolderDialog(context),
          child: const _MenuRow(icon: Icons.create_new_folder, text: 'New Folder'),
        ),
        if (!hasMultiple)
          PopupMenuItem(
            onTap: () => _showRenameDialog(context, entry),
            child: const _MenuRow(icon: Icons.edit, text: 'Rename'),
          ),
        PopupMenuItem(
          onTap: () => _confirmDelete(context, selectedEntries),
          child: _MenuRow(
            icon: Icons.delete,
            text: hasMultiple ? 'Delete ${selectedEntries.length} items' : 'Delete',
          ),
        ),
      ],
    );
  }

  Future<void> _showNewFolderDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final path = '${ctrl.currentPath}/$result';
      try {
        await ctrl.fs.mkdir(path);
        await ctrl.refresh();
      } catch (e) {
        if (context.mounted) {
          Toast.show(context, message: 'Failed to create folder: $e', level: ToastLevel.error);
        }
      }
    }
  }

  Future<void> _showRenameDialog(BuildContext context, FileEntry entry) async {
    final nameCtrl = TextEditingController(text: entry.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != entry.name) {
      final newPath = '${ctrl.currentPath}/$result';
      try {
        await ctrl.fs.rename(entry.path, newPath);
        await ctrl.refresh();
      } catch (e) {
        if (context.mounted) {
          Toast.show(context, message: 'Failed to rename: $e', level: ToastLevel.error);
        }
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, List<FileEntry> entries) async {
    final names = entries.length == 1
        ? '"${entries.first.name}"'
        : '${entries.length} items';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete $names?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final entry in entries) {
        try {
          if (entry.isDir) {
            await ctrl.fs.removeDir(entry.path);
          } else {
            await ctrl.fs.remove(entry.path);
          }
        } catch (e) {
          if (context.mounted) {
            Toast.show(context, message: 'Failed to delete ${entry.name}: $e', level: ToastLevel.error);
          }
        }
      }
      await ctrl.refresh();
    }
  }
}

/// A single file row in the list.
class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset position) onContextMenu;

  const _FileRow({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      child: InkWell(
        onTap: () {
          if (HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlRight)) {
            onCtrlTap();
          } else {
            onTap();
          }
        },
        onDoubleTap: onDoubleTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          child: Row(
            children: [
              Icon(
                entry.isDir ? Icons.folder : Icons.insert_drive_file,
                size: 16,
                color: entry.isDir
                    ? Colors.amber[700]
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.isDir ? '' : formatSize(entry.size),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.modeString,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MenuRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}

/// Paints a semi-transparent marquee selection rectangle.
class _MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _MarqueePainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // Fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter oldDelegate) {
    return start != oldDelegate.start || end != oldDelegate.end;
  }
}
