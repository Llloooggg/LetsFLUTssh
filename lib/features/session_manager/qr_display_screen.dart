import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Modal display of a QR code for scanning by another device.
///
/// Shown via [AppDialog.show] so it matches the rest of the export flow
/// (the preceding `QrExportDialog` is also a modal). The previous
/// full-screen route was an outlier and introduced an unwanted slide
/// transition — every other modal in the app uses the app's shared
/// no-animation dialog style.
class QrDisplayScreen extends StatelessWidget {
  final String data;
  final int sessionCount;

  /// True when the deep-link payload carries session credentials — i.e. the
  /// user kept [ExportOptions.includePasswords] or any key-inclusion flag
  /// enabled in the export dialog.
  ///
  /// The display intentionally reflects the *actual* payload rather than
  /// assuming a default: for QR mode [UnifiedExportDialog] ships with
  /// `includePasswords: true` on, so a blanket "no passwords in QR" message
  /// would be a lie — and "lies in a security prompt" is exactly the kind
  /// of thing that gets credentials leaked.
  final bool containsCredentials;

  const QrDisplayScreen({
    super.key,
    required this.data,
    required this.sessionCount,
    this.containsCredentials = false,
  });

  /// Show the QR display as a modal dialog.
  static Future<void> show(
    BuildContext context, {
    required String data,
    required int sessionCount,
    bool containsCredentials = false,
  }) {
    return AppDialog.show<void>(
      context,
      builder: (_) => QrDisplayScreen(
        data: data,
        sessionCount: sessionCount,
        containsCredentials: containsCredentials,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppDialog(
      title: S.of(context).scanQrCode,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  S.of(context).qrGenerationFailed,
                  style: TextStyle(color: AppTheme.red),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            S.of(context).nSessions(sessionCount),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            S.of(context).scanWithCameraApp,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFonts.lg,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          _buildSecurityBadge(context, theme),
        ],
      ),
      actions: [
        AppDialogAction.primary(
          label: S.of(context).copyLink,
          onTap: () {
            Clipboard.setData(ClipboardData(text: data));
            Toast.show(
              context,
              message: S.of(context).linkCopied,
              level: ToastLevel.success,
            );
          },
        ),
      ],
    );
  }

  /// Bottom info chip. Switches to an orange warning style when the payload
  /// carries credentials so the user is prompted to keep the screen private;
  /// otherwise shows the neutral "no passwords in QR" confirmation.
  Widget _buildSecurityBadge(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (containsCredentials) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.orange.withValues(alpha: 0.15),
          borderRadius: AppTheme.radiusLg,
          border: Border.all(color: AppTheme.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 14, color: AppTheme.orange),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                S.of(context).qrContainsCredentialsWarning,
                style: TextStyle(fontSize: AppFonts.md, color: AppTheme.orange),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: AppTheme.radiusLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              S.of(context).noPasswordsInQr,
              style: TextStyle(fontSize: AppFonts.md),
            ),
          ),
        ],
      ),
    );
  }
}
