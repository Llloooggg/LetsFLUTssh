import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      canRequestFocus: false,
      child: TerminalView(
        widget.terminal,
        controller: _controller,
        autofocus: false,
        hardwareKeyboardOnly: true,
        backgroundOpacity: 1.0,
        padding: const EdgeInsets.all(4),
        theme: TerminalTheme(
          cursor: AppTheme.termCursor,
          selection: AppTheme.termSelection,
          foreground: AppTheme.fg,
          background: AppTheme.bg2,
          black: AppTheme.termBlack,
          red: AppTheme.termRed,
          green: AppTheme.termGreen,
          yellow: AppTheme.termYellow,
          blue: AppTheme.termBlue,
          magenta: AppTheme.termMagenta,
          cyan: AppTheme.termCyan,
          white: AppTheme.termWhite,
          brightBlack: AppTheme.termBrightBlack,
          brightRed: AppTheme.termBrightRed,
          brightGreen: AppTheme.termBrightGreen,
          brightYellow: AppTheme.termBrightYellow,
          brightBlue: AppTheme.termBrightBlue,
          brightMagenta: AppTheme.termBrightMagenta,
          brightCyan: AppTheme.termBrightCyan,
          brightWhite: AppTheme.termBrightWhite,
          searchHitBackground: AppTheme.accent.withValues(alpha: 0.3),
          searchHitBackgroundCurrent: AppTheme.accent,
          searchHitForeground: AppTheme.searchHitFg,
        ),
        textStyle: TerminalStyle(
          fontSize: widget.fontSize,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}
