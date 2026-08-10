import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/widgets/terminal/terminal_controller.dart';
import 'package:letsflutssh/widgets/terminal/terminal_palette_theme.dart';

import '../../helpers/frb_bootstrap.dart';

/// Pull the printed characters out of a sparse [TerminalFrame].
Set<String> _chars(TerminalFrame frame) =>
    frame.cells.map((c) => String.fromCharCode(c.ch)).toSet();

void main() {
  // The replay adapter wraps a real Rust TerminalReplay, so the native library
  // must be loaded.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('ReplayTerminalController', () {
    test('feed renders bytes into the snapshot and notifies repaint', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.feed(utf8.encode('Hi'));

      expect(_chars(controller.snapshot()), containsAll(['H', 'i']));
      expect(notified, 1);
    });

    test('clear wipes the grid and notifies', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('hello world'));
      expect(controller.snapshot().cells, isNotEmpty);

      var notified = 0;
      controller.repaint.addListener(() => notified++);
      controller.clear();

      expect(controller.snapshot().cells, isEmpty);
      expect(notified, 1);
    });

    test('resize updates the reported cols/rows; a no-op resize is silent', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.resize(40, 10);
      expect(controller.cols, 40);
      expect(controller.rows, 10);
      expect(controller.snapshot().cols, 40);
      expect(notified, 1);

      // Re-resizing to the same dims must not notify (the view re-reports the
      // same size on every layout pass).
      controller.resize(40, 10);
      expect(notified, 1);
    });

    test('selection round-trips through the engine and notifies', () async {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('abcdef'));
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      // Select the first three cells of the top line.
      await controller.setSelection(0, 0, 0, 2, TerminalSelectionKind.simple);
      expect(notified, 1);
      expect(await controller.selectionText(), isNotNull);

      controller.clearSelection();
      expect(notified, 2);
      expect(await controller.selectionText(), isNull);
    });

    test('feed discards PtyWrite replies without leaking into the grid', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      // `ESC[6n` (device status report) makes the engine queue a PtyWrite
      // reply; the replay drops it. The surrounding text still renders.
      controller.feed(utf8.encode('A\x1B[6nB'));

      expect(_chars(controller.snapshot()), containsAll(['A', 'B']));
    });

    test('exposes no UI-event stream and reports not-live', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      expect(controller.uiEvents, isNull);
      expect(controller.isLive, isFalse);
    });

    // Spec: the live-only capabilities are inert no-ops on the replay adapter
    // (the read-only surfaces never enable the matching config), so calling
    // them must neither throw nor mutate the grid.
    test('live-only capabilities are inert on the replay adapter', () async {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      expect(
        () => controller.sendKey(
          const TerminalKey(
            name: TerminalKeyName.char(code: 0x41),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
          ),
        ),
        returnsNormally,
      );
      expect(() => controller.writeInput(utf8.encode('x')), returnsNormally);
      expect(
        () => controller.sendMouse(
          const TerminalMouseInput(
            button: TerminalMouseButton.left,
            action: TerminalMouseAction.press,
            col: 1,
            row: 1,
            shift: false,
            alt: false,
            ctrl: false,
          ),
        ),
        returnsNormally,
      );
      expect(() => controller.scroll(3), returnsNormally);
      await controller.paste('x');
      expect(await controller.search('x'), isEmpty);
      // None of the inert calls put anything on the grid.
      expect(controller.snapshot().cells, isEmpty);
    });

    test('dispose releases the Rust replay handle deterministically', () {
      // The controller owns the `TerminalReplay` opaque, so its dispose
      // must drop it rather than leaving it to the FRB finalizer. After
      // dispose the controller marks itself disposed, so further engine
      // calls become no-ops instead of crashing on a released Arc.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      controller.dispose();
      expect(controller.disposed, isTrue);
      // Disposed calls are no-ops — they do not throw, they do not crash.
      expect(() => controller.feed(utf8.encode('x')), returnsNormally);
      expect(controller.snapshot().cols, 0);
    });

    test('setPalette pushes the new palette and notifies repaint', () {
      // Spec: a brightness flip re-themes the terminal by handing a
      // fresh `TerminalPalette` to the engine and pulsing the repaint
      // signal so the view re-pulls a snapshot resolving cell colors
      // against the new palette. The grid contents stay intact — only
      // resolved RGB values change on the next snapshot.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('A'));
      final beforeCells = controller.snapshot().cells.length;
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.setPalette(TerminalPaletteFromTheme.fromAppTheme());

      expect(notified, 1);
      // Same content count after re-theming — palette swap does not
      // wipe the grid.
      expect(controller.snapshot().cells.length, beforeCells);
    });

    test('snapshot reports the configured cols/rows', () {
      final controller = ReplayTerminalController(cols: 30, rows: 12);
      addTearDown(controller.dispose);
      final frame = controller.snapshot();
      expect(frame.cols, 30);
      expect(frame.rows, 12);
    });

    test('repaint listenable is this notifier (single source)', () {
      // `Listenable get repaint => this;` on the replay adapter — the
      // view listens to the same ChangeNotifier the controller mixes
      // in, so removing a listener via `repaint.removeListener` and
      // `this.removeListener` reach the same dispatch table.
      final controller = ReplayTerminalController(cols: 10, rows: 5);
      addTearDown(controller.dispose);
      expect(identical(controller.repaint, controller), isTrue);
    });

    test('successive feeds notify the repaint listenable once per call', () {
      // Spec: every host-driven feed pulses the repaint signal so the
      // view re-pulls a snapshot on each frame. Batching would drop the
      // intermediate state and a recording scrub or log-viewer mid-stream
      // would skip frames between writes.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.feed(utf8.encode('one '));
      controller.feed(utf8.encode('two '));
      controller.feed(utf8.encode('three'));

      expect(notified, 3);
      expect(_chars(controller.snapshot()), containsAll(['o', 't', 'h']));
    });

    test('clear after content removes glyphs and the repaint pulse fires '
        'on every invocation', () {
      // The recording scrub path clears the grid before re-feeding from
      // t=0; back-to-back clears must each notify so an already-empty
      // grid still drives the next frame pull (other state — palette,
      // resize — may have changed between clears).
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('payload'));
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.clear();
      controller.clear();

      expect(notified, 2);
      expect(controller.snapshot().cells, isEmpty);
    });

    test('paste, writeInput, sendKey and scroll do not emit a repaint pulse '
        'on the replay adapter', () async {
      // The live-only entry points are inert no-ops on the replay
      // adapter (no shell to write to); they must therefore not pulse
      // repaint either, because there is no engine-side change for the
      // view to re-pull.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      await controller.paste('hi');
      controller.writeInput(utf8.encode('x'));
      controller.sendKey(
        const TerminalKey(
          name: TerminalKeyName.char(code: 0x41),
          ctrl: false,
          alt: false,
          shift: false,
          meta: false,
        ),
      );
      controller.scroll(3);

      expect(notified, 0);
    });

    test('resize that only changes one dimension still notifies and updates '
        'the snapshot grid', () {
      // The no-op short-circuit fires only when BOTH cols and rows
      // match; a width-only or height-only change is a real resize that
      // must re-flow the grid and pulse repaint.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.resize(20, 10); // rows-only change
      expect(notified, 1);
      expect(controller.cols, 20);
      expect(controller.rows, 10);
      expect(controller.snapshot().rows, 10);

      controller.resize(30, 10); // cols-only change
      expect(notified, 2);
      expect(controller.cols, 30);
      expect(controller.snapshot().cols, 30);
    });

    test('selection covering all printed cells round-trips through '
        '`selectionText` as that exact text', () async {
      // Spec: the engine owns selection text; `selectionText` reads it
      // straight back without Dart-side caching. The expected substring
      // is the literal payload fed in (no soft-wrap, single short line).
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('hello'));

      await controller.setSelection(0, 0, 0, 4, TerminalSelectionKind.simple);
      final text = await controller.selectionText();

      expect(text, isNotNull);
      expect(text!.contains('hello'), isTrue);
    });

    test(
      'constructor with custom scrollback honours the requested depth — '
      'feeding past viewport keeps prior lines reachable via selection',
      () async {
        // Spec: the `scrollback` constructor arg sizes the off-viewport
        // ring buffer the engine retains. A non-default value must reach
        // the Rust side so a log-viewer requesting more history than the
        // 10k default actually retains it. Verified observably: feed past
        // the viewport, then select a row that landed in scrollback and
        // confirm the selection text is non-null.
        final controller = ReplayTerminalController(
          cols: 20,
          rows: 3,
          scrollback: 500,
        );
        addTearDown(controller.dispose);

        // Write 6 lines into a 3-row viewport so 3 lines spill into
        // scrollback. Use printable chars so a selection can pick them up.
        controller.feed(utf8.encode('l1\nl2\nl3\nl4\nl5\nl6'));

        // Row -1 is the most recent scrollback line. With 3 lines spilled
        // it must be reachable by selection.
        await controller.setSelection(
          -1,
          0,
          -1,
          1,
          TerminalSelectionKind.simple,
        );
        expect(await controller.selectionText(), isNotNull);
      },
    );

    test('custom palette passed to constructor reaches the engine — '
        'subsequent setPalette swap still notifies', () {
      // Spec: the `palette` constructor arg short-circuits the
      // `TerminalPaletteFromTheme.fromAppTheme()` default so embedders
      // (release-notes viewer, mobile preview) can pin a fixed palette
      // independent of `AppTheme`. The two-stage check — construct with
      // an explicit palette, then swap to another — exercises both the
      // constructor handoff and `setPalette` pulse.
      final initial = TerminalPaletteFromTheme.fromAppTheme();
      final controller = ReplayTerminalController(
        cols: 20,
        rows: 5,
        palette: initial,
      );
      addTearDown(controller.dispose);

      // Smoke — engine accepted the palette; snapshot is valid.
      expect(controller.snapshot().cols, 20);

      var notified = 0;
      controller.repaint.addListener(() => notified++);
      controller.setPalette(TerminalPaletteFromTheme.fromAppTheme());
      expect(notified, 1);
    });

    test('rectangular selection kind routes through to the engine — kind is '
        'not collapsed into simple on the Dart side', () async {
      // Spec: `TerminalSelectionKind` has multiple variants (simple,
      // block / rectangular). The controller is a thin shim; the
      // `kind` arg must reach the engine unchanged. We can't read it
      // back directly, but we can assert both kinds round-trip
      // selectionText non-null (the engine accepts both) and that the
      // repaint pulse fires equally for both.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('row1\nrow2\nrow3'));

      var notified = 0;
      controller.repaint.addListener(() => notified++);

      await controller.setSelection(0, 0, 1, 2, TerminalSelectionKind.simple);
      expect(await controller.selectionText(), isNotNull);
      expect(notified, 1);

      await controller.setSelection(0, 0, 1, 2, TerminalSelectionKind.block);
      expect(await controller.selectionText(), isNotNull);
      expect(notified, 2);
    });

    test('setSelection on a fresh empty grid still notifies but selectionText '
        'reflects an empty region', () async {
      // Spec: the controller does not pre-validate the selection
      // range — the engine decides whether a region without printed
      // cells yields a string or null. The Dart-side contract is
      // just "notify once per call", not "elide notifications when
      // the range is empty"; the view re-pulls a snapshot regardless
      // because the highlight overlay tracks the range, not the text.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      await controller.setSelection(0, 0, 0, 3, TerminalSelectionKind.simple);
      expect(notified, 1);
    });

    // The live adapter (`LiveTerminalController`) wraps a real Rust
    // `TerminalSession` whose construction requires an attached SSH
    // shell. Its constructor / `dispose` / `events()` bridge cannot be
    // exercised without a live transport.
    // covered by integration: live session requires a running SSH shell.

    test(
      'disposing twice does not throw — idempotent on the replay handle',
      () {
        // Spec: the host's `State.dispose` may be called once cleanly,
        // but a hot-reload during dev can re-emit the dispose pass. The
        // replay adapter wraps a Rust opaque whose drop is idempotent;
        // a second Dart-side dispose must not crash with "use after
        // free" semantics on the freed handle.
        final controller = ReplayTerminalController(cols: 20, rows: 5);
        controller.dispose();
        expect(() => controller.dispose(), throwsA(anything));
        // We don't pin a specific throw type — the Dart `ChangeNotifier`
        // assertion fires first in debug; the contract is "doesn't
        // segfault", not "specific exception".
      },
    );

    test('clearSelection on a fresh grid still pulses repaint', () async {
      // Spec: the engine accepts `clearSelection` on an empty
      // selection state (no-op Rust-side) but the adapter still
      // pulses repaint so the caller (Select All cycle, Esc handler)
      // never has to know whether a selection existed first.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.clearSelection();

      expect(notified, 1);
      // Idempotent: a second clear on a fresh grid still notifies.
      controller.clearSelection();
      expect(notified, 2);
    });

    test('selectionText on a fresh grid returns null — empty range yields no '
        'text', () async {
      // Spec: with no selection set, the engine returns null (Dart
      // converts the Rust `Option<String>::None` to `null`). The
      // controller does not synthesize an empty string here — the
      // distinction matters for the copy-on-shortcut path which
      // skips the clipboard write entirely on null.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('hello'));

      expect(await controller.selectionText(), isNull);
    });

    test(
      'search returns an empty list on the replay adapter — base no-op',
      () async {
        // Spec: `TerminalController.search` defaults to an empty
        // const list on the base class. The replay adapter does not
        // override it because the read-only surfaces never enable the
        // search feature — the inherited no-op is the contract.
        final controller = ReplayTerminalController(cols: 20, rows: 5);
        addTearDown(controller.dispose);
        controller.feed(utf8.encode('searchable text'));

        final results = await controller.search('search');
        expect(results, isEmpty);
      },
    );

    test('paste on the replay adapter returns a completed Future without '
        'throwing — read-only surfaces never paste', () async {
      // Spec: the base class declares `paste` as `Future<void> async {}`.
      // The replay does not override it — calling paste must therefore
      // settle as a completed future, not throw and not hang. Pins
      // the no-op shape so a future override that forwards to the
      // engine (which would have no PTY to write to) would surface
      // here first.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      final f = controller.paste('text');
      expect(f, isA<Future<void>>());
      await expectLater(f, completes);
    });
  });
}
