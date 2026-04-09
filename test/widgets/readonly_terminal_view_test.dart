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

    testWidgets('FocusScope prevents focus requests', (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadOnlyTerminalView(terminal: terminal)),
        ),
      );

      // FocusScope with canRequestFocus: false should wrap the terminal
      final focusScope = tester.widget<FocusScope>(
        find
            .ancestor(
              of: find.byType(TerminalView),
              matching: find.byType(FocusScope),
            )
            .first,
      );
      expect(focusScope.canRequestFocus, false);
    });
  });
}
