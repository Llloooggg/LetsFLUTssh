import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import 'progress_writer.dart';
import 'readonly_terminal_grid_view.dart';
import '../../l10n/app_localizations.dart';

/// Displays structured connection progress through the Rust terminal engine —
/// identical rendering to the live terminal pane's progress output.
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
  late final ReadOnlyTerminalController _controller;
  ProgressTracker? _tracker;
  late ProgressWriter _writer;
  StreamSubscription<ConnectionStep>? _sub;

  @override
  void initState() {
    super.initState();
    _controller = ReadOnlyTerminalController(
      cols: 80,
      rows: 24,
      scrollback: 50,
    );
    _tracker = ProgressTracker(widget.connection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return; // already subscribed
    _writer = ProgressWriter.controller(
      controller: _controller,
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
    _controller.dispose();
    super.dispose();
  }

  /// Add a consumer-local step (e.g. "Opening SFTP channel").
  /// Does NOT propagate to the shared [Connection.progressStream].
  void addStep(ConnectionStep step) {
    _tracker?.addLocalStep(step);
  }

  /// Write a localized error message to the progress terminal.
  void writeError(String message) {
    _controller.feed(utf8.encode('\x1B[?25h\x1B[31m$message\x1B[0m\r\n'));
  }

  @override
  Widget build(BuildContext context) {
    return ReadOnlyTerminalGridView(
      controller: _controller,
      fontSize: widget.fontSize,
      reportResize: true,
      selectable: true,
    );
  }
}
