import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable confirmation dialog with destructive action styling.
///
/// Returns `true` if confirmed, `null` or `false` if cancelled.
class ConfirmDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmLabel;
  final bool destructive;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Delete',
    this.destructive = true,
  });

  /// Show the dialog and return `true` if confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required Widget content,
    String confirmLabel = 'Delete',
    bool destructive = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => ConfirmDialog(
        title: title,
        content: content,
        confirmLabel: confirmLabel,
        destructive: destructive,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.disconnected)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
