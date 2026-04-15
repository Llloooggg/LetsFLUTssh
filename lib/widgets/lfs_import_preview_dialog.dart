import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/session/qr_codec.dart';
import '../../features/settings/export_import.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'app_dialog.dart';
import 'data_checkboxes.dart';
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
/// Layout mirrors the export dialog: preset chips on top, a collapsible
/// "What to import" section with every supported data type listed with its
/// count on the right, followed by the merge/replace mode selector.
///
/// Every checkbox is always clickable regardless of archive contents. That
/// matters for replace mode, where checking a type with zero entries in the
/// archive is a deliberate "wipe it out" intent — the checkbox state carries
/// through to [ImportResult.includeTags] / `includeSnippets` /
/// `includeKnownHosts` and `ImportService` honors it.
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
  bool _checkboxesExpanded = true;
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = _fullPreset;
  }

  /// Full import — every type ON, including types the archive doesn't carry.
  /// Reason: in replace mode the checkbox intent is authoritative (checked +
  /// empty archive = wipe), so the preset has to surface that toggle up front.
  static const ExportOptions _fullPreset = ExportOptions(
    includeSessions: true,
    includeConfig: true,
    includeKnownHosts: true,
    includeAllManagerKeys: true,
    includeTags: true,
    includeSnippets: true,
  );

  /// Selective: sessions only plus session-linked keys/tags/snippets so
  /// foreign keys resolve. Known hosts and config stay OFF.
  static const ExportOptions _selectivePreset = ExportOptions(
    includeSessions: true,
    includeManagerKeys: true,
    includeTags: true,
    includeSnippets: true,
  );

  bool _isPresetActive(ExportOptions preset) => _options == preset;

  String _activePresetLabel() {
    final s = S.of(context);
    if (_isPresetActive(_fullPreset)) return s.presetFullImport;
    if (_isPresetActive(_selectivePreset)) return s.presetSelective;
    return s.presetCustom;
  }

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilename(),
          const SizedBox(height: 12),
          _buildPresets(),
          const SizedBox(height: 8),
          _buildCheckboxesSection(),
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

  Widget _buildFilename() {
    return Row(
      children: [
        Icon(Icons.archive_outlined, size: 16, color: AppTheme.fgDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            p.basename(widget.filePath),
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

  Widget _buildCheckboxesSection() {
    return CollapsibleCheckboxesSection(
      title: S.of(context).importWhatToImport,
      trailingLabel: _activePresetLabel(),
      expanded: _checkboxesExpanded,
      onToggle: () =>
          setState(() => _checkboxesExpanded = !_checkboxesExpanded),
      body: _buildDataCheckboxes(),
    );
  }

  Widget _buildDataCheckboxes() {
    final preview = widget.preview;
    final yes = S.of(context).yes;
    final no = S.of(context).no;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataCheckboxRow(
          icon: Icons.computer,
          label: S.of(context).sessions,
          value: _options.includeSessions,
          onTap: () => setState(
            () => _options = _options.withIncludeSessions(
              !_options.includeSessions,
            ),
          ),
          trailingLabel: '${preview.sessions.length}',
        ),
        DataCheckboxRow(
          icon: Icons.settings,
          label: S.of(context).appSettings,
          value: _options.includeConfig,
          onTap: () => setState(
            () =>
                _options = _options.withIncludeConfig(!_options.includeConfig),
          ),
          trailingLabel: preview.hasConfig ? yes : no,
        ),
        DataCheckboxRow(
          icon: Icons.vpn_key,
          label: S.of(context).sessionSshKeys,
          value: _options.includeManagerKeys,
          onTap: () => setState(
            () => _options = _options
                .withIncludeManagerKeys(!_options.includeManagerKeys)
                .withIncludeAllManagerKeys(false),
          ),
          trailingLabel: '${preview.managerKeyCount}',
        ),
        DataCheckboxRow(
          icon: Icons.cloud_done,
          label: S.of(context).allManagerKeys,
          value: _options.includeAllManagerKeys,
          onTap: () => setState(
            () => _options = _options
                .withIncludeAllManagerKeys(!_options.includeAllManagerKeys)
                .withIncludeManagerKeys(false),
          ),
          trailingLabel: '${preview.managerKeyCount}',
        ),
        DataCheckboxRow(
          icon: Icons.label_outline,
          label: S.of(context).tags,
          value: _options.includeTags,
          onTap: () => setState(
            () => _options = _options.withIncludeTags(!_options.includeTags),
          ),
          trailingLabel: '${preview.tagCount}',
        ),
        DataCheckboxRow(
          icon: Icons.code,
          label: S.of(context).snippets,
          value: _options.includeSnippets,
          onTap: () => setState(
            () => _options = _options.withIncludeSnippets(
              !_options.includeSnippets,
            ),
          ),
          trailingLabel: '${preview.snippetCount}',
        ),
        DataCheckboxRow(
          icon: Icons.verified_user,
          label: S.of(context).knownHosts,
          value: _options.includeKnownHosts,
          onTap: () => setState(
            () => _options = _options.withIncludeKnownHosts(
              !_options.includeKnownHosts,
            ),
          ),
          trailingLabel: preview.hasKnownHosts ? yes : no,
        ),
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
