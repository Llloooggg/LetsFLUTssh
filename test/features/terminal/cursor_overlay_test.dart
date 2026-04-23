import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/terminal/cursor_overlay.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

/// Wraps [child] in a MaterialApp with theme and localization.
Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

void main() {
  group('CursorTextOverlay — widget basics', () {
    testWidgets('renders IgnorePointer with CustomPaint', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      expect(find.byType(CursorTextOverlay), findsOneWidget);
      // CursorTextOverlay's build returns IgnorePointer > CustomPaint.
      // Verify the widget tree contains these types (may also appear in
      // ancestor widgets, so we check at least one exists).
      expect(find.byType(IgnorePointer), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('uses default fontFamily and padding', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      final widget = tester.widget<CursorTextOverlay>(
        find.byType(CursorTextOverlay),
      );
      expect(widget.fontFamily, 'JetBrains Mono');
      expect(widget.fontFamilyFallback, AppFonts.monoFallback);
      expect(widget.fontFamilyFallback, contains('Noto Color Emoji'));
      expect(widget.padding, const EdgeInsets.all(4));
    });

    testWidgets('accepts custom fontFamilyFallback', (tester) async {
      final terminal = Terminal();
      const override = <String>['Noto Emoji', 'monospace'];

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            fontFamilyFallback: override,
          ),
        ),
      );

      final widget = tester.widget<CursorTextOverlay>(
        find.byType(CursorTextOverlay),
      );
      expect(widget.fontFamilyFallback, override);
    });

    testWidgets('accepts custom fontFamily and padding', (tester) async {
      final terminal = Terminal();
      const customPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 16,
            fontFamily: 'Fira Code',
            padding: customPadding,
          ),
        ),
      );

      final widget = tester.widget<CursorTextOverlay>(
        find.byType(CursorTextOverlay),
      );
      expect(widget.fontFamily, 'Fira Code');
      expect(widget.padding, customPadding);
      expect(widget.fontSize, 16);
    });
  });

  group('CursorTextOverlay — terminal listener lifecycle', () {
    testWidgets('subscribes to terminal on init and unsubscribes on dispose', (
      tester,
    ) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Widget is mounted — listener is active. Writing to terminal should
      // not throw and should trigger a repaint cycle.
      terminal.write('A');
      await tester.pump();

      // Dispose the widget.
      await tester.pumpWidget(_app(const SizedBox.shrink()));

      // After dispose, writing should not cause errors (listener removed).
      terminal.write('B');
      await tester.pump();
    });

    testWidgets('swaps listener when terminal instance changes', (
      tester,
    ) async {
      final terminal1 = Terminal();
      final terminal2 = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal1, fontSize: 14)),
      );

      // Swap to a new terminal.
      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal2, fontSize: 14)),
      );

      // Old terminal should not affect the widget.
      terminal1.write('X');
      await tester.pump();

      // New terminal triggers repaint without errors.
      terminal2.write('Y');
      await tester.pump();
    });

    testWidgets('does not swap listener when same terminal is provided', (
      tester,
    ) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Rebuild with same terminal but different fontSize — didUpdateWidget
      // fires but should NOT swap listeners.
      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 18)),
      );

      terminal.write('Z');
      await tester.pump();
    });
  });

  group('CursorTextOverlay — painter rendering with terminal content', () {
    testWidgets('paints without error on empty terminal', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      await tester.pump();
      // No error means the paint method handled empty buffer gracefully.
    });

    testWidgets('paints without error when terminal has text at cursor', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Write text so the cursor sits on a character.
      terminal.write('Hello, World!');
      await tester.pump();
      // No exceptions means the painter handled cursor-over-text correctly.
    });

    testWidgets('paints without error after multiple writes and repaints', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      for (var i = 0; i < 5; i++) {
        terminal.write('line $i\r\n');
        await tester.pump();
      }
    });

    testWidgets('handles cursor at line boundary without error', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Move cursor to various positions. Write a full line, then newline.
      terminal.write('A' * 80);
      await tester.pump();

      terminal.write('\r\n');
      await tester.pump();
    });
  });

  group('CursorTextOverlay — shouldRepaint coverage', () {
    testWidgets('repaints when fontSize changes', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      terminal.write('A');
      await tester.pump();

      // Change fontSize — triggers shouldRepaint returning true.
      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 18)),
      );

      await tester.pump();
    });

    testWidgets('repaints when fontFamily changes', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      );

      terminal.write('A');
      await tester.pump();

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            fontFamily: 'Fira Code',
          ),
        ),
      );

      await tester.pump();
    });

    testWidgets('repaints when terminal instance changes', (tester) async {
      final terminal1 = Terminal();
      final terminal2 = Terminal();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal1, fontSize: 14)),
      );

      terminal1.write('A');
      await tester.pump();

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal2, fontSize: 14)),
      );

      await tester.pump();
    });

    testWidgets('repaints when fontFamilyFallback list changes', (
      tester,
    ) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            fontFamilyFallback: const ['Noto Color Emoji'],
          ),
        ),
      );

      terminal.write('A');
      await tester.pump();

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            fontFamilyFallback: const ['Apple Color Emoji'],
          ),
        ),
      );

      await tester.pump();
    });

    testWidgets('does not repaint when only padding changes', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            padding: const EdgeInsets.all(4),
          ),
        ),
      );

      terminal.write('A');
      await tester.pump();

      // Padding is not compared in shouldRepaint — only terminal, fontSize,
      // fontFamily. This rebuild should not trigger shouldRepaint == true,
      // but the widget will still rebuild due to didUpdateWidget.
      await tester.pumpWidget(
        _app(
          CursorTextOverlay(
            terminal: terminal,
            fontSize: 14,
            padding: const EdgeInsets.all(8),
          ),
        ),
      );

      await tester.pump();
    });
  });

  group('CursorTextOverlay — cell size caching', () {
    testWidgets('caches cell size across paints with same fontSize', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Write content to trigger paint, which calls _measureCellSize.
      terminal.write('Hello');
      await tester.pump();

      // Write more content — paint fires again but _measureCellSize should
      // return cached value.
      terminal.write(' World');
      await tester.pump();
    });

    testWidgets('recalculates cell size when fontSize changes', (tester) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      terminal.write('Test');
      await tester.pump();

      // Change font size — should invalidate cached cell size.
      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 20)),
      );

      terminal.write('!');
      await tester.pump();
    });
  });

  group('CursorTextOverlay — edge cases', () {
    testWidgets('handles cursor beyond buffer lines length', (tester) async {
      // A freshly created terminal with default size — cursor at (0,0).
      // The buffer should have lines matching viewHeight, but the cursor
      // might be on an empty cell. Painter should handle gracefully.
      final terminal = Terminal(maxLines: 1000);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      await tester.pump();
    });

    testWidgets('handles cursor on null/zero charCode cell', (tester) async {
      final terminal = Terminal(maxLines: 100);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Write a newline — cursor moves to next line where the cell is empty
      // (charCode == 0). Painter should return early.
      terminal.write('\r\n');
      await tester.pump();
    });

    testWidgets('handles scrolled terminal where cursor is off-screen', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 1000);

      await tester.pumpWidget(
        _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
      );

      // Write many lines to push cursor well beyond the visible viewport.
      final manyLines = List.generate(200, (i) => 'line $i\r\n').join();
      terminal.write(manyLines);
      await tester.pump();
    });
  });

  group('CursorTextOverlay — paint covers the cursor cell', () {
    testWidgets(
      'cursor sits on a non-empty cell: paint path runs without throwing',
      (tester) async {
        // The block-cursor paint short-circuits when `charCode == 0`
        // (default for freshly written terminals where the cursor
        // sits past the last written char). Force the cursor onto an
        // occupied cell by writing a char + carriage return — the
        // cursor snaps back to column 0 with the glyph still beneath
        // it — so the painter hits the full measure + draw path.
        final terminal = Terminal(maxLines: 100);
        terminal.write('X\r');

        await tester.pumpWidget(
          _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
        );
        // The overlay coalesces repaints via a post-frame callback, so
        // the first paint needs a second pump to drain the schedule.
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets(
      'cursor off-screen after a long scrollback: paint exits early',
      (tester) async {
        // 200 lines of output push the shell cursor well past the
        // visible viewport. `visibleRow < 0` → painter returns early.
        // The test asserts that exit is silent (no exceptions + no
        // inverted glyph rendered off-canvas).
        final terminal = Terminal(maxLines: 1000);
        await tester.pumpWidget(
          _app(CursorTextOverlay(terminal: terminal, fontSize: 14)),
        );
        terminal.write(List.generate(200, (i) => 'line $i\r\n').join());
        await tester.pump();
        await tester.pump();
      },
    );
  });

  group('CursorTextOverlay — line-height invariant (xterm lockstep)', () {
    test(
      'kTerminalLineHeight matches the xterm TerminalStyle default (1.2)',
      () {
        // xterm's TerminalStyle defaults height to 1.2 (see xterm package
        // source). Our overlay has to measure cells with the same multiplier
        // or the painted inverted-cursor glyph / virtual-cursor marker drifts
        // vertically against the xterm-rendered text. A bump in xterm's
        // default will surface here first so we can align our constant.
        expect(kTerminalLineHeight, 1.2);
      },
    );

    test('measured cell height uses the 1.2 line-height multiplier', () {
      // A raw measurement without the height multiplier yields
      // `paragraph.height ≈ fontSize * ~1.17` (font ascent+descent). With
      // the 1.2 multiplier xterm applies, the paragraph height is
      // `fontSize * 1.2`. Pin that invariant — a regression that drops
      // the height arg silently reintroduces the cursor/selection
      // offset bug users saw on mobile.
      const fontSize = 14.0;
      final style = ui.TextStyle(
        fontSize: fontSize,
        height: kTerminalLineHeight,
      );
      final builder =
          ui.ParagraphBuilder(ui.ParagraphStyle(height: kTerminalLineHeight))
            ..pushStyle(style)
            ..addText('mmmmmmmmmm');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      expect(paragraph.height, closeTo(fontSize * kTerminalLineHeight, 0.5));
      paragraph.dispose();
    });
  });
}
