import 'package:flutter/material.dart';

/// Shown when no tabs are open.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNewSession;

  const WelcomeScreen({super.key, required this.onNewSession});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'LetsFLUTssh',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SSH/SFTP Client',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onNewSession,
            icon: const Icon(Icons.add),
            label: const Text('New Session'),
          ),
          const SizedBox(height: 8),
          Text(
            'Ctrl+N to connect',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
