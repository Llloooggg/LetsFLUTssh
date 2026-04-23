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

TerminalCopyOverlay _buildOverlay({
  required Terminal terminal,
  required TerminalController controller,
  required ScrollController scrollController,
  Key? key,
}) => TerminalCopyOverlay(
  key: key,
  terminal: terminal,
  controller: controller,
  scrollController: scrollController,
  fontSize: 14,
  fontFamily: AppFonts.monoFamily,
  fontFamilyFallback: AppFonts.monoFallback,
);

void main() {
  group('TerminalCopyOverlay — lifecycle', () {
    testWidgets('suspends pointer input on mount and restores on dispose', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      final scroll = ScrollController();

      await tester.pumpWidget(
        _app(
          _buildOverlay(
            terminal: terminal,
            controller: controller,
            scrollController: scroll,
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
      final scroll = ScrollController();
      final line = terminal.buffer.lines[0];
      controller.setSelection(line.createAnchor(0), line.createAnchor(5));
      expect(controller.selection, isNotNull);

      await tester.pumpWidget(
        _app(
          _buildOverlay(
            terminal: terminal,
            controller: controller,
            scrollController: scroll,
          ),
        ),
      );

      expect(controller.selection, isNull);
    });
  });

  group('TerminalCopyOverlay — cursor + selection', () {
    testWidgets('onAnchorDown sets a selection anchor at the cursor', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      terminal.write('hello world');
      final controller = TerminalController();
      final scroll = ScrollController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          _buildOverlay(
            terminal: terminal,
            controller: controller,
            scrollController: scroll,
            key: key,
          ),
        ),
      );

      // Before first anchor-down, selection is empty and `anchorSet` is
      // false — parent uses it to swap the hint copy in the Column layout.
      expect(controller.selection, isNull);
      expect(key.currentState!.anchorSet, isFalse);

      key.currentState!.onAnchorDown();
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(key.currentState!.anchorSet, isTrue);
    });

    testWidgets('onAnchorDown is idempotent after the first call', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);
      final controller = TerminalController();
      final scroll = ScrollController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          _buildOverlay(
            terminal: terminal,
            controller: controller,
            scrollController: scroll,
            key: key,
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
      final scroll = ScrollController();
      final key = GlobalKey<TerminalCopyOverlayState>();

      await tester.pumpWidget(
        _app(
          _buildOverlay(
            terminal: terminal,
            controller: controller,
            scrollController: scroll,
            key: key,
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

  // CopyModeHint and CopyModeToolbar were removed: the bar's row
  // now swaps its own contents between normal keys and copy-mode
  // content inside the same fixed-height Container, which keeps
  // the terminal widget a constant size across copy-mode toggles.
  // Coverage for the swap lives in the SshKeyboardBar test file.
}
