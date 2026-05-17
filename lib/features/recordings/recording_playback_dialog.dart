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
/// a user-selectable speed (1× / 2× / 4× / instant) with a scrub bar.
///
/// **Scrub bar.** The recorder writes a fixed-width `<recording>.idx`
/// sidecar alongside every event. Each entry binds an event's byte
/// offset to its asciinema timestamp; the dialog binary-searches the
/// sidecar via [`RecordingReader.seek`] to translate the slider value
/// into a frame boundary, then restarts the FRB playback stream
/// pre-positioned at that offset. Recordings made before the sidecar
/// landed have no `.idx` — the slider disables with a tooltip
/// explaining why (capability-ladder rung 4: hide rather than ship a
/// weaker path that pretends to scrub).
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

class _RecordingPlaybackDialogState extends State<RecordingPlaybackDialog> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;

  /// Replay speed multiplier. `null` means "instant" (skip every
  /// inter-event delay so the user lands at the final frame
  /// immediately).
  double? _speed = 1.0;

  bool _running = false;
  bool _disposed = false;
  String? _error;

  /// Current playback position in milliseconds. Drives the scrub-bar
  /// thumb; updated as events stream past their timestamp.
  int _positionMs = 0;

  /// Total recording duration in milliseconds, taken from
  /// `RecordingMeta` if present. The scrub bar renders against this
  /// max; a null / zero meta forces the bar into disabled mode.
  late final int _totalMs;

  /// Probe result for the sidecar. `true` means at least one entry
  /// exists → scrub bar enabled. `false` (legacy recording or
  /// missing sidecar) → scrub bar disabled with tooltip.
  bool? _scrubAvailable;

  /// Active playback subscription. Held so a scrub event can cancel
  /// the current pump and restart from the new offset.
  StreamSubscription<RecordingDecodedLine>? _playSub;

  /// Set during an in-flight slider drag so the play loop pauses
  /// (event timestamps stop advancing the cursor) while the user
  /// drags. The pump itself remains alive; the slider's
  /// `onChangeEnd` triggers a [_jumpTo] to the released value.
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    final w = widget.meta?.header.width ?? 80;
    final h = widget.meta?.header.height ?? 24;
    _terminal = Terminal(maxLines: 10000);
    _terminal.resize(w, h);
    _terminalController = TerminalController();
    _totalMs = ((widget.meta?.durationSeconds ?? 0) * 1000).round();
    _probeScrubAvailability();
    _start();
  }

  Future<void> _probeScrubAvailability() async {
    // A seek to ts=0 returns Some(...) when the sidecar exists with
    // at least one entry; null otherwise. Fast — binary-search over
    // the whole sidecar is `O(log n)` on a multi-KB index file.
    try {
      final hit = await RecordingReader.seek(
        widget.filePath,
        targetMs: _totalMs > 0 ? _totalMs : 0,
        encrypted: widget.encrypted,
      );
      if (!mounted) return;
      setState(() => _scrubAvailable = hit != null && _totalMs > 0);
    } catch (e, st) {
      AppLogger.instance.log(
        'Scrub-bar probe failed; falling back to sequential-only',
        name: 'Recording',
        error: e,
        stackTrace: st,
      );
      if (mounted) setState(() => _scrubAvailable = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playSub?.cancel();
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _positionMs = 0;
    });
    await _pumpFrom(
      stream: RecordingReader.open(widget.filePath),
      startMs: 0,
      skipHeader: false,
    );
  }

  /// Cancel any in-flight playback subscription, clear the terminal,
  /// and restart the decoder pre-positioned at the matched sidecar
  /// offset. Falls back to a full re-decode (target reached by
  /// sequentially streaming the file from start) when the sidecar
  /// returns null — same UX as a legacy recording, just slower.
  Future<void> _jumpTo(int targetMs) async {
    await _playSub?.cancel();
    _playSub = null;
    if (_disposed) return;
    setState(() {
      _running = true;
      _error = null;
      _positionMs = targetMs;
    });
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);
    final hit = await RecordingReader.seek(
      widget.filePath,
      targetMs: targetMs,
      encrypted: widget.encrypted,
    );
    if (_disposed) return;
    if (hit == null) {
      // No sidecar — sequentially replay from start, fast-forwarding
      // every event whose timestamp is below the target (we let the
      // dialog's normal pump drive the terminal write so trailing
      // ANSI state lands cleanly).
      await _pumpFrom(
        stream: RecordingReader.open(widget.filePath),
        startMs: 0,
        skipHeader: false,
        forwardUntilMs: targetMs,
      );
      return;
    }
    await _pumpFrom(
      stream: RecordingReader.openAt(
        widget.filePath,
        byteOffset: hit.byteOffset,
        startFrameIndex: hit.startFrameIndex,
      ),
      startMs: hit.timestampMs,
      skipHeader: true,
    );
  }

  /// Common pump loop shared by [_start] and [_jumpTo]. Drives the
  /// decoded-line stream into the xterm widget at the active speed,
  /// updating `_positionMs` after every applied event.
  ///
  /// `forwardUntilMs` (when non-null) suppresses the inter-event
  /// delay until the cursor crosses the threshold — used for the
  /// legacy fallback when no sidecar exists, so the user does not
  /// have to wait at 1× to reach a deep scrub target.
  Future<void> _pumpFrom({
    required Stream<RecordingDecodedLine> stream,
    required int startMs,
    required bool skipHeader,
    int? forwardUntilMs,
  }) async {
    var prevTimestamp = startMs / 1000.0;
    var sawHeader = skipHeader;
    final completer = Completer<void>();
    _playSub = stream.listen(
      (line) async {
        if (_disposed) return;
        if (!sawHeader) {
          sawHeader = true;
          // The Rust-side `decodeHeaderLine` returns non-null only
          // for the asciinema-v2 header object (first record of
          // every cast); event tuples and malformed lines fall
          // through to the event-decode path below.
          if (decodeHeaderLine(line.value) != null) return;
        }
        final frame = decodeEventLine(line.value);
        if (frame == null) return;
        final speed = _speed;
        final fastForward =
            forwardUntilMs != null && (frame.timestamp * 1000) < forwardUntilMs;
        if (speed != null && !fastForward && !_scrubbing) {
          final delta = frame.timestamp - prevTimestamp;
          if (delta > 0) {
            final waitSeconds = (delta / speed).clamp(0.0, 5.0);
            await Future.delayed(
              Duration(milliseconds: (waitSeconds * 1000).round()),
            );
          }
        }
        if (_disposed) return;
        if (frame.direction == 'o') {
          _terminal.write(frame.data);
        }
        prevTimestamp = frame.timestamp;
        if (mounted) {
          setState(() => _positionMs = (frame.timestamp * 1000).round());
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        AppLogger.instance.log(
          'Recording playback failed',
          name: 'Recording',
          error: e,
          stackTrace: st,
        );
        if (mounted) setState(() => _error = e.toString());
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future;
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final w = widget.meta?.header.width ?? 80;
    final h = widget.meta?.header.height ?? 24;
    final fontSize = AppFonts.sm;
    return AppDialog(
      title: l10n.recordingPlaybackTitle,
      maxWidth: (w * fontSize * 0.6).clamp(420.0, 900.0),
      scrollable: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSpeedRow(l10n),
          const SizedBox(height: AppSpacing.sm),
          _buildScrubRow(l10n),
          const SizedBox(height: AppSpacing.md),
          _buildTerminal(h, fontSize),
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
            const DropdownMenuItem(value: 1.0, child: Text('1×')),
            const DropdownMenuItem(value: 2.0, child: Text('2×')),
            const DropdownMenuItem(value: 4.0, child: Text('4×')),
            DropdownMenuItem(
              value: null,
              child: Text(l10n.recordingSpeedInstant),
            ),
          ],
          onChanged: (v) => setState(() => _speed = v),
        ),
        const Spacer(),
        if (_running)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  Widget _buildScrubRow(S l10n) {
    final available = _scrubAvailable ?? false;
    final maxValue = _totalMs > 0 ? _totalMs.toDouble() : 1.0;
    final value = _positionMs.clamp(0, _totalMs > 0 ? _totalMs : 0).toDouble();
    final slider = Slider(
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
              unawaited(_jumpTo(v.round()));
            }
          : null,
    );
    final positionLabel = l10n.recordingScrubPositionLabel(
      _formatDuration(_positionMs),
      _formatDuration(_totalMs),
    );
    return Row(
      children: [
        Expanded(
          child: available
              ? slider
              : Tooltip(
                  message: l10n.recordingScrubTooltipUnavailable,
                  child: slider,
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderLight),
        borderRadius: AppTheme.radiusSm,
      ),
      // SizedBox sized to fit the recording's column count at
      // the active font size — keeps the playback geometry
      // honest (a 132-col session does not get squashed into
      // 80 cols). Height capped so the dialog stays inside
      // the viewport on mobile.
      child: SizedBox(
        height: (h * fontSize * kTerminalLineHeight).clamp(200.0, 480.0),
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
