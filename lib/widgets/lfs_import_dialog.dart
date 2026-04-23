import 'dart:io';

import 'package:flutter/material.dart';

import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_dialog.dart';
import 'mode_button.dart';
import 'secure_password_field.dart';

/// Result from the LFS import password dialog.
typedef LfsImportDialogResult = ({String password, ImportMode mode});

/// Dialog for entering master password and import mode for .lfs file import.
///
/// Returns [LfsImportDialogResult] on submit, null on cancel. When
/// [isEncrypted] is false (unencrypted ZIP archive), the password field is
/// hidden and the import button is always enabled; an empty password is
/// passed to [ExportImport.import_] to signal the unencrypted path.
class LfsImportDialog extends StatefulWidget {
  final String filePath;
  final bool isEncrypted;

  const LfsImportDialog({
    super.key,
    required this.filePath,
    this.isEncrypted = true,
  });

  /// Show the dialog and return the result.
  static Future<LfsImportDialogResult?> show(
    BuildContext context, {
    required String filePath,
    bool isEncrypted = true,
  }) {
    return AppDialog.show<LfsImportDialogResult>(
      context,
      builder: (_) =>
          LfsImportDialog(filePath: filePath, isEncrypted: isEncrypted),
    );
  }

  @override
  State<LfsImportDialog> createState() => _LfsImportDialogState();
}

class _LfsImportDialogState extends State<LfsImportDialog> {
  final _passwordCtrl = TextEditingController();
  var _mode = ImportMode.merge;

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    // For unencrypted archives the password is ignored downstream; for
    // encrypted ones an empty value would just fail to decrypt, so we
    // require non-empty input in that branch.
    if (widget.isEncrypted && _passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, (password: _passwordCtrl.text, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            File(widget.filePath).uri.pathSegments.last,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 12),
          if (widget.isEncrypted)
            SecurePasswordField(
              controller: _passwordCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.masterPassword,
                filled: true,
                fillColor: AppTheme.bg3,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
              ),
              onSubmitted: (v) {
                if (v.isNotEmpty) {
                  Navigator.pop(context, (password: v, mode: _mode));
                }
              },
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.exportWithoutPasswordWarning,
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.red),
              ),
            ),
          const SizedBox(height: 12),
          _buildModeSelector(),
          const SizedBox(height: 4),
          Text(
            _mode == ImportMode.merge
                ? l10n.importModeMergeDescription
                : l10n.importModeReplaceDescription,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        AppButton.primary(label: l10n.import_, onTap: _submit),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        ModeButton(
          label: S.of(context).merge,
          icon: Icons.merge,
          selected: _mode == ImportMode.merge,
          onTap: () => setState(() => _mode = ImportMode.merge),
        ),
        const SizedBox(width: 8),
        ModeButton(
          label: S.of(context).replace,
          icon: Icons.swap_horiz,
          selected: _mode == ImportMode.replace,
          onTap: () => setState(() => _mode = ImportMode.replace),
        ),
      ],
    );
  }
}
