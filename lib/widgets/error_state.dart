import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Reusable centered error state with icon, message, and optional action buttons.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final IconData retryIcon;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.retryIcon = Icons.refresh,
    this.onSecondary,
    this.secondaryLabel,
    this.secondaryIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppTheme.disconnected),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: AppTheme.disconnected),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null || onSecondary != null) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRetry != null)
                  AppButton.primary(
                    label: retryLabel ?? S.of(context).retry,
                    icon: retryIcon,
                    onTap: onRetry,
                  ),
                if (onRetry != null && onSecondary != null)
                  const SizedBox(width: 12),
                if (onSecondary != null)
                  AppButton.secondary(
                    label: secondaryLabel ?? S.of(context).close,
                    icon: secondaryIcon ?? Icons.close,
                    onTap: onSecondary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
