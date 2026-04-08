import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';

/// Dialog shown when connecting to an unknown SSH host (TOFU).
/// Displays the host fingerprint and asks the user to accept or reject.
class HostKeyDialog {
  /// Show dialog for a new unknown host.
  static Future<bool> showNewHost(
    BuildContext context, {
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      barrierDismissible: false,
      builder: (ctx) => _HostKeyDialogWidget(
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
        isChanged: false,
      ),
    );
    return result ?? false;
  }

  /// Show warning dialog when a known host's key has changed.
  static Future<bool> showKeyChanged(
    BuildContext context, {
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      barrierDismissible: false,
      builder: (ctx) => _HostKeyDialogWidget(
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
        isChanged: true,
      ),
    );
    return result ?? false;
  }
}

class _HostKeyDialogWidget extends StatelessWidget {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final bool isChanged;

  const _HostKeyDialogWidget({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.isChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: isChanged
          ? S.of(context).hostKeyChanged
          : S.of(context).unknownHost,
      dismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isChanged) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.connecting.withValues(alpha: 0.1),
                borderRadius: AppTheme.radiusLg,
                border: Border.all(
                  color: AppTheme.connecting.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.connecting,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.of(context).hostKeyChangedWarning,
                      style: TextStyle(
                        fontSize: AppFonts.md,
                        color: AppTheme.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else
            Text(
              S.of(context).unknownHostMessage,
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            ),
          const SizedBox(height: 12),
          _InfoRow(label: S.of(context).host, value: '$host:$port'),
          const SizedBox(height: 6),
          _InfoRow(label: S.of(context).keyType, value: keyType),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 70, maxWidth: 100),
                child: Text(
                  S.of(context).fingerprint,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fgFaint,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  fingerprint,
                  style: AppFonts.mono(
                    fontSize: AppFonts.sm,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.fg,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.copy,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fingerprint));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of(context).fingerprintCopied),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: S.of(context).copyFingerprint,
                size: 14,
                boxSize: 28,
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context, false)),
        if (isChanged)
          AppDialogAction.destructive(
            label: S.of(context).acceptAnyway,
            onTap: () => Navigator.pop(context, true),
          )
        else
          AppDialogAction.primary(
            label: S.of(context).accept,
            onTap: () => Navigator.pop(context, true),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 70, maxWidth: 100),
          child: Text(
            label,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w500,
              color: AppTheme.fg,
            ),
          ),
        ),
      ],
    );
  }
}
