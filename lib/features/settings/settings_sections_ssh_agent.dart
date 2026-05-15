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

/// Rust-owned agent endpoint snapshot. Sync FRB call — invalidated
/// after every start / stop so the next `ref.watch` reads canonical
/// state.
final _sshAgentStatusProvider = Provider<rust_ssh_agent.DbAgentStatus>(
  (ref) => rust_ssh_agent.sshAgentStatus(),
);

class _SshAgentSection extends ConsumerStatefulWidget {
  const _SshAgentSection();

  @override
  ConsumerState<_SshAgentSection> createState() => _SshAgentSectionState();
}

class _SshAgentSectionState extends ConsumerState<_SshAgentSection> {
  /// In-flight flag — disables the toggle while a start / stop call
  /// is mid-flight so a double-tap doesn't enqueue both verbs.
  bool _busy = false;

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
        ref.invalidate(_sshAgentStatusProvider);
      }
    }
  }

  Future<void> _copyPath(String? path) async {
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
    final status = ref.watch(_sshAgentStatusProvider);
    final unsupported = status.unsupported;
    final running = status.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.agentEndpointSectionTitle),
        _Toggle(
          label: l10n.agentEndpointToggleTitle,
          value: running,
          onChanged: unsupported || _busy ? null : _setRunning,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          unsupported
              ? l10n.agentEndpointStatusUnsupported
              : l10n.agentEndpointToggleSubtitle,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
        if (running && status.socketPath != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  status.socketPath!,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    fontFamily: 'monospace',
                    color: AppTheme.fgDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton.secondary(
                label: Platform.isWindows
                    ? l10n.agentEndpointCopyPipeName
                    : l10n.agentEndpointCopyEnvVar,
                icon: Icons.copy,
                dense: true,
                onTap: () => _copyPath(status.socketPath),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
