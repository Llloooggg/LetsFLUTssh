import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../widgets/app_dialog.dart';
import '../widgets/toast.dart';

/// Shows a user-friendly error dialog for unhandled async errors.
///
/// Error is already logged by the crash handler in `main.dart` — this
/// just surfaces a brief message and, when routine logging is off,
/// offers a one-tap enable so the next recurrence lands on disk.
///
/// Caller contract: invoked from the post-frame callback of the global
/// error boundary (`FlutterError.onError` + `runZonedGuarded`) with a
/// [BuildContext] resolved through `navigatorKey.currentContext`. Safe
/// on a null / unmounted context — the outer callback already checked
/// before calling in.
void showGlobalErrorDialog(BuildContext context, Object error) {
  final errorType = error.runtimeType.toString();
  final loggingEnabled = AppLogger.instance.enabled;

  try {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return AppDialog(
          title: 'Unexpected Error',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An unexpected error occurred. The app will continue running.',
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
              ),
              const SizedBox(height: 8),
              Text(
                loggingEnabled
                    ? 'Full details have been saved to the log file.'
                    : 'Enable logging in Settings to save error details.',
                style: TextStyle(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Error: $errorType',
                style: TextStyle(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.fgFaint,
                  fontFamily: 'JetBrains Mono',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!loggingEnabled)
              AppButton.secondary(
                label: 'Enable Logging',
                onTap: () {
                  AppLogger.instance.setEnabled(true);
                  AppLogger.instance.log(
                    'Logging enabled after error: $errorType',
                    name: 'ErrorBoundary',
                  );
                  Navigator.of(ctx).pop();
                  Toast.show(
                    ctx,
                    message:
                        'Logging enabled — errors will be saved to log file',
                    level: ToastLevel.success,
                  );
                },
              ),
            AppButton.primary(
              label: 'OK',
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  } catch (e) {
    // If the dialog itself fails to show, at least leave a breadcrumb —
    // the error that triggered this was already logged by the outer
    // crash handler, but a swallowed showDialog failure here would hide
    // "why the user never saw an error message" from support traces.
    AppLogger.instance.log(
      'Failed to show error dialog: $e',
      name: 'ErrorBoundary',
    );
  }
}
