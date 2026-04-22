import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/terminal_copy_overlay.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

/// Wraps [child] in a MaterialApp with theme + localization and a fixed
/// SizedBox so layout is deterministic.
Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

void main() {
  group('TerminalCopyOverlay — lifecycle', () {
    testWidgets('suspends pointer input on mount and restores on dispose', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () {},
          ),
        ),
      );

      expect(controller.suspendedPointerInputs, isTrue);

      await tester.pumpWidget(_app(const SizedBox.shrink()));

      expect(controller.suspendedPointerInputs, isFalse);
    });

    testWidgets('clears any pre-existing selection on mount', (tester) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('hello world');
      final controller = TerminalController();
      final line = terminal.buffer.lines[0];
      controller.setSelection(line.createAnchor(0), line.createAnchor(5));
      expect(controller.selection, isNotNull);

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () {},
          ),
        ),
      );

      expect(controller.selection, isNull);
    });
  });

  group('TerminalCopyOverlay — toolbar actions', () {
    testWidgets('tapping Copy button fires onCopy', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      var fired = 0;

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () => fired++,
            onCancel: () {},
          ),
        ),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('tapping Cancel button fires onCancel', (tester) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      var fired = 0;

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () => fired++,
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(fired, 1);
    });
  });

  group('TerminalCopyOverlay — cursor + selection', () {
    testWidgets('onAnchorDown sets a selection anchor at the cursor', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('hello world');
      final controller = TerminalController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            key: key,
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () {},
          ),
        ),
      );

      // Before first anchor-down, selection is empty.
      expect(controller.selection, isNull);

      key.currentState!.onAnchorDown();
      await tester.pump();

      // Anchor + extent are both at the cursor, so the range is zero-
      // width but the controller reports a non-null selection.
      expect(controller.selection, isNotNull);
    });

    testWidgets('onAnchorDown is idempotent after the first call', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            key: key,
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () {},
          ),
        ),
      );

      key.currentState!.onAnchorDown();
      final first = controller.selection;
      expect(first, isNotNull);

      key.currentState!.onAnchorDown();
      // Second call must not move the anchor — the user lifted and
      // re-touched and should continue extending, not re-anchor.
      expect(controller.selection?.begin, first!.begin);
    });

    testWidgets('onCursorPan moves the cursor and extends selection', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('hello world');
      final controller = TerminalController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          TerminalCopyOverlay(
            key: key,
            terminal: terminal,
            controller: controller,
            fontSize: 14,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            onCopy: () {},
            onCancel: () {},
          ),
        ),
      );

      key.currentState!.onAnchorDown();
      // Push the finger across roughly five cells. Cell width at
      // fontSize 14 is ~8-9 px, so 100 px will advance ~10 cells —
      // enough to know the selection's extent column moved.
      key.currentState!.onCursorPan(const Offset(100, 0));
      await tester.pump();

      final sel = controller.selection!;
      expect(sel.end.x, greaterThan(sel.begin.x));
    });
  });
}
