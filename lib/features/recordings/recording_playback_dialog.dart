import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_popup_select.dart';
import '../../widgets/terminal/readonly_terminal_grid_view.dart';
import '../../widgets/terminal/terminal_cell_metrics.dart';
import 'recording_reader.dart';

/// Modal that replays a recording into a read-only terminal at
/// a user-selectable speed (0.5× / 1× / 2× / 4×) with a
/// fully-functional scrub bar.
///
/// **Why pre-decode + Timer-driven playback.** A `Stream.listen` with
/// `await Future.delayed` between frames put each asciinema event through a
/// microtask + a delayed Future. For dense recordings (htop refresh = dozens
/// of ANSI frames clustered inside 100 ms) every frame paid a microtask + a
/// `Future.delayed` rounding-loss penalty, and the renderer painted between
/// every event — choppy / jerky playback.
///
/// The shape used here loads the full event list once on dialog open, then
/// drives the screen off a single 60 Hz `Timer.periodic`. Each tick advances
/// a virtual position by `wall_elapsed × speed` and applies every event whose
/// timestamp crossed under the new position. Renders coalesce on the single
/// tick boundary — the engine gets a tight burst of feeds per tick and the
/// controller fires one repaint.
///
/// **Scrub correctness.** asciinema events are ANSI deltas: a
/// "move cursor to row 5, write 'CPU: 12%'" frame at second 30 has
/// no value without the preceding frames that put the cursor +
/// screen state in the right place. Seek-via-sidecar (a byte-cursor jump
/// mid-stream) rendered garbage for htop-style recordings. The scrub here
/// clears the engine and re-feeds every event from `t=0` up to the target in
/// one tight synchronous loop — the controller fires one repaint at the end.
/// The user sees a single transition, not a fast-scroll-from-beginning.
///
/// **Why a custom replay loop, not asciinema's player package.**
/// Their package is built on package:web — it injects a `<canvas>`
/// inside an iframe and is not portable to Flutter desktop / mobile.
/// Re-implementing the loop ourselves over the Rust terminal engine keeps the
/// same rendering stack the rest of the app uses.
class RecordingPlaybackDialog extends ConsumerStatefulWidget {
  final String filePath;
  final bool encrypted;
  final RecordingMeta? meta;

  const RecordingPlaybackDialog({
    super.key,
    required this.filePath,
    required this.encrypted,
    required this.meta,
  });

  static Future<void> show(
    BuildContext context, {
    required String filePath,
    required bool encrypted,
    required RecordingMeta? meta,
  }) {
    return AppDialog.show<void>(
      context,
      builder: (_) => RecordingPlaybackDialog(
        filePath: filePath,
        encrypted: encrypted,
        meta: meta,
      ),
    );
  }

  @override
  ConsumerState<RecordingPlaybackDialog> createState() =>
      _RecordingPlaybackDialogState();
}

/// One asciinema event extracted from the decoded stream. Held in
/// memory as a flat triple so the playback tick's hot loop walks
/// the list without intermediate object construction.
class _Event {
  final double timestamp;
  final String direction;
  final String data;
  const _Event(this.timestamp, this.direction, this.data);
}

class _RecordingPlaybackDialogState
    extends ConsumerState<RecordingPlaybackDialog> {
  /// Playback's preferred font as a multiple of the user's configured
  /// terminal font (`configProvider.fontSize`). Above `1.0` so the
  /// replay reads larger than the live terminal — recordings are
  /// reviewed, not typed into, so a roomier grid is easier to scan.
  /// The auto-fit in `_resolveFontSize` only shrinks below this when
  /// the recorded grid would overflow the dialog (a tall curses
  /// capture on a short screen).
  static const double _fontScale = 1.25;

  /// Floor for the auto-fit font. An extreme grid in a tiny viewport
  /// overflows rather than shrinking past readability.
  static const double _minFontSize = 6.0;

  /// Guard pixel added to the grid's pixel size so the renderer's integer
  /// `viewport ~/ cellSize` row / col count cannot truncate to one
  /// less than the recorded `w × h` on a sub-pixel float rounding.
  /// One pixel is far below a cell, so it never seats an extra cell.
  static const double _cellGuard = 1.0;

  /// RIS — `ESC c`, full terminal reset. Fed before a scrub rebuild from
  /// `t=0` so alt-screen / scroll-region / character-attribute modes from
  /// the prior position cannot bleed in: a plain grid clear blanks cells but
  /// leaves those modes alive, and the next ANSI line then lands at the wrong
  /// column / colour (ghost characters on htop / vim recordings). RIS resets
  /// the screen AND the modes in one sequence.
  static const _ris = '\x1Bc';

  /// Drives the shell-less Rust terminal engine the playback feeds into.
  /// A scrub re-feeds from `t=0` after a [_ris] reset rather than rebuilding
  /// the engine.
  late final ReadOnlyTerminalController _controller;
  int _terminalCols = 80;
  int _terminalRows = 24;

  /// Replay speed multiplier applied to wall-clock elapsed time on
  /// each tick.
  double _speed = 1.0;

  /// Whether playback is paused. The tick stays scheduled but the
  /// "advance virtual time" branch short-circuits, so toggling on
  /// resumes from the exact `_positionMs` the pause landed on
  /// without re-applying any events. Defaults to `false` so the
  /// recording auto-plays on open; user can pause at any point.
  bool _paused = false;

  bool _disposed = false;
  bool _loading = true;
  String? _error;

  /// Pre-decoded event list. Loaded once in `initState` via the
  /// existing stream API; populated before the user can interact
  /// with the playback controls so every replay / scrub action runs
  /// off the in-memory list, not a fresh disk decode.
  List<_Event> _events = const [];

  /// Index of the next event to apply on the next tick. Reset to 0
  /// on scrub so `_applyEventsTo` reconstructs terminal state from
  /// the beginning.
  int _cursor = 0;

  /// Virtual playback position in milliseconds. Drives the scrub
  /// bar's thumb + the "should this event have fired by now?"
  /// check inside `_applyEventsTo`.
  int _positionMs = 0;

  /// Total recording duration in milliseconds. Computed from
  /// `RecordingMeta.durationSeconds` when present; on the fallback
  /// path (`durationSeconds == 0`) we infer it from the last
  /// event's timestamp once the full list is loaded.
  int _totalMs = 0;

  /// True while the user holds the scrub thumb. The tick is a
  /// no-op during this window; release fires `_jumpTo` against the
  /// released value.
  bool _scrubbing = false;

  /// 60 Hz tick that advances `_positionMs` and dispatches due
  /// events. Cancelled at dispose + when playback reaches the end.
  Timer? _ticker;

  /// Wall-clock timestamp of the last tick. The delta between two
  /// ticks is what we feed (scaled by `_speed`) into the virtual
  /// cursor — making the playback rate independent of jitter in
  /// `Timer.periodic`'s real cadence.
  DateTime? _lastTickAt;

  @override
  void initState() {
    super.initState();
    _terminalCols = widget.meta?.header.width ?? 80;
    _terminalRows = widget.meta?.header.height ?? 24;
    _controller = ReadOnlyTerminalController(
      cols: _terminalCols,
      rows: _terminalRows,
    );
    _totalMs = ((widget.meta?.durationSeconds ?? 0) * 1000).round();
    _loadAll();
  }

  /// Drain the recording's decoded-line stream once into the
  /// in-memory event list. The first line is the asciinema-v2
  /// header — we extract its width / height + resize the terminal
  /// to match, then skip it as not-an-event. Subsequent malformed
  /// records skip silently. Errors land on `_error`; the user
  /// sees the localized message inline.
  ///
  /// Resizing here (not just from `widget.meta`) covers the case
  /// where the pre-loaded `RecordingMeta` is null / missing dims —
  /// `widget.meta` is read via `RecordingReader.readMeta` which is
  /// best-effort. Resizing inside `_loadAll` reads the canonical
  /// dims off the first line of the recording itself; htop / vim /
  /// any curses workload then writes its ANSI cursor-position
  /// sequences against the same column count it was originally
  /// rendered at, so a "col 132 write" lands at col 132 instead of
  /// wrapping back onto column 0 of the next line.
  Future<void> _loadAll() async {
    final stream = RecordingReader.open(widget.filePath);
    final collected = <_Event>[];
    var sawHeader = false;
    try {
      await for (final line in stream) {
        if (_disposed) return;
        if (!sawHeader) {
          sawHeader = true;
          final header = decodeHeaderLine(line.value);
          if (header != null) {
            // Resize the terminal off the recording's authoritative
            // dims. The header is always the first line of an
            // asciinema-v2 stream; a recording that has no header
            // line stays on the `widget.meta` defaults and inherits
            // the wrap-on-col-80 problem the comment above
            // describes, but at least the rest of the playback
            // path keeps working.
            _terminalCols = header.width;
            _terminalRows = header.height;
            _controller.resize(_terminalCols, _terminalRows);
            continue;
          }
        }
        final frame = decodeEventLine(line.value);
        if (frame == null) continue;
        collected.add(_Event(frame.timestamp, frame.direction, frame.data));
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'Recording load failed',
        name: 'Recording',
        error: e,
        stackTrace: st,
      );
      if (mounted) setState(() => _error = e.toString());
      return;
    }
    if (!mounted) return;
    setState(() {
      _events = collected;
      _loading = false;
      if (_totalMs == 0 && collected.isNotEmpty) {
        // Fallback for recordings with no `durationSeconds` in the
        // meta — the last event's timestamp is the authoritative
        // upper bound for the scrub bar.
        _totalMs = (collected.last.timestamp * 1000).round();
      }
    });
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _lastTickAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  /// 60 Hz tick. Reads wall-clock delta since the previous tick,
  /// scales by `_speed`, advances the virtual position, and
  /// dispatches every event whose timestamp falls in the new
  /// window. No-op when paused or scrubbing.
  void _tick() {
    if (_disposed) return;
    final now = DateTime.now();
    if (_scrubbing || _paused) {
      // Reset the elapsed anchor so resume after pause does not
      // pay back the paused window in one big jump.
      _lastTickAt = now;
      return;
    }
    final elapsedMs = _lastTickAt == null
        ? 16
        : now.difference(_lastTickAt!).inMilliseconds.clamp(0, 250);
    _lastTickAt = now;
    final newPosMs = _positionMs + (elapsedMs * _speed).round();
    _applyEventsTo(newPosMs);
    if (_cursor >= _events.length) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (mounted) {
      setState(() => _positionMs = newPosMs.clamp(0, _totalMs));
    }
  }

  /// Apply every event from `_cursor` onwards whose timestamp lies
  /// at or below `targetMs`. Hot path — the due output events are
  /// concatenated and fed in one engine call so the controller fires a
  /// single repaint per tick rather than one per event.
  void _applyEventsTo(int targetMs) {
    final targetSec = targetMs / 1000.0;
    final buf = StringBuffer();
    while (_cursor < _events.length &&
        _events[_cursor].timestamp <= targetSec) {
      final e = _events[_cursor];
      if (e.direction == 'o') buf.write(e.data);
      _cursor++;
    }
    if (buf.isNotEmpty) _controller.feed(utf8.encode(buf.toString()));
  }

  /// Scrub to `targetMs`. Always rebuilds terminal state from
  /// `t=0` so ANSI deltas land on the correct cursor / screen
  /// positions — htop's "redraw row 5" only makes sense if the
  /// preceding row-setup frames already ran.
  ///
  /// Synchronous: `_applyEventsTo` concatenates the due events and feeds the
  /// engine once, so the controller fires a single repaint and the next
  /// Flutter frame paints one transition. The user does not see a
  /// fast-scroll-from-beginning even on recordings with thousands of events
  /// before the target.
  void _jumpTo(int targetMs) {
    if (_loading || _disposed) return;
    // Feed RIS to reset the engine to a pristine state so alt-screen /
    // scroll-region / character-attribute modes from the previous position
    // cannot bleed into the rebuild from t=0. A plain grid clear blanks cells
    // but leaves those modes alive, and htop / vim recordings then render
    // ghost characters on lines re-written under the wrong mode.
    _controller.feed(utf8.encode(_ris));
    _cursor = 0;
    _applyEventsTo(targetMs);
    setState(() => _positionMs = targetMs.clamp(0, _totalMs));
    _lastTickAt = DateTime.now();
    if (_ticker == null || !_ticker!.isActive) _startTicker();
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _lastTickAt = DateTime.now();
    if (_ticker == null || !_ticker!.isActive) _startTicker();
  }

  /// Toggle play / pause. When pausing, the tick stays scheduled
  /// (we keep `_ticker` alive so resume is cheap), it just no-ops
  /// inside `_tick`. When resuming, reset `_lastTickAt` so the
  /// elapsed window the next tick reads starts at "now", not at
  /// "the moment we paused" — otherwise the first post-resume tick
  /// would burn through the paused interval in one big jump.
  void _togglePause() {
    if (_loading || _events.isEmpty) return;
    setState(() => _paused = !_paused);
    if (!_paused) {
      _lastTickAt = DateTime.now();
      if (_ticker == null || !_ticker!.isActive) _startTicker();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    // Authoritative grid dims come from the recording's own header,
    // which `_loadAll` decodes and stores in `_terminalCols/Rows`
    // (seeded from `widget.meta` in `initState`). Reading those — not
    // `widget.meta` directly — keeps the SizedBox aligned with the
    // engine's grid size even when meta is missing.
    final w = _terminalCols;
    final h = _terminalRows;
    // Match the grid view's cell measurement, which scales by the OS text
    // scale (`measureMonoCell`); measuring unscaled here would clip the
    // bottom row whenever the system text scale is above 1.0.
    final textScaler = MediaQuery.textScalerOf(context);
    final settingsFontSize = ref.watch(
      configProvider.select((c) => c.fontSize),
    );
    final desiredFont = settingsFontSize * _fontScale;
    // Request enough width to seat `w` cols at the desired font plus
    // the dialog's content padding; AppDialog clamps to
    // `viewport - 48 px`, and `_buildTerminal`'s LayoutBuilder
    // shrinks the font further if the clamped width is tighter.
    final maxWidth =
        (w *
                    measureMonoCell(
                      fontSize: desiredFont,
                      textScaler: textScaler,
                    ).width +
                AppSpacing.xs * 2.0 +
                AppSpacing.lg * 2)
            .clamp(560.0, 2400.0);
    return AppDialog(
      title: l10n.recordingPlaybackTitle,
      maxWidth: maxWidth,
      scrollable: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildControlsRow(l10n),
          const SizedBox(height: AppSpacing.sm),
          // Terminal flexes so the dialog never overflows on
          // short viewports — the recording's nominal row count
          // is the preferred height, not a hard floor.
          Flexible(
            fit: FlexFit.loose,
            child: _buildTerminal(w, h, settingsFontSize, textScaler),
          ),
          if (_loading) ...[
            const SizedBox(height: AppSpacing.sm),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: AppTheme.red, fontSize: AppFonts.xs),
            ),
          ],
        ],
      ),
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
    );
  }

  /// Single controls strip: pause / play, speed picker, scrub
  /// slider, and the position read-out on one row. Folding the former
  /// two-row layout into one frees the vertical space for the terminal
  /// panel below.
  Widget _buildControlsRow(S l10n) {
    // Pause toggle gates on `!_loading && _events.isNotEmpty` — a
    // pre-load tap is meaningless and an empty recording (no events
    // past the header) cannot be paused.
    final canTogglePause = !_loading && _events.isNotEmpty;
    // Slider stays enabled once the event list is loaded — scrub
    // re-applies from t=0 synchronously, so terminal state is always
    // correct regardless of recording age.
    final available = !_loading && _events.isNotEmpty && _totalMs > 0;
    final maxValue = _totalMs > 0 ? _totalMs.toDouble() : 1.0;
    final value = _positionMs.clamp(0, _totalMs > 0 ? _totalMs : 0).toDouble();
    final positionLabel = l10n.recordingScrubPositionLabel(
      _formatDuration(_positionMs),
      _formatDuration(_totalMs),
    );
    return Row(
      children: [
        Tooltip(
          message: _paused ? l10n.playRecording : l10n.playbackPause,
          child: IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 20),
            onPressed: canTogglePause ? _togglePause : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Shared no-animation picker (`AppPopupSelect`) — matches the
        // project-wide hard-off on dropdown open animations that the
        // settings pickers already use.
        AppPopupSelect<double>(
          value: _speed,
          menuMinWidth: 96,
          onChanged: _setSpeed,
          options: const [
            AppPopupSelectOption(value: 0.5, label: '0.5×'),
            AppPopupSelectOption(value: 1.0, label: '1×'),
            AppPopupSelectOption(value: 2.0, label: '2×'),
            AppPopupSelectOption(value: 4.0, label: '4×'),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Slider(
            min: 0,
            max: maxValue,
            value: value.clamp(0, maxValue),
            onChanged: available
                ? (v) {
                    setState(() {
                      _scrubbing = true;
                      _positionMs = v.round();
                    });
                  }
                : null,
            onChangeEnd: available
                ? (v) {
                    _scrubbing = false;
                    _jumpTo(v.round());
                  }
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          positionLabel,
          style: TextStyle(
            color: AppTheme.fgFaint,
            fontFamily: AppFonts.interFamily,
            fontSize: AppFonts.xs,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminal(
    int w,
    int h,
    double settingsFontSize,
    TextScaler textScaler,
  ) {
    // Render the engine through the read-only grid view — the same painter
    // the live desktop pane uses. The whole recorded grid renders at its
    // natural pixel size with no surrounding scroll view: `_resolveFontSize`
    // picks the largest font (capped at the user's terminal font) at which
    // `w × h` cells fit the dialog. The engine is fixed at the recorded
    // `w × h` (no `reportResize`), so htop / curses recordings keep their
    // fixed header + footer rows aligned to the recorded scroll region.
    final desired = settingsFontSize * _fontScale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = _resolveFontSize(
          w,
          h,
          desired,
          constraints,
          textScaler,
        );
        // Cell metrics come from a `TextPainter` against the same mono
        // stack — and the same OS text scale — the grid view measures with
        // (`measureMonoCell`), so the SizedBox math matches the renderer's
        // own layout; a sub-cell drift would clip the right / bottom edge.
        final cell = measureMonoCell(
          fontSize: fontSize,
          textScaler: textScaler,
        );
        // `AppTerminalView.padding` on all four sides is the grid view's
        // inner padding — the SizedBox must add the same so `w × h` cells fit.
        const innerPad = AppSpacing.xs * 2.0;
        // `+ _cellGuard` keeps the integer `~/ cellSize` row / col count from
        // truncating to `h-1` / `w-1` on a sub-pixel float rounding; one
        // extra guard pixel never seats another cell.
        final terminalWidth = w * cell.width + innerPad + _cellGuard;
        final terminalHeight = h * cell.height + innerPad + _cellGuard;
        // `heightFactor: 1` hugs the grid height so a recording
        // smaller than the viewport keeps the dialog compact;
        // `topCenter` centres the fixed-width grid horizontally.
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1.0,
          child: Container(
            // Border via `foregroundDecoration` so it paints over the grid
            // edge instead of insetting the child — an inset would shrink
            // the render box below `w × h` cells.
            decoration: const BoxDecoration(borderRadius: AppTheme.radiusSm),
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderLight),
              borderRadius: AppTheme.radiusSm,
            ),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: terminalWidth,
              height: terminalHeight,
              child: ReadOnlyTerminalGridView(
                controller: _controller,
                fontSize: fontSize,
                selectable: true,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Largest font at which the recording's `w × h` grid fits inside
  /// [constraints], capped at [desired] (the user's terminal font)
  /// and floored at [_minFontSize]. Cell size is linear in font size,
  /// so the fit font is the desired font scaled by the tighter of the
  /// width / height overflow ratios. [textScaler] keeps the cell
  /// measurement in step with the OS text scale the grid view renders with.
  double _resolveFontSize(
    int w,
    int h,
    double desired,
    BoxConstraints c,
    TextScaler textScaler,
  ) {
    final cell = measureMonoCell(fontSize: desired, textScaler: textScaler);
    const innerPad = AppSpacing.xs * 2.0;
    return playbackFitFontSize(
      desiredFontSize: desired,
      neededWidth: w * cell.width + innerPad + _cellGuard,
      neededHeight: h * cell.height + innerPad + _cellGuard,
      maxWidth: c.maxWidth,
      maxHeight: c.maxHeight,
      innerPad: innerPad + _cellGuard,
      minFontSize: _minFontSize,
    );
  }

  /// Format `ms` as `mm:ss`. Hours roll into the minutes field
  /// (`62:30` not `01:02:30`) — a multi-hour single recording is rare
  /// enough that the wider format would waste pixels in the common
  /// case. Negative values clamp to zero.
  String _formatDuration(int ms) {
    final clamped = ms < 0 ? 0 : ms;
    final totalSeconds = clamped ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Largest font at which a grid needing [neededWidth] × [neededHeight]
/// pixels (already including [innerPad]) fits a [maxWidth] × [maxHeight]
/// viewport, capped at [desiredFontSize] and floored at [minFontSize].
///
/// The cell size is linear in font size, so once the grid overflows
/// an axis the fit font is the desired font scaled by that axis's
/// overflow ratio — the constant [innerPad] is excluded from the scale
/// because the terminal padding does not grow with the font. The
/// tighter of the two axes wins. Infinite (unbounded) constraints leave
/// the desired font untouched. Pure arithmetic, extracted from the
/// dialog so the fit logic is unit-testable without the engine.
double playbackFitFontSize({
  required double desiredFontSize,
  required double neededWidth,
  required double neededHeight,
  required double maxWidth,
  required double maxHeight,
  required double innerPad,
  required double minFontSize,
}) {
  var fs = desiredFontSize;
  if (maxWidth.isFinite && neededWidth > maxWidth) {
    fs = desiredFontSize * (maxWidth - innerPad) / (neededWidth - innerPad);
  }
  if (maxHeight.isFinite && neededHeight > maxHeight) {
    final fitH =
        desiredFontSize * (maxHeight - innerPad) / (neededHeight - innerPad);
    if (fitH < fs) fs = fitH;
  }
  return fs < minFontSize ? minFontSize : fs;
}
