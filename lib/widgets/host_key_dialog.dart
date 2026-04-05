import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      title: isChanged ? 'Host Key Changed!' : 'Unknown Host',
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
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.connecting,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WARNING: The host key for this server has changed. '
                      'This could indicate a man-in-the-middle attack, '
                      'or the server may have been reinstalled.',
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
              'The authenticity of this host cannot be established. '
              'Are you sure you want to continue connecting?',
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Host', value: '$host:$port'),
          const SizedBox(height: 6),
          _InfoRow(label: 'Key type', value: keyType),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  'Fingerprint',
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
                    const SnackBar(
                      content: Text('Fingerprint copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: 'Copy fingerprint',
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
            label: 'Accept Anyway',
            onTap: () => Navigator.pop(context, true),
          )
        else
          AppDialogAction.primary(
            label: 'Accept',
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
        SizedBox(
          width: 70,
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
