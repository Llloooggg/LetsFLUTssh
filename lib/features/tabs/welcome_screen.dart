import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Shown when no tabs are open.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.6);
    final faintColor = scheme.onSurface.withValues(alpha: 0.4);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppTheme.itemHeightLg,
            height: AppTheme.itemHeightLg,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
            child: Icon(Icons.terminal, size: 22, color: faintColor),
          ),
          const SizedBox(height: 16),
          Text(
            S.of(context).noActiveSession,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.lg,
              color: dimColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).createConnectionHint,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.sm,
              color: faintColor,
            ),
          ),
        ],
      ),
    );
  }
}
