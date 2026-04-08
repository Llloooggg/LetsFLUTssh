import 'dart:async';

import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../ssh/ssh_config.dart';
import 'connection_step.dart';
import 'progress_tracker.dart';

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

/// Writes structured connection progress steps to an xterm [Terminal].
///
/// Shared between desktop [TerminalPane] and mobile [MobileTerminalView].
class ProgressWriter {
  final Terminal terminal;
  final S l10n;
  final SSHConfig config;

  /// Custom label for [ConnectionPhase.openChannel].
  /// Defaults to [S.progressOpeningShell] when null.
  final String? channelLabel;

  ProgressWriter({
    required this.terminal,
    required this.l10n,
    required this.config,
    this.channelLabel,
  });

  /// Subscribe to [tracker] and write steps to [terminal].
  ///
  /// Replays any buffered history first (handles late subscription), then
  /// listens for new steps. Returns the subscription so the caller can cancel.
  StreamSubscription<ConnectionStep> subscribe(ProgressTracker tracker) {
    terminal.write(_Ansi.hideCursor);
    for (final step in tracker.history) {
      writeStep(step);
    }
    return tracker.stream.listen(writeStep);
  }

  /// Write a single progress step to the terminal.
  void writeStep(ConnectionStep step) {
    final label = _phaseLabel(step.phase);
    switch (step.status) {
      case StepStatus.inProgress:
        terminal.write('${_Ansi.yellow}[*]${_Ansi.reset} $label...\r\n');
      case StepStatus.success:
        terminal.write(
          '${_Ansi.moveUpAndClear}'
          '${_Ansi.green}[✓]${_Ansi.reset} $label\r\n',
        );
      case StepStatus.failed:
        final detail = step.detail != null ? ': ${step.detail}' : '';
        terminal.write(
          '${_Ansi.moveUpAndClear}'
          '${_Ansi.red}[✗]${_Ansi.reset} $label$detail\r\n',
        );
    }
  }

  /// Clear the terminal (used after successful connection).
  void clear() {
    terminal.write('${_Ansi.clearScreen}${_Ansi.showCursor}');
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
