import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection/connection.dart';
import '../core/connection/connection_step.dart';
import '../core/ssh/ssh_config.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Widget that displays structured connection progress steps.
///
/// Renders in a terminal-like style (dark background, monospace font,
/// [*]/[✓]/[✗] markers) to match the terminal pane progress output.
///
/// Used by SFTP file browser tabs (desktop and mobile) where there is no
/// xterm terminal to write ANSI output into.
class ConnectionProgress extends StatefulWidget {
  final Connection connection;

  /// Optional extra step added after SSH connection succeeds
  /// (e.g. "Opening SFTP channel").
  final String? channelLabel;

  const ConnectionProgress({
    super.key,
    required this.connection,
    this.channelLabel,
  });

  @override
  State<ConnectionProgress> createState() => ConnectionProgressState();
}

class ConnectionProgressState extends State<ConnectionProgress> {
  final _steps = <ConnectionStep>[];
  StreamSubscription<ConnectionStep>? _sub;

  @override
  void initState() {
    super.initState();
    // Replay buffered history (handles late subscription)
    _steps.addAll(widget.connection.progressHistory);
    _sub = widget.connection.progressStream.listen((step) {
      if (mounted) setState(() => _steps.add(step));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Add a local step (not from the connection stream) — used for
  /// channel-specific progress like "Opening SFTP channel".
  void addStep(ConnectionStep step) {
    if (mounted) setState(() => _steps.add(step));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final config = widget.connection.sshConfig;

    // Collapse inProgress steps that have a subsequent success/failed step
    // for the same phase — only show the final state.
    final visible = _collapseSteps(_steps);

    return Container(
      color: AppTheme.bg2,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in visible)
            _StepLine(step: step, config: config, l10n: l10n),
        ],
      ),
    );
  }

  /// Collapse consecutive inProgress→success/failed pairs for the same phase
  /// into just the final step.
  static List<ConnectionStep> _collapseSteps(List<ConnectionStep> steps) {
    final result = <ConnectionStep>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step.status == StepStatus.inProgress) {
        // Check if next step is the resolution for this phase
        final hasResolution =
            i + 1 < steps.length &&
            steps[i + 1].phase == step.phase &&
            steps[i + 1].status != StepStatus.inProgress;
        if (hasResolution) continue; // skip inProgress, show resolution
      }
      result.add(step);
    }
    return result;
  }
}

class _StepLine extends StatelessWidget {
  final ConnectionStep step;
  final SSHConfig config;
  final S l10n;

  const _StepLine({
    required this.step,
    required this.config,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final (marker, color) = switch (step.status) {
      StepStatus.inProgress => ('[*]', AppTheme.yellow),
      StepStatus.success => ('[✓]', AppTheme.green),
      StepStatus.failed => ('[✗]', AppTheme.red),
    };

    final label = _phaseLabel(step.phase);
    final suffix = step.status == StepStatus.inProgress ? '...' : '';
    final detail = step.detail != null ? ': ${step.detail}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: marker,
              style: AppFonts.mono(fontSize: AppFonts.sm, color: color),
            ),
            TextSpan(
              text: ' $label$suffix$detail',
              style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
            ),
          ],
        ),
      ),
    );
  }

  String _phaseLabel(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.socketConnect => l10n.progressConnecting(
      config.host,
      config.effectivePort,
    ),
    ConnectionPhase.hostKeyVerify => l10n.progressVerifyingHostKey,
    ConnectionPhase.authenticate => l10n.progressAuthenticating(config.user),
    ConnectionPhase.openChannel => l10n.progressOpeningSftp,
  };
}
