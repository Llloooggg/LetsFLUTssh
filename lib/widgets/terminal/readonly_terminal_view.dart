import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/terminal_clipboard.dart';
import 'anchor_pinning_terminal_controller.dart';
import 'app_terminal_view.dart';
import '../core/context_menu.dart';
import '../core/shortcut_registry.dart' show AppShortcut;

/// Read-only xterm `TerminalView` — no keyboard input, no cursor.
///
/// Thin wrapper around [AppTerminalView] that owns an
/// [AnchorPinningTerminalController], hides the cursor on mount
/// (`\x1B[?25l`), and provides a Copy + Select All right-click
/// menu via [showAppContextMenu]. All gesture handling
/// (right-click via `Listener.onPointerDown`, primary-mouse
/// `beginDrag` / `endDrag`, etc.) is delegated to
/// [AppTerminalView] so this widget and the live PTY pane share
/// one battle-tested code path.
class ReadOnlyTerminalView extends StatefulWidget {
  final Terminal terminal;
  final double fontSize;

  const ReadOnlyTerminalView({
    super.key,
    required this.terminal,
    this.fontSize = 14.0,
  });

  @override
  State<ReadOnlyTerminalView> createState() => _ReadOnlyTerminalViewState();
}

class _ReadOnlyTerminalViewState extends State<ReadOnlyTerminalView> {
  late final AnchorPinningTerminalController _controller;

  /// Owned focus node so [_handleKey] reliably receives `Ctrl+C`.
  /// xterm's built-in `_onTapDown` only requests focus when the
  /// controller has no active selection — re-clicking after a
  /// drag-select clears the selection but does NOT re-focus the
  /// terminal, so subsequent `Ctrl+C` key events stop reaching us.
  /// Owning the node lets the secondary-tap-or-primary-down
  /// handler in `_handleAuxFocus` request focus unconditionally.
  final FocusNode _focus = FocusNode(debugLabel: 'ReadOnlyTerminalView');

  @override
  void initState() {
    super.initState();
    _controller = AnchorPinningTerminalController();
    widget.terminal.write('\x1B[?25l'); // hide cursor — read-only view
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Request focus on every primary-button press regardless of
  /// current selection state. Bridges xterm 4's gap (`_onTapDown`
  /// skips `requestFocus` when selection is non-null), so a click
  /// always re-arms the terminal as the key-event target — without
  /// this, `Ctrl+C` only works on the very first interaction.
  void _handlePointerDown(BuildContext context, PointerDownEvent event) {
    if (event.buttons == kPrimaryButton) {
      _focus.requestFocus();
    }
  }

  /// Plain `Ctrl+C` / `Cmd+C` copy. Not [`AppShortcut.terminalCopy`]
  /// (`Ctrl+Shift+C`) — this surface renders a log, not a live PTY,
  /// so the Unix convention of reserving `Ctrl+C` for SIGINT does
  /// not apply.
  static const _copyActivators = <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true),
  ];

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    for (final activator in _copyActivators) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        TerminalClipboard.copy(widget.terminal, _controller);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _controller.selection != null;
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          StandardMenuAction.copy.item(
            context,
            shortcut: AppShortcut.fileCopy,
            onTap: () => TerminalClipboard.copy(widget.terminal, _controller),
          ),
        ContextMenuItem(
          label: S.of(context).selectAll,
          icon: Icons.select_all,
          onTap: _selectAll,
        ),
      ],
    );
  }

  /// Select the entire scrollback + viewport. Uses
  /// `buffer.createAnchor(col, row)` — the only public xterm 4 API
  /// for synthesising selection anchors outside a live drag.
  void _selectAll() {
    final terminal = widget.terminal;
    final buffer = terminal.buffer;
    if (buffer.height == 0) return;
    _controller.setSelection(
      buffer.createAnchor(0, buffer.height - terminal.viewHeight),
      buffer.createAnchor(terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _handlePointerDown(context, e),
      child: AppTerminalView(
        terminal: widget.terminal,
        controller: _controller,
        focusNode: _focus,
        fontSize: widget.fontSize,
        autofocus: false,
        hardwareKeyboardOnly: true,
        onKeyEvent: _handleKey,
        secondaryTapBuilder: _showContextMenu,
      ),
    );
  }
}
