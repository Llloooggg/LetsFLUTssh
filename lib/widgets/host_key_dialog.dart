import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

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
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
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
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isChanged ? Icons.warning_amber_rounded : Icons.shield_outlined,
            color: isChanged ? AppTheme.connecting : theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isChanged ? 'Host Key Changed!' : 'Unknown Host',
              style: TextStyle(
                color: isChanged ? AppTheme.connecting : null,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isChanged) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.connecting.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.connecting.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'WARNING: The host key for this server has changed. '
                  'This could indicate a man-in-the-middle attack, '
                  'or the server may have been reinstalled.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const Text(
                'The authenticity of this host cannot be established. '
                'Are you sure you want to continue connecting?',
                style: TextStyle(fontSize: 13),
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
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    fingerprint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: fingerprint));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Fingerprint copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    tooltip: 'Copy fingerprint',
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: isChanged
              ? FilledButton.styleFrom(backgroundColor: AppTheme.connecting)
              : null,
          child: Text(isChanged ? 'Accept Anyway' : 'Accept'),
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
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
