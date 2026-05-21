import 'package:xterm/xterm.dart';

import '../../core/ssh/shell_helper.dart' show ShellTerminal;

/// Adapts an xterm [Terminal] to the core-side [ShellTerminal] surface
/// so the Flutter terminal package stays out of `core/`. The resize
/// callback drops xterm's pixel dimensions — the shell only needs the
/// cell grid (cols, rows).
class XtermShellTerminal implements ShellTerminal {
  XtermShellTerminal(this.terminal);

  final Terminal terminal;

  @override
  int get viewWidth => terminal.viewWidth;

  @override
  int get viewHeight => terminal.viewHeight;

  @override
  void write(String data) => terminal.write(data);

  @override
  set onOutput(void Function(String data)? handler) =>
      terminal.onOutput = handler;

  @override
  set onResize(void Function(int cols, int rows)? handler) =>
      terminal.onResize = handler == null
      ? null
      : (w, h, _, _) => handler(w, h);
}
