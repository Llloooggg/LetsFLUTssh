import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Verdict returned by [AgentSignatureRequestDialog]. Mirrors
/// `lfs_core::ssh_agent::per_key_confirm::Decision` case-for-case so
/// the FRB shim maps directly: `'once'` -> `AuthorizeOnce`,
/// `'always'` -> `AuthorizeAndRemember`, anything else -> `Deny`.
enum AgentSignatureDecision { authorizeOnce, authorizeAlways, deny }

/// Modal that surfaces a per-key SIGN_REQUEST confirmation prompt
/// from the in-process ssh-agent endpoint
/// (`lfs_core::ssh_agent`). Composes [AppDialog] verbatim so the
/// visual contract reads the same as every other security-related
/// modal in the app.
class AgentSignatureRequestDialog extends StatelessWidget {
  /// Human-readable label of the stored key being signed against.
  final String keyLabel;

  /// Best-effort name of the SSH client behind the agent socket
  /// (`git`, `ssh`, etc.). `null` on platforms that cannot
  /// resolve the peer process — the dialog body renders the
  /// localized "Unknown" placeholder.
  final String? requesterName;

  const AgentSignatureRequestDialog({
    super.key,
    required this.keyLabel,
    this.requesterName,
  });

  /// Show the dialog. Returns `null` when the route was popped
  /// without an explicit choice — caller treats `null` as `deny`.
  static Future<AgentSignatureDecision?> show(
    BuildContext context, {
    required String keyLabel,
    String? requesterName,
  }) {
    return AppDialog.show<AgentSignatureDecision>(
      context,
      builder: (_) => AgentSignatureRequestDialog(
        keyLabel: keyLabel,
        requesterName: requesterName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final requester = requesterName ?? s.agentEndpointRequesterUnknown;
    return AppDialog(
      title: s.agentEndpointSignatureRequestTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key, size: 28, color: AppTheme.accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  keyLabel,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.agentEndpointSignatureRequestBody(requester, keyLabel),
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppButton.destructive(
          label: s.agentEndpointDeny,
          onTap: () => Navigator.of(context).pop(AgentSignatureDecision.deny),
        ),
        AppButton.secondary(
          label: s.agentEndpointAuthorizeAlways,
          onTap: () =>
              Navigator.of(context).pop(AgentSignatureDecision.authorizeAlways),
        ),
        AppButton.primary(
          label: s.agentEndpointAuthorizeOnce,
          onTap: () =>
              Navigator.of(context).pop(AgentSignatureDecision.authorizeOnce),
        ),
      ],
    );
  }
}
