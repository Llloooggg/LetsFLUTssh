import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/terminal_copy_overlay.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/theme/app_theme.dart';

/// A captured selection update from the overlay, in absolute grid-line
/// coordinates.
class _Sel {
  const _Sel(this.startRow, this.startCol, this.endRow, this.endCol);
  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;
}

/// Build a synthetic frame so the overlay's cell math runs without a live
/// `TerminalSession`. `displayOffset` lets a test exercise the
/// absolute-row mapping (viewportRow - displayOffset).
rust_terminal.TerminalFrame _frame({
  int cols = 80,
  int rows = 24,
  int displayOffset = 0,
}) {
  return rust_terminal.TerminalFrame(
    cols: cols,
    rows: rows,
    cursor: const rust_terminal.TerminalCursor(
      row: 0,
      col: 0,
      shape: rust_terminal.TerminalCursorShape.block,
      visible: true,
    ),
    displayOffset: displayOffset,
    historySize: 0,
    mouseTracking: rust_terminal.TerminalMouseTracking.none,
    cells: const [],
  );
}

void main() {
  Widget app(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
    );
  }

  group('TerminalCopyOverlay — lifecycle', () {
    testWidgets('clears the engine selection on mount and on dispose', (
      tester,
    ) async {
      var clears = 0;
      await tester.pumpWidget(
        app(
          TerminalCopyOverlay(
            snapshotProvider: _frame,
            onSetSelection: (_, _, _, _) {},
            onClearSelection: () => clears++,
            onScroll: (_) {},
            fontSize: 14,
          ),
        ),
      );
      // One clear on mount.
      expect(clears, 1);

      await tester.pumpWidget(app(const SizedBox.shrink()));
      // A second clear on dispose.
      expect(clears, 2);
    });
  });

  group('TerminalCopyOverlay — cursor + selection', () {
    testWidgets('onAnchorDown sets a selection at the cursor cell', (
      tester,
    ) async {
      _Sel? sel;
      final key = GlobalKey<TerminalCopyOverlayState>();
      await tester.pumpWidget(
        app(
          TerminalCopyOverlay(
            key: key,
            snapshotProvider: _frame,
            onSetSelection: (sr, sc, er, ec) => sel = _Sel(sr, sc, er, ec),
            onClearSelection: () {},
            onScroll: (_) {},
            fontSize: 14,
          ),
        ),
      );

      expect(key.currentState!.anchorSet, isFalse);

      key.currentState!.onAnchorDown();
      await tester.pump();

      expect(key.currentState!.anchorSet, isTrue);
      // Cursor starts under the engine cursor (0,0); anchor == cursor here,
      // so a collapsed single-cell selection at the origin.
      expect(sel, isNotNull);
      expect(sel!.startRow, 0);
      expect(sel!.startCol, 0);
      expect(sel!.endRow, 0);
      expect(sel!.endCol, 0);
    });

    testWidgets('onAnchorDown is idempotent after the first call', (
      tester,
    ) async {
      final sels = <_Sel>[];
      final key = GlobalKey<TerminalCopyOverlayState>();
      await tester.pumpWidget(
        app(
          TerminalCopyOverlay(
            key: key,
            snapshotProvider: _frame,
            onSetSelection: (sr, sc, er, ec) => sels.add(_Sel(sr, sc, er, ec)),
            onClearSelection: () {},
            onScroll: (_) {},
            fontSize: 14,
          ),
        ),
      );

      key.currentState!.onAnchorDown();
      key.currentState!.onAnchorDown();
      // Second anchor-down is a no-op — only the first set a selection.
      expect(sels.length, 1);
    });

    testWidgets('onCursorPan extends the selection rightward', (tester) async {
      _Sel? last;
      final key = GlobalKey<TerminalCopyOverlayState>();
      await tester.pumpWidget(
        app(
          TerminalCopyOverlay(
            key: key,
            snapshotProvider: _frame,
            onSetSelection: (sr, sc, er, ec) => last = _Sel(sr, sc, er, ec),
            onClearSelection: () {},
            onScroll: (_) {},
            fontSize: 14,
          ),
        ),
      );

      key.currentState!.onAnchorDown();
      // Push ~100px right; cell width at fontSize 14 is ~8-9px so the cursor
      // advances several columns past the anchor.
      key.currentState!.onCursorPan(const Offset(100, 0));
      await tester.pump();

      expect(last, isNotNull);
      // Anchor stays at column 0; the end column advanced.
      expect(last!.startCol, 0);
      expect(last!.endCol, greaterThan(0));
    });

    testWidgets('anchor row accounts for the scroll displayOffset', (
      tester,
    ) async {
      // With the viewport scrolled up by 5 lines, a cursor on viewport row 0
      // maps to absolute row -5 (negative = scrollback) — the inverse of the
      // engine's row = absolute + displayOffset mapping.
      _Sel? sel;
      final key = GlobalKey<TerminalCopyOverlayState>();
      await tester.pumpWidget(
        app(
          TerminalCopyOverlay(
            key: key,
            snapshotProvider: () => _frame(displayOffset: 5),
            onSetSelection: (sr, sc, er, ec) => sel = _Sel(sr, sc, er, ec),
            onClearSelection: () {},
            onScroll: (_) {},
            fontSize: 14,
          ),
        ),
      );

      key.currentState!.onAnchorDown();
      await tester.pump();
      expect(sel!.startRow, -5);
    });
  });
}
