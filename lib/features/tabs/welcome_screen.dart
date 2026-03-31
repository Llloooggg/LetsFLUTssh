import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shown when no tabs are open.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNewSession;

  const WelcomeScreen({super.key, required this.onNewSession});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Terminal icon in 48×48 bg3 container
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.bg3),
            child: Icon(
              Icons.terminal,
              size: 22,
              color: AppTheme.fgFaint,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No active session',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppTheme.fgDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a new connection or select one from the sidebar',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppTheme.fgFaint,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 30,
            child: TextButton.icon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add, size: 13, color: Colors.white),
              label: const Text(
                'New Connection',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.accent,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Shortcuts table
          const _ShortcutRow(keys: 'Ctrl+N', description: 'New Terminal'),
          const SizedBox(height: 6),
          const _ShortcutRow(
              keys: 'Ctrl+Shift+N', description: 'New File Transfer'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 90),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.bg3,
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Text(
            keys,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 9,
              color: AppTheme.fgDim,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          description,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            color: AppTheme.fgFaint,
          ),
        ),
      ],
    );
  }
}
