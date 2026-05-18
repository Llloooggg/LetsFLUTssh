import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../widgets/app_dialog.dart';
import '../terminal/cursor_overlay.dart';
import 'recording_reader.dart';

/// Modal that replays a recording into a read-only xterm widget at
/// a user-selectable speed (0.5× / 1× / 2× / 4× / instant) with a
/// fully-functional scrub bar.
///
/// **Why pre-decode + Timer-driven playback.** Earlier shape was a
/// `Stream.listen` with `await Future.delayed` between frames — each
/// asciinema event went through a microtask + a delayed Future. For
/// dense recordings (htop refresh = dozens of ANSI frames clustered
/// inside 100 ms) every frame paid a microtask + a `Future.delayed`
/// rounding-loss penalty, and the renderer painted between every
/// event. Visually that surfaces as choppy / jerky playback.
///
/// The new shape loads the full event list once on dialog open,
/// then drives the screen off a single 60 Hz `Timer.periodic`. Each
/// tick advances a virtual position by `wall_elapsed × speed` and
/// applies every event whose timestamp crossed under the new
/// position. Renders coalesce on the single tick boundary — xterm
/// gets a tight burst of writes per tick, paints once.
///
/// **Scrub correctness.** asciinema events are ANSI deltas: a
/// "move cursor to row 5, write 'CPU: 12%'" frame at second 30 has
/// no value without the preceding frames that put the cursor +
/// screen state in the right place. Seek-via-sidecar (the previous
/// scrub path) jumped the byte cursor mid-stream and rendered
/// garbage for htop-style recordings. The new scrub clears the
/// terminal and re-applies every event from `t=0` up to the target
/// in one tight synchronous loop — no microtask between events,
/// xterm only paints when the next Flutter frame ticks. The user
/// sees a single transition, not a fast-scroll-from-beginning.
///
/// **Why a custom replay loop, not asciinema's player package.**
/// Their package is built on package:web — it injects a `<canvas>`
/// inside an iframe and is not portable to Flutter desktop / mobile.
/// Re-implementing the loop ourselves over xterm keeps the same
/// rendering stack the rest of the app uses.
class RecordingPlaybackDialog extends StatefulWidget {
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
  State<RecordingPlaybackDialog> createState() =>
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

class _RecordingPlaybackDialogState extends State<RecordingPlaybackDialog> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;

  /// Replay speed multiplier. `null` means "instant" — jump straight
  /// to the final frame so the user lands at the recording's last
  /// rendered state immediately.
  double? _speed = 1.0;

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
    final w = widget.meta?.header.width ?? 80;
    final h = widget.meta?.header.height ?? 24;
    _terminal = Terminal(maxLines: 10000);
    _terminal.resize(w, h);
    _terminalController = TerminalController();
    _totalMs = ((widget.meta?.durationSeconds ?? 0) * 1000).round();
    _loadAll();
  }

  /// Drain the recording's decoded-line stream once into the
  /// in-memory event list. Header line skipped via the same
  /// `decodeHeaderLine` predicate the live pump used; malformed
  /// records skipped silently. Errors land on `_error`; the user
  /// sees the localized message inline.
  Future<void> _loadAll() async {
    final stream = RecordingReader.open(widget.filePath);
    final collected = <_Event>[];
    var sawHeader = false;
    try {
      await for (final line in stream) {
        if (_disposed) return;
        if (!sawHeader) {
          sawHeader = true;
          if (decodeHeaderLine(line.value) != null) continue;
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
  /// window. No-op when paused (instant speed) or scrubbing.
  void _tick() {
    if (_disposed) return;
    final now = DateTime.now();
    if (_scrubbing || _speed == null) {
      _lastTickAt = now;
      return;
    }
    final elapsedMs = _lastTickAt == null
        ? 16
        : now.difference(_lastTickAt!).inMilliseconds.clamp(0, 250);
    _lastTickAt = now;
    final newPosMs = _positionMs + (elapsedMs * _speed!).round();
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
  /// at or below `targetMs`. Hot path — kept tight with no
  /// allocations + a single `Terminal.write` per output event.
  void _applyEventsTo(int targetMs) {
    final targetSec = targetMs / 1000.0;
    while (_cursor < _events.length &&
        _events[_cursor].timestamp <= targetSec) {
      final e = _events[_cursor];
      if (e.direction == 'o') _terminal.write(e.data);
      _cursor++;
    }
  }

  /// Scrub to `targetMs`. Always rebuilds terminal state from
  /// `t=0` so ANSI deltas land on the correct cursor / screen
  /// positions — htop's "redraw row 5" only makes sense if the
  /// preceding row-setup frames already ran.
  ///
  /// Synchronous: `_applyEventsTo` runs inside a tight `while` with
  /// no Future / Timer yields, so xterm accumulates writes and the
  /// next Flutter frame paints a single transition. The user does
  /// not see a fast-scroll-from-beginning even on recordings with
  /// thousands of events before the target.
  void _jumpTo(int targetMs) {
    if (_loading || _disposed) return;
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);
    _cursor = 0;
    _applyEventsTo(targetMs);
    setState(() => _positionMs = targetMs.clamp(0, _totalMs));
    _lastTickAt = DateTime.now();
    if (_ticker == null || !_ticker!.isActive) _startTicker();
  }

  void _setSpeed(double? speed) {
    setState(() => _speed = speed);
    if (speed == null) {
      // Instant — jump to the recording's end so the user lands on
      // the final rendered state in one transition.
      _jumpTo(_totalMs);
      return;
    }
    _lastTickAt = DateTime.now();
    if (_ticker == null || !_ticker!.isActive) _startTicker();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final w = widget.meta?.header.width ?? 80;
    final h = widget.meta?.header.height ?? 24;
    final fontSize = AppFonts.sm;
    return AppDialog(
      title: l10n.recordingPlaybackTitle,
      // Wide enough to seat a 132-col recording at the current
      // font; AppDialog clamps to `viewport - 48 px` so the upper
      // bound is the screen, not this number.
      maxWidth: (w * fontSize * 0.62).clamp(480.0, 1600.0),
      scrollable: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSpeedRow(l10n),
          const SizedBox(height: AppSpacing.sm),
          _buildScrubRow(l10n),
          const SizedBox(height: AppSpacing.md),
          // Terminal flexes so the dialog never overflows on
          // short viewports — the recording's nominal row count
          // is the preferred height, not a hard floor.
          Flexible(fit: FlexFit.loose, child: _buildTerminal(h, fontSize)),
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

  Widget _buildSpeedRow(S l10n) {
    return Row(
      children: [
        Text(
          l10n.recordingSpeed,
          style: TextStyle(
            color: AppTheme.fgFaint,
            fontFamily: AppFonts.interFamily,
            fontSize: AppFonts.xs,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButton<double?>(
          value: _speed,
          items: [
            const DropdownMenuItem(value: 0.5, child: Text('0.5×')),
            const DropdownMenuItem(value: 1.0, child: Text('1×')),
            const DropdownMenuItem(value: 2.0, child: Text('2×')),
            const DropdownMenuItem(value: 4.0, child: Text('4×')),
            DropdownMenuItem(
              value: null,
              child: Text(l10n.recordingSpeedInstant),
            ),
          ],
          onChanged: _loading ? null : _setSpeed,
        ),
      ],
    );
  }

  Widget _buildScrubRow(S l10n) {
    // Slider stays enabled as long as we've loaded the event list
    // — no sidecar dependency anymore (scrub re-applies from t=0
    // synchronously, so terminal state is always correct). The
    // previous "disabled scrub bar" branch retires with the
    // sidecar-driven seek.
    final available = !_loading && _events.isNotEmpty && _totalMs > 0;
    final maxValue = _totalMs > 0 ? _totalMs.toDouble() : 1.0;
    final value = _positionMs.clamp(0, _totalMs > 0 ? _totalMs : 0).toDouble();
    final positionLabel = l10n.recordingScrubPositionLabel(
      _formatDuration(_positionMs),
      _formatDuration(_totalMs),
    );
    return Row(
      children: [
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

  Widget _buildTerminal(int h, double fontSize) {
    // The recording's nominal row count + a generous cap. Tight
    // viewports still squeeze via the surrounding `Flexible`.
    final preferred = h * fontSize * kTerminalLineHeight;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderLight),
        borderRadius: AppTheme.radiusSm,
      ),
      child: SizedBox(
        height: preferred.clamp(200.0, 900.0),
        child: TerminalView(
          _terminal,
          controller: _terminalController,
          autofocus: false,
          hardwareKeyboardOnly: false,
          backgroundOpacity: 1.0,
          padding: const EdgeInsets.all(AppSpacing.xs),
          textStyle: TerminalStyle(
            fontSize: fontSize,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
          ),
        ),
      ),
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
