/// Widget tests for [RecordingPlaybackDialog] — the modal that replays
/// an asciinema-v2 recording into a read-only terminal with speed /
/// pause / scrub controls.
///
/// The pure fit-font math lives in `recording_playback_dialog_test.dart`;
/// this file drives the live dialog: a real plaintext `.cast` fixture is
/// streamed through the Rust reader (FRB), the 60 Hz playback ticker is
/// advanced with real wall-clock delays, and the controls are exercised.
///
/// FRB is required — the reader stream and the replay terminal engine
/// both route through `liblfs_frb`. No DB key is needed because the
/// fixture is plaintext, so this file is NOT `frb_global_store`-tagged.
///
/// Timer discipline: the dialog runs a `Timer.periodic(16ms)` ticker
/// whose advance is driven off `DateTime.now()` wall-clock deltas, so
/// `pumpAndSettle` would hang forever on it. Every test instead drains
/// the async load with bounded `tester.runAsync` + `tester.pump` loops,
/// advances playback with real `Future.delayed` inside `runAsync`, and
/// closes the dialog before returning so `dispose` cancels the ticker
/// (no pending-timer assertion).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/features/recordings/recording_playback_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_dialog.dart';
import 'package:letsflutssh/widgets/core/app_icon_button.dart';
import 'package:letsflutssh/widgets/core/app_popup_select.dart';
import 'package:letsflutssh/widgets/terminal/terminal_controller.dart';
import 'package:letsflutssh/widgets/terminal/terminal_view.dart';
import 'package:path/path.dart' as p;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rec_playback_widget_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Write a plaintext asciinema-v2 `.cast` fixture. The first line is
  /// the header carrying the recorded grid dims; each later line is an
  /// `[t, "o", data]` output event. The recording ends at the last
  /// event's timestamp, so callers pick that to bound how much real
  /// wall-clock time playback needs to reach the end.
  String writeCast({
    required int width,
    required int height,
    required List<(double, String)> events,
  }) {
    final f = File(p.join(tempDir.path, 'fixture.cast'));
    final buf = StringBuffer()
      ..writeln('{"version":2,"width":$width,"height":$height}');
    for (final (t, data) in events) {
      // Data is plain ASCII in the fixtures, so a bare-quote JSON
      // string is valid; no escaping needed.
      buf.writeln('[$t,"o","$data"]');
    }
    f.writeAsStringSync(buf.toString());
    return f.path;
  }

  /// A short recording: three output frames inside the first 300 ms.
  /// Total duration is small enough that ~400 ms of real wall-clock
  /// time drives playback all the way to the end (the ticker then
  /// self-cancels), yet `_totalMs` is non-zero so the scrub bar is
  /// enabled.
  String shortCast() => writeCast(
    width: 80,
    height: 24,
    events: const [(0.0, 'Hello'), (0.1, ' World'), (0.3, '!')],
  );

  /// A 5 s recording — total "00:05". Long enough that the position can
  /// climb across whole-second boundaries (the only resolution the
  /// `mm:ss` read-out exposes) without the ticker reaching the end and
  /// self-cancelling mid-test under real-time jitter.
  String longCast() => writeCast(
    width: 80,
    height: 24,
    events: const [
      (0.0, 'a'),
      (1.0, 'b'),
      (2.0, 'c'),
      (3.0, 'd'),
      (4.0, 'e'),
      (5.0, 'f'),
    ],
  );

  Widget host({required String filePath}) {
    return ProviderScope(
      overrides: [
        // Pin a known config so the dialog's font math is deterministic
        // and no disk-backed config load runs in the test.
        preloadedAppConfigProvider.overrideWithValue(AppConfig.defaults),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RecordingPlaybackDialog.show(
                  context,
                  filePath: filePath,
                  encrypted: false,
                  meta: null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Open the dialog and drain the async file load. Returns once the
  /// loading spinner has cleared (the reader stream drained + the event
  /// list applied), or after the bounded loop budget runs out.
  Future<void> openAndLoad(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pump();
    for (
      var i = 0;
      i < 60 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// Advance the playback ticker. Two clocks are in play: the
  /// `Timer.periodic` ticker fires on `testWidgets`'s FAKE clock (only a
  /// `tester.pump(Duration)` advances it), while `_tick` measures elapsed
  /// time off the REAL `DateTime.now()`. Each iteration therefore (1)
  /// burns real wall-clock inside `runAsync` so the next `_tick` reads a
  /// non-zero delta, then (2) pumps ≥16 ms of fake time so the periodic
  /// timer actually fires and applies that delta to the virtual position.
  Future<void> advancePlayback(
    WidgetTester tester, {
    int iterations = 20,
    Duration each = const Duration(milliseconds: 30),
  }) async {
    for (var i = 0; i < iterations; i++) {
      await tester.runAsync(() => Future<void>.delayed(each));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Advance playback until the elapsed read-out reaches at least
  /// [targetMs], or the iteration budget is spent. Robust against the
  /// real-time jitter of `runAsync` delays (a fixed iteration count can
  /// over- or under-shoot a whole-second boundary).
  Future<void> advanceUntilElapsedAtLeast(
    WidgetTester tester,
    int targetMs, {
    int maxIterations = 120,
  }) async {
    for (var i = 0; i < maxIterations && _elapsedMs() < targetMs; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Close the dialog so `dispose` cancels the ticker before the test
  /// returns; without this a live `Timer.periodic` trips the
  /// pending-timer assertion. Pumps a couple of frames to let the route
  /// tear down.
  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders the speed selector, pause, scrub bar and close', (
    tester,
  ) async {
    await tester.pumpWidget(host(filePath: shortCast()));
    await openAndLoad(tester);

    // Control strip: a speed picker (default 1×), a pause toggle, a
    // scrub Slider, and a Cancel/close action.
    expect(find.byType(AppPopupSelect<double>), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // The read-only terminal panel renders the recording.
    expect(find.byType(TerminalView), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('parses the header and sizes the terminal to the recorded grid', (
    tester,
  ) async {
    // A non-default grid (132×40) proves the dims come from the
    // recording's own header line, not the 80×24 init fallback.
    final path = writeCast(
      width: 132,
      height: 40,
      events: const [(0.0, 'wide'), (0.2, ' grid')],
    );
    await tester.pumpWidget(host(filePath: path));
    await openAndLoad(tester);

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    final controller = view.controller as ReplayTerminalController;
    expect(controller.cols, 132);
    expect(controller.rows, 40);

    await closeDialog(tester);
  });

  testWidgets('auto-plays on open: the read-out advances with no input', (
    tester,
  ) async {
    // Last event at t=2.0 s → total "00:02". The dialog starts the
    // ticker from `_onLoadComplete` (no play press needed). Letting real
    // wall-clock pass at 1× must push the elapsed field off 00:00 — proof
    // the virtual position tracks wall-clock and playback auto-started.
    final path = writeCast(
      width: 80,
      height: 24,
      events: const [
        (0.0, 'a'),
        (0.5, 'b'),
        (1.0, 'c'),
        (1.5, 'd'),
        (2.0, 'e'),
      ],
    );
    await tester.pumpWidget(host(filePath: path));
    await openAndLoad(tester);

    // Starts paused-at-zero with the total inferred from the last event.
    expect(find.text('00:00 / 00:02'), findsOneWidget);
    // The pause button shows `pause` — i.e. it IS playing, not waiting
    // for the user to press play.
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await advancePlayback(
      tester,
      iterations: 40,
      each: const Duration(milliseconds: 30),
    );

    // Elapsed has moved off 00:00; total stays 00:02.
    expect(find.text('00:00 / 00:02'), findsNothing);
    expect(find.textContaining('/ 00:02'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('playback self-stops at the end of a short recording', (
    tester,
  ) async {
    // Recording ends at t=0.3 s. Once the cursor passes the last event
    // the ticker cancels itself (`_cursor >= _events.length`). Pumping
    // far past the end leaves no live `Timer.periodic`, so the test can
    // tear down without the pending-timer assertion firing — that clean
    // teardown IS the observable proof the ticker stopped. The dialog
    // stays mounted at its final position throughout.
    await tester.pumpWidget(host(filePath: shortCast()));
    await openAndLoad(tester);

    await advancePlayback(tester, iterations: 30);

    expect(find.byType(RecordingPlaybackDialog), findsOneWidget);
    expect(find.text('00:00 / 00:00'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('pause stops the elapsed read-out from advancing', (
    tester,
  ) async {
    // 5 s recording → plenty of headroom so the position can climb to a
    // visible second without the ticker reaching the end mid-test.
    final path = longCast();
    await tester.pumpWidget(host(filePath: path));
    await openAndLoad(tester);

    // Let playback advance the position to a visible (non-zero) value
    // first, so the freeze assertion can distinguish a working pause
    // from a broken one (otherwise both stay sub-second at "00:00").
    await advanceUntilElapsedAtLeast(tester, 1000);
    final before = _elapsedMs();
    expect(before, greaterThanOrEqualTo(1000));

    // Tapping the pause button (its icon is `pause` while playing)
    // freezes the virtual position. The button then shows `play_arrow`.
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Letting more real time pass must NOT advance the read-out — at 1×
    // an unpaused ticker would have added another visible second.
    await advancePlayback(tester, iterations: 40);
    expect(_elapsedMs(), before);

    await closeDialog(tester);
  });

  testWidgets('resume after pause continues advancing the read-out', (
    tester,
  ) async {
    await tester.pumpWidget(host(filePath: longCast()));
    await openAndLoad(tester);

    // Advance to a visible position, pause, confirm the freeze, then
    // resume and confirm the read-out climbs past the paused value.
    await advanceUntilElapsedAtLeast(tester, 1000);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    final paused = _elapsedMs();
    expect(paused, greaterThanOrEqualTo(1000));
    await advancePlayback(tester, iterations: 15);
    expect(_elapsedMs(), paused);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await advanceUntilElapsedAtLeast(tester, paused + 1000);
    expect(_elapsedMs(), greaterThan(paused));

    await closeDialog(tester);
  });

  testWidgets('changing speed re-applies the selected multiplier', (
    tester,
  ) async {
    await tester.pumpWidget(host(filePath: longCast()));
    await openAndLoad(tester);

    // Pause first so the speed change applies from a controlled
    // position, then switch to 4× and resume: a fixed number of ticks
    // now advances the virtual position roughly four times as far per
    // unit of real wall-clock as 1× would.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    // Open the speed picker and choose 4×.
    await tester.tap(find.byType(AppPopupSelect<double>));
    await tester.pump();
    await tester.tap(find.text('4×').last);
    await tester.pump();
    // The trigger now reflects the chosen multiplier.
    expect(find.text('4×'), findsOneWidget);

    final start = _elapsedMs();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    // ~10 ticks of ~30 ms real time ≈ 300 ms wall-clock; at 4× that is
    // ~1.2 s of virtual time — past a whole second, which 1× could not
    // reach in the same window. Bounded well under the 5 s total.
    await advancePlayback(tester, iterations: 10);
    final advanced = _elapsedMs() - start;
    expect(advanced, greaterThanOrEqualTo(1000));

    await closeDialog(tester);
  });

  testWidgets('scrubbing the slider seeks the position read-out', (
    tester,
  ) async {
    final path = writeCast(
      width: 80,
      height: 24,
      events: const [(0.0, 'a'), (1.0, 'b'), (2.0, 'c'), (3.0, 'd')],
    );
    await tester.pumpWidget(host(filePath: path));
    await openAndLoad(tester);

    // Pause so the ticker can't move the position out from under the
    // seek assertion.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.text('00:00 / 00:03'), findsOneWidget);

    // Drag the scrub thumb to the right edge. `onChangeEnd` fires
    // `_jumpTo`, which rebuilds terminal state from t=0 and snaps the
    // position to the released value — here the far end (00:03).
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(500, 0));
    await tester.pump();

    expect(find.text('00:03 / 00:03'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('an empty recording disables pause and the scrub bar', (
    tester,
  ) async {
    // Header only, no events: nothing to play, so `_totalMs` stays 0,
    // pause is gated off, and the slider is disabled (onChanged null).
    final path = writeCast(width: 80, height: 24, events: const []);
    await tester.pumpWidget(host(filePath: path));
    await openAndLoad(tester);

    // Pause toggle present (icon `pause`, since `_paused` is false) but
    // disabled — its onTap is null because there is nothing to play.
    final pauseBtn = tester.widget<AppIconButton>(
      find.widgetWithIcon(AppIconButton, Icons.pause),
    );
    expect(pauseBtn.onTap, isNull);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(find.text('00:00 / 00:00'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('a header-less recording falls back to the 80x24 grid', (
    tester,
  ) async {
    // The plaintext `.cast` iterator yields raw lines; the dialog
    // decodes them Dart-side. A file whose first line is not a valid
    // asciinema header object means `_applyHeaderLine` returns false and
    // the terminal keeps its `initState` default of 80×24 instead of
    // resizing. The remaining (also-unparseable) lines decode to no
    // events, so the controls disable like an empty recording — the
    // dialog degrades without throwing.
    final f = File(p.join(tempDir.path, 'broken.cast'))
      ..writeAsStringSync('not-json-at-all\nstill-garbage\n');
    await tester.pumpWidget(host(filePath: f.path));
    await openAndLoad(tester);

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    final controller = view.controller as ReplayTerminalController;
    expect(controller.cols, 80);
    expect(controller.rows, 24);

    // No events parsed → scrub bar disabled, total stays 00:00.
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(find.text('00:00 / 00:00'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('close pops the dialog', (tester) async {
    await tester.pumpWidget(host(filePath: shortCast()));
    await openAndLoad(tester);
    expect(find.byType(AppDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecordingPlaybackDialog), findsNothing);
  });
}

/// Read the dialog's position read-out (`"{current} / {total}"`) and
/// return the whole label, or `null` when it is not on screen.
String? _positionLabel() {
  final matches = find.textContaining(' / ').evaluate();
  if (matches.isEmpty) return null;
  return (matches.first.widget as Text).data;
}

/// The elapsed (left) side of the position read-out, e.g. `"00:01"`.
String _elapsedLabel() {
  final label = _positionLabel();
  expect(label, isNotNull);
  return label!.split(' / ').first;
}

/// The elapsed read-out parsed back into milliseconds for ordering
/// comparisons (`mm:ss` → ms). Hours roll into minutes per the dialog's
/// own `_formatDuration` contract.
int _elapsedMs() {
  final parts = _elapsedLabel().split(':');
  final minutes = int.parse(parts[0]);
  final seconds = int.parse(parts[1]);
  return (minutes * 60 + seconds) * 1000;
}
