import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/sanitize.dart';
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
  final errorDetail = redactSecrets(error.toString());
  final loggingEnabled = AppLogger.instance.enabled;
  final l10n = S.of(context);

  try {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return AppDialog(
          title: l10n.globalErrorTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.globalErrorBody,
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                loggingEnabled
                    ? l10n.globalErrorLogSavedNote
                    : l10n.globalErrorLogDisabledNote,
                style: TextStyle(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.globalErrorTechnicalLine(errorDetail),
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
                label: l10n.globalErrorEnableLoggingButton,
                onTap: () {
                  // "Enable Logging" defaults to info — the most
                  // verbose level we have, which writes every routine
                  // entry + warnings + errors.
                  unawaited(AppLogger.instance.setThreshold(LogLevel.info));
                  AppLogger.instance.log(
                    'Logging enabled after error',
                    name: 'ErrorBoundary',
                  );
                  Navigator.of(ctx).pop();
                  Toast.show(
                    ctx,
                    message: l10n.globalErrorLoggingEnabledToast,
                    level: ToastLevel.success,
                  );
                },
              ),
            AppButton.primary(
              label: l10n.ok,
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
