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
        theme: AppTheme.terminalTheme,
        textStyle: TerminalStyle(
          fontSize: widget.fontSize,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}
