import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Shared clipboard operations for terminal views (desktop + mobile).
class TerminalClipboard {
  TerminalClipboard._();

  /// Copy the current selection text to clipboard and clear selection.
  static void copy(Terminal terminal, TerminalController controller) {
    final selection = controller.selection;
    if (selection == null) return;
    final text = terminal.buffer.getText(selection);
    Clipboard.setData(ClipboardData(text: text));
    controller.clearSelection();
  }

  /// Paste clipboard text into terminal.
  static Future<void> paste(Terminal terminal) async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      terminal.textInput(data.text!);
    }
  }
}
