import 'dart:async';
import 'dart:convert';

import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';
import '../../core/ssh/ssh_config.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import 'readonly_terminal_grid_view.dart';

/// ANSI escape codes for terminal progress display.
abstract final class _Ansi {
  static const reset = '\x1B[0m';
  static const yellow = '\x1B[33m';
  static const green = '\x1B[32m';
  static const red = '\x1B[31m';
  static const moveUpAndClear = '\x1B[A\x1B[2K';
  static const clearScreen = '\x1B[2J\x1B[H';
  static const hideCursor = '\x1B[?25l';
  static const showCursor = '\x1B[?25h';
}

/// Writes structured connection progress steps into a terminal sink.
///
/// Two back ends behind one ANSI-writing core: the desktop SFTP /
/// connection-progress surface drives the Rust terminal engine
/// ([ProgressWriter.controller] over a [ReadOnlyTerminalController]); the
/// mobile pane drives its xterm [Terminal] ([ProgressWriter.new]). The step
/// formatting + phase labels are shared — only the byte sink differs.
class ProgressWriter {
  /// xterm-backed writer (mobile terminal pane). Writes ANSI strings straight
  /// into the [Terminal].
  ProgressWriter({
    required Terminal terminal,
    required this.l10n,
    required this.config,
    this.channelLabel,
  }) : _write = ((ansi) => terminal.write(ansi));

  /// Rust-engine-backed writer (desktop connection-progress surface). Encodes
  /// each ANSI string to UTF-8 and feeds the [ReadOnlyTerminalController],
  /// which repaints the read-only grid.
  ProgressWriter.controller({
    required ReadOnlyTerminalController controller,
    required this.l10n,
    required this.config,
    this.channelLabel,
  }) : _write = ((ansi) => controller.feed(utf8.encode(ansi)));

  final void Function(String ansi) _write;
  final S l10n;
  final SSHConfig config;

  /// Custom label for [ConnectionPhase.openChannel].
  /// Defaults to [S.progressOpeningShell] when null.
  final String? channelLabel;

  /// Subscribe to [tracker] and write steps to the sink.
  ///
  /// Replays any buffered history first (handles late subscription), then
  /// listens for new steps. Returns the subscription so the caller can cancel.
  StreamSubscription<ConnectionStep> subscribe(ProgressTracker tracker) {
    _write(_Ansi.hideCursor);
    for (final step in tracker.history) {
      writeStep(step);
    }
    return tracker.stream.listen(writeStep);
  }

  /// Write a single progress step to the sink.
  ///
  /// Wrapped in a RangeError guard because xterm's escape parser trips
  /// `IndexAwareCircularBuffer[-2]` when its terminal has not been sized yet
  /// but a sequence like `\x1B[A` (cursor up) already arrives — the progress
  /// stream fires during connect, which can precede the terminal widget's
  /// first layout pass. The Rust engine sink never throws here; the guard
  /// covers the xterm sink (mobile pane). Swallow + log so the user's log
  /// file stays readable and the visible UI recovers on the next frame.
  void writeStep(ConnectionStep step) {
    final label = _phaseLabel(step.phase);
    try {
      switch (step.status) {
        case StepStatus.inProgress:
          _write('${_Ansi.yellow}[*]${_Ansi.reset} $label...\r\n');
        case StepStatus.success:
          _write(
            '${_Ansi.moveUpAndClear}'
            '${_Ansi.green}[✓]${_Ansi.reset} $label\r\n',
          );
        case StepStatus.failed:
          final detail = step.detail != null ? ': ${step.detail}' : '';
          _write(
            '${_Ansi.moveUpAndClear}'
            '${_Ansi.red}[✗]${_Ansi.reset} $label$detail\r\n',
          );
      }
    } on RangeError catch (e) {
      AppLogger.instance.log(
        'Terminal buffer not ready for progress step '
        '(${step.phase.name}/${step.status.name}); skipped',
        name: 'ProgressWriter',
        error: e,
      );
    }
  }

  /// Clear the terminal (used after successful connection).
  void clear() {
    _write('${_Ansi.clearScreen}${_Ansi.showCursor}');
  }

  String _phaseLabel(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.socketConnect => l10n.progressConnecting(
      config.host,
      config.effectivePort,
    ),
    ConnectionPhase.hostKeyVerify => l10n.progressVerifyingHostKey,
    ConnectionPhase.authenticate => l10n.progressAuthenticating(config.user),
    ConnectionPhase.openChannel => channelLabel ?? l10n.progressOpeningShell,
  };
}
