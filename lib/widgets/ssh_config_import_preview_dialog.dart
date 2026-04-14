import 'package:flutter/material.dart';

import '../core/import/openssh_config_importer.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Preview dialog for the `~/.ssh/config` importer.
///
/// Purely informational — the user sees what will be imported (hosts +
/// any missing keys) and confirms. Returns true when the user accepts.
class SshConfigImportPreviewDialog extends StatelessWidget {
  final OpenSshConfigImportPreview preview;
  final String folderLabel;

  const SshConfigImportPreviewDialog({
    super.key,
    required this.preview,
    required this.folderLabel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required OpenSshConfigImportPreview preview,
    required String folderLabel,
  }) => AppDialog.show<bool>(
    context,
    builder: (_) => SshConfigImportPreviewDialog(
      preview: preview,
      folderLabel: folderLabel,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final hostCount = preview.result.sessions.length;
    final hasHosts = hostCount > 0;

    return AppDialog(
      title: s.sshConfigPreviewTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasHosts
                ? s.sshConfigPreviewHostsFound(hostCount)
                : s.sshConfigPreviewNoHosts,
            style: AppFonts.inter(fontSize: AppFonts.md),
          ),
          if (hasHosts) ...[
            const SizedBox(height: 8),
            Text(
              s.sshConfigPreviewFolderLabel(folderLabel),
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
              ),
            ),
            const SizedBox(height: 12),
            _HostList(sessions: preview.result.sessions),
            if (preview.hostsWithMissingKeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                s.sshConfigPreviewMissingKeys(
                  preview.hostsWithMissingKeys.join(', '),
                ),
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.yellow,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context, false)),
        AppDialogAction.primary(
          label: s.importData,
          enabled: hasHosts,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _HostList extends StatelessWidget {
  final List sessions;
  const _HostList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${s.label}  —  ${s.user.isEmpty ? '?' : s.user}@${s.host}:${s.port}'
                  '${s.keyId.isNotEmpty ? '  (key)' : ''}',
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
