import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../widgets/context_menu.dart';
import '../widgets/shortcut_registry.dart';
import '../theme/app_theme.dart';
import '../utils/terminal_clipboard.dart';

/// Read-only xterm TerminalView — no keyboard input, no context menu.
///
/// Used by [ConnectionProgress] for SFTP tab progress/error display.
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
  late final TerminalController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    widget.terminal.write('\x1B[?25l'); // hide cursor — read-only view
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Intercept the terminal-copy shortcut before xterm swallows the
  /// key event. xterm's `TerminalView` consumes most key combos as
  /// raw terminal input; without this hook the read-only progress
  /// view would silently drop Ctrl+C / Cmd+C even when the user
  /// has selected text. Copy is the only shortcut we honour here —
  /// paste and resize don't apply to a read-only progress overlay.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (AppShortcutRegistry.instance.matches(AppShortcut.terminalCopy, event)) {
      TerminalClipboard.copy(widget.terminal, _controller);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Right-click handler. xterm's gesture stack does not surface a
  /// secondary-tap callback when none is wired through `TerminalView`,
  /// and worse: even with no secondary handler, competing recognisers
  /// (the pan recogniser among them) can snip the active selection
  /// off the controller as the gesture arena resolves the right-click.
  /// We therefore use a [`Listener`] that fires synchronously on
  /// `PointerDownEvent`, BEFORE the gesture arena runs — that gives
  /// us a stable read of the selection's text to bake into the menu's
  /// Copy item, and the menu itself appears regardless of which
  /// recogniser ends up winning the arena.
  void _onPointerDown(PointerDownEvent event, BuildContext menuContext) {
    if (event.buttons != kSecondaryButton) return;
    final selection = _controller.selection;
    if (selection == null) return;
    final text = widget.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    showAppContextMenu(
      context: menuContext,
      position: event.position,
      items: [
        StandardMenuAction.copy.item(
          menuContext,
          shortcut: AppShortcut.terminalCopy,
          onTap: () {
            TerminalClipboard.copyText(text);
            _controller.clearSelection();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: Listener(
        onPointerDown: (event) => _onPointerDown(event, context),
        child: TerminalView(
          widget.terminal,
          controller: _controller,
          autofocus: false,
          hardwareKeyboardOnly: true,
          backgroundOpacity: 1.0,
          padding: const EdgeInsets.all(4),
          theme: AppTheme.terminalTheme,
          textStyle: TerminalStyle(
            fontSize: widget.fontSize,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }
}
