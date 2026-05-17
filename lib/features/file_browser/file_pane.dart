import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sftp/sftp_models.dart';
import '../../widgets/shortcut_registry.dart';
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
// Header / file-list / footer / drop-target builders + context-menu
// + dialog handlers live in part siblings so the State + lifecycle
// scaffolding stays the focus of this file. Same `part of` pattern
// the session_panel split uses; setState calls inside the extension
// methods route through the State's `rebuild(VoidCallback)` wrapper
// because `setState` itself is `@protected` and not callable from
// extension methods.
part 'file_pane_actions.dart';
part 'file_pane_layout.dart';

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
  ///
  /// `mode` / `owner` are gated by [`FileSystem.supportsPosixMode`]
  /// / [`FileSystem.supportsOwner`] before the width check —
  /// WebDAV and S3 don't carry POSIX mode bits or per-resource
  /// owner strings, so reserving columns for those backends just
  /// leaves dead space (the column would render `--------` /
  /// empty on every row). The owner column also keeps the
  /// per-entry probe (`entries.any((e) => e.owner.isNotEmpty)`)
  /// as a belt-and-braces for SFTP servers that omit the owner
  /// attribute on certain entries.
  ({bool size, bool modified, bool mode, bool owner}) _visibleColumns(
    double width,
  ) {
    const base = 36.0; // icon(20) + padding(16)
    final modeAllowed = ctrl.fs.supportsPosixMode;
    final hasOwner =
        ctrl.fs.supportsOwner && ctrl.entries.any((e) => e.owner.isNotEmpty);
    final s = 10 + _sizeColWidth;
    final m = 10 + _modifiedColWidth;
    final d = modeAllowed ? 10 + _modeColWidth : 0.0;
    final o = hasOwner ? 10 + _ownerColWidth : 0.0;
    final avail = width - base;
    if (avail >= s + m + d + o) {
      return (size: true, modified: true, mode: modeAllowed, owner: hasOwner);
    }
    if (avail >= s + m + d) {
      return (size: true, modified: true, mode: modeAllowed, owner: false);
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

    // Arrow-key navigation across rows + Enter to open. Focus on
    // the pane gives shortcut hits + cursor movement without a
    // mouse / touch device.
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final entries = ctrl.entries;
      if (entries.isEmpty) return KeyEventResult.ignored;
      final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      var idx = entries.indexWhere((e) => ctrl.selected.contains(e.path));
      if (idx < 0) {
        idx = delta > 0 ? 0 : entries.length - 1;
      } else {
        idx = (idx + delta).clamp(0, entries.length - 1);
      }
      ctrl.selectSingle(entries[idx].path);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (ctrl.selected.length == 1) {
        final entry = ctrl.selectedEntries.first;
        if (entry.isDir) {
          ctrl.navigateTo(entry.path);
          return KeyEventResult.handled;
        }
        // Plain file — same shape the double-tap path uses: hand
        // back to the transfer callback the parent wired in. The
        // pane itself has no in-place "open" surface today; the
        // double-tap path delegates to onTransfer.
        if (widget.onTransfer != null) {
          widget.onTransfer!(entry);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      if (ctrl.entries.isNotEmpty) {
        ctrl.selectSingle(ctrl.entries.first.path);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      if (ctrl.entries.isNotEmpty) {
        ctrl.selectSingle(ctrl.entries.last.path);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

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
    if (reg.matches(AppShortcut.openContextMenu, event) ||
        event.logicalKey == LogicalKeyboardKey.contextMenu) {
      _openContextMenuFromKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Anchor the context menu under a keyboard-driven open. Single
  /// selection → entry menu at the file-list's top-left + a small
  /// inset (rendering at the focused row's exact rect would need
  /// per-row keys; the inset is close enough for users to see the
  /// menu and navigate it). No selection → background menu at the
  /// same anchor.
  void _openContextMenuFromKeyboard() {
    final box = _fileListKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(const Offset(8, 8)) ?? Offset.zero;
    final selected = ctrl.selectedEntries;
    if (selected.length == 1) {
      _showContextMenu(context, origin, selected.first);
    } else if (selected.isEmpty) {
      _showBackgroundContextMenu(context, origin);
    } else {
      // Multi-selection: fire the entry menu against the first
      // selected item; the menu's `hasMultiple` branch already
      // collapses the labels to the bulk form.
      _showContextMenu(context, origin, selected.first);
    }
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

  /// Re-renders the pane from a per-section extension method.
  /// `State.setState` is `@protected` so extensions on
  /// `_FilePaneState` cannot call it directly; this wrapper keeps
  /// the rebuild path inside the class while letting the layout /
  /// actions part files mutate the same fields.
  void rebuild(VoidCallback fn) => setState(fn);
}
