import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../core/shortcut_registry.dart';
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
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
    );
  }
}
