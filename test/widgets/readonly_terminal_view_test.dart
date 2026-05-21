import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/terminal/readonly_terminal_view.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('ReadOnlyTerminalView', () {
    testWidgets('renders TerminalView inside FocusScope', (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadOnlyTerminalView(terminal: terminal, fontSize: 16),
          ),
        ),
      );

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.byType(FocusScope), findsWidgets);
    });

    testWidgets('uses default fontSize of 14', (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadOnlyTerminalView(terminal: terminal)),
        ),
      );

      final widget = tester.widget<ReadOnlyTerminalView>(
        find.byType(ReadOnlyTerminalView),
      );
      expect(widget.fontSize, 14.0);
    });

    testWidgets('accepts custom fontSize', (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadOnlyTerminalView(terminal: terminal, fontSize: 20),
          ),
        ),
      );

      final widget = tester.widget<ReadOnlyTerminalView>(
        find.byType(ReadOnlyTerminalView),
      );
      expect(widget.fontSize, 20.0);
    });

    testWidgets('TerminalView.onKeyEvent is wired so Ctrl+C / Cmd+C copy '
        'fires ahead of xterm\'s internal shortcut manager', (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadOnlyTerminalView(terminal: terminal)),
        ),
      );

      // The earlier shape wrapped TerminalView in
      // `Focus(onKeyEvent:)` and relied on the ancestor seeing
      // the key event first — but Flutter's focus chain
      // dispatches descendant-first, and xterm's internal Focus
      // returned `handled` for Ctrl+Shift+C and ignored plain
      // Ctrl+C, so the wrapper never got a chance. The current
      // shape hands the callback to `TerminalView.onKeyEvent`
      // directly; xterm 4 calls it ahead of its internal
      // `_shortcutManager` (`terminal_view.dart:394`) and
      // short-circuits on a non-ignored return. The assertion
      // pins that the callback is wired so a future refactor
      // can't silently drop it and break log-pane copy.
      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      expect(
        terminalView.onKeyEvent,
        isNotNull,
        reason:
            'ReadOnlyTerminalView must hand `onKeyEvent` to TerminalView so '
            'plain Ctrl+C / Cmd+C copy beats xterm\'s default '
            'Ctrl+Shift+C-only shortcut map.',
      );
    });
  });
}
