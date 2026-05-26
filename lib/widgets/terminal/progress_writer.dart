import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../../l10n/app_localizations.dart';
import '../../core/ssh/ssh_config.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import 'terminal_controller.dart';

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
/// The connection-progress surfaces (desktop pane, mobile pane, SFTP
/// connect) all drive the Rust terminal engine through a
/// [ReplayTerminalController] — [ProgressWriter.controller] encodes each
/// ANSI string to UTF-8 and feeds the controller, which repaints the
/// read-only grid. The step formatting + phase labels are shared.
class ProgressWriter {
  /// Rust-engine-backed writer. Encodes each ANSI string to UTF-8 and feeds
  /// the [ReplayTerminalController], which repaints the read-only grid.
  ProgressWriter.controller({
    required ReplayTerminalController controller,
    required this.l10n,
    required this.config,
    this.channelLabel,
  }) : _write = ((ansi) => controller.feed(utf8.encode(ansi)));

  /// Test seam — writes each formatted ANSI string straight to [sink] so the
  /// step formatting + phase labels are unit-testable without a live
  /// [ReplayTerminalController] (whose `feed` reaches into the Rust
  /// engine). Production always uses [ProgressWriter.controller].
  @visibleForTesting
  ProgressWriter.sink({
    required void Function(String ansi) sink,
    required this.l10n,
    required this.config,
    this.channelLabel,
  }) : _write = sink;

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

  /// Write a single progress step to the sink. The Rust engine sink
  /// tolerates a sequence like `\x1B[A` (cursor up) arriving before the
  /// grid has been sized — it clamps internally rather than throwing — so
  /// no buffer-not-ready guard is needed here.
  void writeStep(ConnectionStep step) {
    final label = _phaseLabel(step.phase);
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
