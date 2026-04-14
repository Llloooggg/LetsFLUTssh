import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/session/qr_codec.dart';
import '../../features/settings/export_import.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'app_dialog.dart';
import 'hover_region.dart';
import 'mode_button.dart';

/// Result from the LFS import preview dialog.
///
/// The master password is NOT part of this result — the caller must have
/// already decrypted the archive to build the [LfsPreview], so it already
/// has the password in hand.
typedef LfsImportPreviewResult = ({
  String filePath,
  ImportMode mode,
  ExportOptions options,
});

/// Dialog for previewing .lfs archive and selecting what data to import.
///
/// Shows archive contents (sessions count, has config, has known_hosts),
/// allows user to select what to import and choose import mode.
class LfsImportPreviewDialog extends StatefulWidget {
  final String filePath;
  final LfsPreview preview;

  const LfsImportPreviewDialog({
    super.key,
    required this.filePath,
    required this.preview,
  });

  /// Show the dialog and return the result.
  static Future<LfsImportPreviewResult?> show(
    BuildContext context, {
    required String filePath,
    required LfsPreview preview,
  }) {
    return AppDialog.show<LfsImportPreviewResult>(
      context,
      builder: (_) =>
          LfsImportPreviewDialog(filePath: filePath, preview: preview),
    );
  }

  @override
  State<LfsImportPreviewDialog> createState() => _LfsImportPreviewDialogState();
}

class _LfsImportPreviewDialogState extends State<LfsImportPreviewDialog> {
  var _mode = ImportMode.merge;
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = _fullPreset;
  }

  /// Full import: every data type present in the archive is ON. All manager
  /// keys stay OFF by default — opt-in, since it overwrites the local
  /// manager (the conservative "session keys only" flag captures what the
  /// imported sessions actually reference).
  ExportOptions get _fullPreset => ExportOptions(
    includeSessions: widget.preview.hasSessions,
    includeConfig: widget.preview.hasConfig,
    includeKnownHosts: widget.preview.hasKnownHosts,
    includeManagerKeys: widget.preview.managerKeyCount > 0,
    includeTags: widget.preview.tagCount > 0,
    includeSnippets: widget.preview.snippetCount > 0,
  );

  /// Selective: sessions only (plus session-linked keys/tags/snippets so
  /// foreign keys resolve). Known hosts and config stay OFF.
  ExportOptions get _selectivePreset => ExportOptions(
    includeSessions: widget.preview.hasSessions,
    includeManagerKeys: widget.preview.managerKeyCount > 0,
    includeTags: widget.preview.tagCount > 0,
    includeSnippets: widget.preview.snippetCount > 0,
  );

  bool _isPresetActive(ExportOptions preset) => _options == preset;

  void _submit() {
    if (!_options.hasAnySelection) return;
    Navigator.pop(context, (
      filePath: widget.filePath,
      mode: _mode,
      options: _options,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildArchiveInfo(),
          const SizedBox(height: 12),
          _buildPresets(),
          const SizedBox(height: 8),
          _buildDataTypeCheckboxes(),
          const SizedBox(height: 12),
          _buildModeSelector(),
          const SizedBox(height: 4),
          Text(
            _mode == ImportMode.merge
                ? S.of(context).importModeMergeDescription
                : S.of(context).importModeReplaceDescription,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).import_,
          enabled: _options.hasAnySelection,
          onTap: _submit,
        ),
      ],
    );
  }

  Widget _buildArchiveInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.basename(widget.filePath),
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.computer,
            S.of(context).sessions,
            widget.preview.hasSessions
                ? '${widget.preview.sessions.length}'
                : '—',
          ),
          if (widget.preview.emptyFolders.isNotEmpty)
            _buildInfoRow(
              Icons.folder,
              S.of(context).emptyFolders,
              '${widget.preview.emptyFoldersCount}',
            ),
          _buildInfoRow(
            Icons.vpn_key,
            S.of(context).sshKeys,
            '${widget.preview.managerKeyCount}',
          ),
          _buildInfoRow(
            Icons.label_outline,
            S.of(context).tags,
            '${widget.preview.tagCount}',
          ),
          _buildInfoRow(
            Icons.code,
            S.of(context).snippets,
            '${widget.preview.snippetCount}',
          ),
          _buildInfoRow(
            Icons.settings,
            S.of(context).appSettings,
            widget.preview.hasConfig ? S.of(context).yes : S.of(context).no,
          ),
          _buildInfoRow(
            Icons.verified_user,
            S.of(context).knownHosts,
            widget.preview.hasKnownHosts ? S.of(context).yes : S.of(context).no,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.fgDim),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w600,
                color: AppTheme.fg,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.download_for_offline, size: 18),
            label: Text(S.of(context).presetFullImport),
            selected: _isPresetActive(_fullPreset),
            selectedColor: AppTheme.accent.withValues(alpha: 0.2),
            onSelected: (_) => setState(() => _options = _fullPreset),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.filter_alt, size: 18),
            label: Text(S.of(context).presetSelective),
            selected: _isPresetActive(_selectivePreset),
            selectedColor: AppTheme.accent.withValues(alpha: 0.2),
            onSelected: (_) => setState(() => _options = _selectivePreset),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTypeCheckboxes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).importWhatToImport,
          style: AppFonts.inter(
            fontSize: AppFonts.sm,
            fontWeight: FontWeight.w600,
            color: AppTheme.fg,
          ),
        ),
        const SizedBox(height: 8),
        if (widget.preview.hasSessions)
          _buildCheckbox(
            Icons.computer,
            S.of(context).sessions,
            _options.includeSessions,
            (v) => setState(() => _options = _options.withIncludeSessions(v)),
          ),
        if (widget.preview.hasConfig)
          _buildCheckbox(
            Icons.settings,
            S.of(context).appSettings,
            _options.includeConfig,
            (v) => setState(() => _options = _options.withIncludeConfig(v)),
          ),
        if (widget.preview.managerKeyCount > 0) ...[
          _buildCheckbox(
            Icons.vpn_key,
            S.of(context).sessionSshKeys,
            _options.includeManagerKeys,
            (v) => setState(
              () => _options = _options
                  .withIncludeManagerKeys(v)
                  .withIncludeAllManagerKeys(false),
            ),
          ),
          _buildCheckbox(
            Icons.cloud_done,
            S.of(context).allManagerKeys,
            _options.includeAllManagerKeys,
            (v) => setState(
              () => _options = _options
                  .withIncludeAllManagerKeys(v)
                  .withIncludeManagerKeys(false),
            ),
          ),
        ],
        _buildCheckbox(
          Icons.label_outline,
          S.of(context).tags,
          _options.includeTags,
          (v) => setState(() => _options = _options.withIncludeTags(v)),
        ),
        _buildCheckbox(
          Icons.code,
          S.of(context).snippets,
          _options.includeSnippets,
          (v) => setState(() => _options = _options.withIncludeSnippets(v)),
        ),
        if (widget.preview.hasKnownHosts)
          _buildCheckbox(
            Icons.verified_user,
            S.of(context).knownHosts,
            _options.includeKnownHosts,
            (v) => setState(() => _options = _options.withIncludeKnownHosts(v)),
          ),
      ],
    );
  }

  Widget _buildCheckbox(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return HoverRegion(
      onTap: () => onChanged(!value),
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            Icon(icon, size: 16, color: AppTheme.fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.inter(fontSize: AppFonts.md, color: AppTheme.fg),
            ),
          ],
        ),
      ),
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
