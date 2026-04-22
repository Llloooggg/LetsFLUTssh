import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/transfer/conflict_resolver.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Dialog shown when a transfer's destination file already exists.
///
/// Offers the user four choices (Skip / Keep both / Replace / Cancel)
/// and an "apply to all remaining" checkbox for batch transfers.
class FileConflictDialog extends StatefulWidget {
  final String fileName;
  final String targetDir;
  final bool isRemoteTarget;
  final bool showApplyToAll;

  const FileConflictDialog({
    super.key,
    required this.fileName,
    required this.targetDir,
    required this.isRemoteTarget,
    this.showApplyToAll = true,
  });

  /// Show the dialog and return the user's [ConflictDecision], or a
  /// cancel decision if the dialog was dismissed by tapping the
  /// scrim or pressing the close button.
  static Future<ConflictDecision> show(
    BuildContext context, {
    required String targetPath,
    required bool isRemoteTarget,
    bool showApplyToAll = true,
  }) async {
    final ctx = isRemoteTarget ? p.posix : p.context;
    final fileName = ctx.basename(targetPath);
    final targetDir = ctx.dirname(targetPath);
    final result = await AppDialog.show<ConflictDecision>(
      context,
      builder: (_) => FileConflictDialog(
        fileName: fileName,
        targetDir: targetDir,
        isRemoteTarget: isRemoteTarget,
        showApplyToAll: showApplyToAll,
      ),
    );
    return result ?? const ConflictDecision(ConflictAction.cancel);
  }

  @override
  State<FileConflictDialog> createState() => _FileConflictDialogState();
}

class _FileConflictDialogState extends State<FileConflictDialog> {
  bool _applyToAll = false;

  void _pop(ConflictAction action) {
    Navigator.of(
      context,
    ).pop(ConflictDecision(action, applyToAll: _applyToAll));
  }

  @override
  Widget build(BuildContext context) {
    final loc = S.of(context);
    return AppDialog(
      title: loc.fileConflictTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.fileConflictMessage(widget.fileName, widget.targetDir),
            style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.sm),
          ),
          if (widget.showApplyToAll) ...[
            const SizedBox(height: 16),
            _ApplyToAllCheckbox(
              value: _applyToAll,
              onChanged: (v) => setState(() => _applyToAll = v),
            ),
          ],
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => _pop(ConflictAction.cancel)),
        AppButton.secondary(
          label: loc.fileConflictSkip,
          onTap: () => _pop(ConflictAction.skip),
        ),
        AppButton.secondary(
          label: loc.fileConflictKeepBoth,
          onTap: () => _pop(ConflictAction.keepBoth),
        ),
        AppButton.primary(
          label: loc.fileConflictReplace,
          onTap: () => _pop(ConflictAction.replace),
        ),
      ],
    );
  }
}

class _ApplyToAllCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ApplyToAllCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final loc = S.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Text(
            loc.fileConflictApplyAll,
            style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.sm),
          ),
        ],
      ),
    );
  }
}
