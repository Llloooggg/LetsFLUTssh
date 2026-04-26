import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/readonly_terminal_view.dart';
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

    testWidgets('Focus wrapper intercepts terminalCopy shortcut', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadOnlyTerminalView(terminal: terminal)),
        ),
      );

      // The progress overlay swaps the previous `FocusScope(canRequestFocus:
      // false)` wrapper for a `Focus(onKeyEvent: ...)` so the
      // `terminalCopy` shortcut reaches our handler before xterm
      // swallows the key. Selection itself stays mouse-driven; the
      // hook only matters for keyboard-initiated copies.
      final focus = tester.widget<Focus>(
        find
            .ancestor(
              of: find.byType(TerminalView),
              matching: find.byType(Focus),
            )
            .first,
      );
      expect(focus.onKeyEvent, isNotNull);
    });
  });
}
