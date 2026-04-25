import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../widgets/app_dialog.dart';
import '../terminal/cursor_overlay.dart';
import 'recording_reader.dart';

/// Modal that replays a recording into a read-only xterm widget at
/// a user-selectable speed (1× / 2× / 4× / instant).
///
/// **Why no scrub bar.** Scrubbing demands random access into the
/// asciinema timeline, but the current GCM-frame stream is purely
/// sequential — seeking to a midpoint event would require either a
/// per-frame index file (extra metadata to persist) or a full-file
/// re-decrypt to rebuild the offset table. The 1× / 4× / instant
/// dropdown covers the common "skim a long session" need without
/// either cost. A future commit can add an index file beside the
/// recording if scrubbing becomes a felt need.
///
/// **Why a custom replay loop, not asciinema's player package.**
/// Their package is built on package:web — it injects a `<canvas>`
/// inside an iframe and is not portable to Flutter desktop / mobile.
/// Re-implementing the loop ourselves over xterm keeps the same
/// rendering stack the rest of the app uses.
class RecordingPlaybackDialog extends StatefulWidget {
  final File file;
  final bool encrypted;
  final Uint8List? dbKey;
  final RecordingMeta? meta;

  const RecordingPlaybackDialog({
    super.key,
    required this.file,
    required this.encrypted,
    required this.dbKey,
    required this.meta,
  });

  static Future<void> show(
    BuildContext context, {
    required File file,
    required bool encrypted,
    required Uint8List? dbKey,
    required RecordingMeta? meta,
  }) {
    return AppDialog.show<void>(
      context,
      builder: (_) => RecordingPlaybackDialog(
        file: file,
        encrypted: encrypted,
        dbKey: dbKey,
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

  @override
  void initState() {
    super.initState();
    final w = widget.meta?.header.width ?? 80;
    final h = widget.meta?.header.height ?? 24;
    _terminal = Terminal(maxLines: 10000);
    _terminal.resize(w, h);
    _terminalController = TerminalController();
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final stream = widget.encrypted
          ? RecordingReader.openEncrypted(widget.file, widget.dbKey!)
          : RecordingReader.openCast(widget.file);
      var prevTimestamp = 0.0;
      var sawHeader = false;
      await for (final line in stream) {
        if (_disposed) return;
        if (!sawHeader) {
          // First record is the header — already used for sizing
          // before we started reading. Skip the JSON object.
          sawHeader = true;
          try {
            final v = jsonDecode(line.value);
            if (v is Map<String, Object?>) continue;
          } catch (_) {
            // Not a header — fall through and treat as event.
          }
        }
        final frame = decodeEventLine(line.value);
        if (frame == null) continue;
        final speed = _speed;
        if (speed != null) {
          final delta = frame.timestamp - prevTimestamp;
          if (delta > 0) {
            // Cap any single delay at 5 seconds — recordings with
            // long idle gaps (user away from keyboard) should not
            // freeze the player for minutes; the bytes still
            // arrive in order, just compressed at the gap.
            final waitSeconds = (delta / speed).clamp(0.0, 5.0);
            await Future.delayed(
              Duration(milliseconds: (waitSeconds * 1000).round()),
            );
          }
        }
        if (_disposed) return;
        // Only the output stream paints — input bytes are recorded
        // for forensic value but the user already saw their own
        // typing's echo as terminal output, so re-applying input
        // would double-print. asciinema standard players do the
        // same.
        if (frame.direction == 'o') {
          _terminal.write(frame.data);
        }
        prevTimestamp = frame.timestamp;
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'Recording playback failed',
        name: 'Recording',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
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
          Row(
            children: [
              Text(
                l10n.recordingSpeed,
                style: TextStyle(
                  color: AppTheme.fgFaint,
                  fontFamily: 'Inter',
                  fontSize: AppFonts.xs,
                ),
              ),
              const SizedBox(width: 8),
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
          ),
          const SizedBox(height: 12),
          Container(
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
                padding: const EdgeInsets.all(4),
                textStyle: TerminalStyle(
                  fontSize: fontSize,
                  fontFamily: AppFonts.monoFamily,
                  fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
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
}
