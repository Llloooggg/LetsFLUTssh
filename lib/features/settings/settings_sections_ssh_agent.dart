part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings → External SSH client integration.
//
// Drives the in-process ssh-agent endpoint (`lfs_core::ssh_agent`).
// The endpoint is off by default — flipping the toggle below starts
// the listener and shows the operator the `SSH_AUTH_SOCK` /
// OpenSSH-named-pipe path to point external SSH clients (`git`,
// `ssh`, IDE plugins) at.
//
// Per-key SIGN_REQUEST confirmation dialogs are wired by the
// post-FRB bootstrap listener (`bootstrap.dart`), not here; this
// section owns only the start / stop verbs and the path-display
// affordance.
// ═══════════════════════════════════════════════════════════════════

class _SshAgentSection extends ConsumerStatefulWidget {
  const _SshAgentSection();

  @override
  ConsumerState<_SshAgentSection> createState() => _SshAgentSectionState();
}

class _SshAgentSectionState extends ConsumerState<_SshAgentSection> {
  /// Cached status snapshot, rendered by the build method. Refreshed
  /// after every toggle so the UI matches the Rust-side reality.
  rust_ssh_agent.DbAgentStatus? _status;

  /// In-flight flag — disables the toggle while a start / stop call
  /// is mid-flight so a double-tap doesn't enqueue both verbs.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Always re-fetch the canonical state through FRB. Rust owns the
  /// data; the Dart side is a thin renderer.
  void _refresh() {
    setState(() {
      _status = rust_ssh_agent.sshAgentStatus();
    });
  }

  Future<void> _setRunning(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        await rust_ssh_agent.sshAgentStart();
      } else {
        await rust_ssh_agent.sshAgentStop();
      }
    } catch (e) {
      AppLogger.instance.log(
        'sshAgent toggle failed',
        name: 'SshAgent',
        error: e,
      );
      if (!mounted) return;
      final l10n = S.of(context);
      Toast.show(
        context,
        message: l10n.agentEndpointStartFailed(localizeError(l10n, e)),
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _copyPath() async {
    final path = _status?.socketPath;
    if (path == null) return;
    final cmd = Platform.isWindows ? path : 'export SSH_AUTH_SOCK="$path"';
    await Clipboard.setData(ClipboardData(text: cmd));
    if (!mounted) return;
    final l10n = S.of(context);
    Toast.show(context, message: l10n.commandCopied, level: ToastLevel.info);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final status = _status;
    final unsupported = status?.unsupported ?? false;
    final running = status?.running ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.agentEndpointSectionTitle),
        _Toggle(
          label: l10n.agentEndpointToggleTitle,
          value: running,
          onChanged: unsupported || _busy ? null : _setRunning,
        ),
        const SizedBox(height: 4),
        Text(
          unsupported
              ? l10n.agentEndpointStatusUnsupported
              : l10n.agentEndpointToggleSubtitle,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
        if (running && status?.socketPath != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  status!.socketPath!,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    fontFamily: 'monospace',
                    color: AppTheme.fgDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AppButton.secondary(
                label: Platform.isWindows
                    ? l10n.agentEndpointCopyPipeName
                    : l10n.agentEndpointCopyEnvVar,
                icon: Icons.copy,
                dense: true,
                onTap: _copyPath,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
