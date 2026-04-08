import 'dart:io';

import 'package:flutter/material.dart';

import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'styled_form_field.dart';

/// Result from the LFS import password dialog.
typedef LfsImportDialogResult = ({String password, ImportMode mode});

/// Dialog for entering master password and import mode for .lfs file import.
///
/// Returns [LfsImportDialogResult] on submit, null on cancel.
/// Extracted from MainScreen for testability.
class LfsImportDialog extends StatefulWidget {
  final String filePath;

  const LfsImportDialog({super.key, required this.filePath});

  /// Show the dialog and return the result.
  static Future<LfsImportDialogResult?> show(
    BuildContext context, {
    required String filePath,
  }) {
    return AppDialog.show<LfsImportDialogResult>(
      context,
      builder: (_) => LfsImportDialog(filePath: filePath),
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
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, (password: _passwordCtrl.text, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            File(widget.filePath).uri.pathSegments.last,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 12),
          StyledInput(
            controller: _passwordCtrl,
            obscure: true,
            autofocus: true,
            labelText: S.of(context).masterPassword,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            onSubmitted: (v) {
              if (v.isNotEmpty) {
                Navigator.pop(context, (password: v, mode: _mode));
              }
            },
          ),
          const SizedBox(height: 12),
          _buildModeSelector(),
          const SizedBox(height: 4),
          Text(
            _mode == ImportMode.merge
                ? S.of(context).importModeMergeDescription
                : S.of(context).importModeReplaceDescription,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: S.of(context).import_, onTap: _submit),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _modeButton(S.of(context).merge, Icons.merge, ImportMode.merge),
        const SizedBox(width: 8),
        _modeButton(
          S.of(context).replace,
          Icons.swap_horiz,
          ImportMode.replace,
        ),
      ],
    );
  }

  Widget _modeButton(String label, IconData icon, ImportMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          height: AppTheme.controlHeightLg,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.bg3,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.borderLight,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.onAccent : AppTheme.fgDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected ? AppTheme.onAccent : AppTheme.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
