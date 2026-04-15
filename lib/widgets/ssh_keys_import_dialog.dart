import 'package:flutter/material.dart';

import '../core/import/ssh_dir_key_scanner.dart';
import '../core/security/key_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'hover_region.dart';

/// Dialog for selecting which scanned SSH keys to import.
///
/// Shows a checkbox per discovered key file. Keys whose fingerprint is
/// already in [existingFingerprints] are flagged with a badge and start
/// unchecked — they would dedup to no-ops anyway, so opting in must be
/// explicit. Returns the list of selected keys when the user confirms,
/// or null on cancel.
class SshKeysImportDialog extends StatefulWidget {
  final List<ScannedKey> candidates;
  final Set<String> existingFingerprints;

  const SshKeysImportDialog({
    super.key,
    required this.candidates,
    this.existingFingerprints = const {},
  });

  static Future<List<ScannedKey>?> show(
    BuildContext context, {
    required List<ScannedKey> candidates,
    Set<String> existingFingerprints = const {},
  }) => AppDialog.show<List<ScannedKey>>(
    context,
    builder: (_) => SshKeysImportDialog(
      candidates: candidates,
      existingFingerprints: existingFingerprints,
    ),
  );

  @override
  State<SshKeysImportDialog> createState() => _SshKeysImportDialogState();
}

class _SshKeysImportDialogState extends State<SshKeysImportDialog> {
  late final List<bool> _selected;
  late final List<bool> _alreadyImported;

  @override
  void initState() {
    super.initState();
    _alreadyImported = widget.candidates
        .map(
          (k) => widget.existingFingerprints.contains(
            KeyStore.privateKeyFingerprint(k.pem),
          ),
        )
        .toList();
    // Default-uncheck the ones already in the store.
    _selected = _alreadyImported.map((existing) => !existing).toList();
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
    final existing = _alreadyImported[i];
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          key.suggestedLabel,
                          style: AppFonts.inter(
                            fontSize: AppFonts.md,
                            color: existing ? AppTheme.fgDim : AppTheme.fg,
                          ),
                        ),
                      ),
                      if (existing) ...[
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).sshKeyAlreadyImported,
                          style: AppFonts.inter(
                            fontSize: AppFonts.xs,
                            color: AppTheme.yellow,
                          ),
                        ),
                      ],
                    ],
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
