import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

/// Full-screen display of a QR code for scanning by another device.
class QrDisplayScreen extends StatelessWidget {
  final String data;
  final int sessionCount;

  const QrDisplayScreen({
    super.key,
    required this.data,
    required this.sessionCount,
  });

  /// Show the QR display screen.
  static Future<void> show(
    BuildContext context, {
    required String data,
    required int sessionCount,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrDisplayScreen(data: data, sessionCount: sessionCount),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QR code with white background for reliable scanning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppTheme.radiusLg,
                ),
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 280,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorStateBuilder: (context, error) => Center(
                    child: Text(
                      'QR generation failed',
                      style: TextStyle(color: AppTheme.red),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '$sessionCount session(s)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Scan with any camera app on a device\n'
                'that has LetsFLUTssh installed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFonts.lg,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.3,
                        ),
                  borderRadius: AppTheme.radiusLg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'No passwords or keys are in this QR code',
                      style: TextStyle(fontSize: AppFonts.md),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: data));
                  Toast.show(
                    context,
                    message: 'Link copied to clipboard',
                    level: ToastLevel.success,
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
