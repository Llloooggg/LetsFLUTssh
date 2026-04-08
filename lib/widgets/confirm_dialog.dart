import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_dialog.dart';

/// Reusable confirmation dialog with destructive action styling.
///
/// Returns `true` if confirmed, `null` or `false` if cancelled.
class ConfirmDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String? confirmLabel;
  final bool destructive;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel,
    this.destructive = true,
  });

  /// Show the dialog and return `true` if confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required Widget content,
    String? confirmLabel,
    bool destructive = true,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
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
    final label = confirmLabel ?? S.of(context).delete;
    return AppDialog(
      title: title,
      content: content,
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.of(context).pop(false)),
        if (destructive)
          AppDialogAction.destructive(
            label: label,
            onTap: () => Navigator.of(context).pop(true),
          )
        else
          AppDialogAction.primary(
            label: label,
            onTap: () => Navigator.of(context).pop(true),
          ),
      ],
    );
  }
}
