import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shown when no tabs are open.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNewSession;

  const WelcomeScreen({super.key, required this.onNewSession});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.6);
    final faintColor = scheme.onSurface.withValues(alpha: 0.4);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
            child: Icon(Icons.terminal, size: 22, color: faintColor),
          ),
          const SizedBox(height: 16),
          Text(
            'No active session',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.lg,
              color: dimColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a new connection or select one from the sidebar',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.sm,
              color: faintColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 30,
            child: TextButton.icon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add, size: 13, color: Colors.white),
              label: Text(
                'New Connection',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.sm,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: scheme.primary,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _ShortcutRow(keys: 'Ctrl+N', description: 'New Terminal'),
          const SizedBox(height: 6),
          const _ShortcutRow(keys: 'Ctrl+Shift+N', description: 'New File Transfer'),
          const SizedBox(height: 6),
          const _ShortcutRow(keys: 'Ctrl+B', description: 'Toggle Sidebar'),
          const SizedBox(height: 6),
          const _ShortcutRow(keys: 'Ctrl+,', description: 'Settings'),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String description;

  const _ShortcutRow({required this.keys, required this.description});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.6);
    final faintColor = scheme.onSurface.withValues(alpha: 0.4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 90),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            keys,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: AppFonts.xxs,
              color: dimColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          description,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppFonts.xs,
            color: faintColor,
          ),
        ),
      ],
    );
  }
}
