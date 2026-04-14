import 'package:flutter/material.dart';

import '../core/import/ssh_dir_key_scanner.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'hover_region.dart';

/// Dialog for selecting which scanned SSH keys to import.
///
/// Shows a checkbox per discovered key file. Returns the list of selected
/// keys when the user confirms, or null on cancel. All boxes start checked
/// since the user explicitly opened the picker to import — unchecking is
/// an exclusion workflow, not an inclusion one.
class SshKeysImportDialog extends StatefulWidget {
  final List<ScannedKey> candidates;

  const SshKeysImportDialog({super.key, required this.candidates});

  static Future<List<ScannedKey>?> show(
    BuildContext context, {
    required List<ScannedKey> candidates,
  }) => AppDialog.show<List<ScannedKey>>(
    context,
    builder: (_) => SshKeysImportDialog(candidates: candidates),
  );

  @override
  State<SshKeysImportDialog> createState() => _SshKeysImportDialogState();
}

class _SshKeysImportDialogState extends State<SshKeysImportDialog> {
  late final List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.filled(widget.candidates.length, true);
  }

  bool get _hasAnySelection => _selected.any((v) => v);

  void _submit() {
    final picked = <ScannedKey>[];
    for (var i = 0; i < widget.candidates.length; i++) {
      if (_selected[i]) picked.add(widget.candidates[i]);
    }
    Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final empty = widget.candidates.isEmpty;

    return AppDialog(
      title: s.importSshKeysTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            empty
                ? s.importSshKeysNoneFound
                : s.importSshKeysFound(widget.candidates.length),
            style: AppFonts.inter(fontSize: AppFonts.md),
          ),
          if (!empty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < widget.candidates.length; i++)
                      _buildRow(i),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: s.importData,
          enabled: !empty && _hasAnySelection,
          onTap: _submit,
        ),
      ],
    );
  }

  Widget _buildRow(int i) {
    final key = widget.candidates[i];
    final checked = _selected[i];
    return HoverRegion(
      onTap: () => setState(() => _selected[i] = !checked),
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => setState(() => _selected[i] = v ?? false),
            ),
            const Icon(Icons.vpn_key, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key.suggestedLabel,
                    style: AppFonts.inter(
                      fontSize: AppFonts.md,
                      color: AppTheme.fg,
                    ),
                  ),
                  Text(
                    key.path,
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
