import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../core/connection/connection.dart';
import '../core/connection/connection_step.dart';
import '../core/connection/progress_tracker.dart';
import '../core/connection/progress_writer.dart';
import '../l10n/app_localizations.dart';
import 'readonly_terminal_view.dart';

/// Displays structured connection progress using a read-only xterm Terminal —
/// identical rendering to the terminal pane progress output.
///
/// Used by SFTP file browser tabs (desktop and mobile).
class ConnectionProgress extends StatefulWidget {
  final Connection connection;
  final double fontSize;

  /// Custom label for [ConnectionPhase.openChannel].
  /// Defaults to "Opening shell…" when null; SFTP tabs pass "Opening SFTP…".
  final String? channelLabel;

  const ConnectionProgress({
    super.key,
    required this.connection,
    this.fontSize = 14.0,
    this.channelLabel,
  });

  @override
  State<ConnectionProgress> createState() => ConnectionProgressState();
}

class ConnectionProgressState extends State<ConnectionProgress> {
  late final Terminal _terminal;
  ProgressTracker? _tracker;
  late ProgressWriter _writer;
  StreamSubscription<ConnectionStep>? _sub;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 50);
    _tracker = ProgressTracker(widget.connection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return; // already subscribed
    _writer = ProgressWriter(
      terminal: _terminal,
      l10n: S.of(context),
      config: widget.connection.sshConfig,
      channelLabel: widget.channelLabel,
    );
    _sub = _writer.subscribe(_tracker!);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tracker?.dispose();
    super.dispose();
  }

  /// Add a consumer-local step (e.g. "Opening SFTP channel").
  /// Does NOT propagate to the shared [Connection.progressStream].
  void addStep(ConnectionStep step) {
    _tracker?.addLocalStep(step);
  }

  /// Write a localized error message to the progress terminal.
  void writeError(String message) {
    _terminal.write('\x1B[?25h\x1B[31m$message\x1B[0m\r\n');
  }

  @override
  Widget build(BuildContext context) {
    return ReadOnlyTerminalView(terminal: _terminal, fontSize: widget.fontSize);
  }
}
