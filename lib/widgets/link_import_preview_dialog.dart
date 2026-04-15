import 'package:flutter/material.dart';

import '../core/session/qr_codec.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'data_checkboxes.dart';
import 'mode_button.dart';

/// Result from the link/QR import preview dialog.
typedef LinkImportPreviewResult = ({ImportMode mode, ExportOptions options});

/// Preview dialog for `letsflutssh://import?...` deep links and scanned QR
/// payloads.
///
/// Mirrors [LfsImportPreviewDialog] — same preset chips, collapsible
/// checkboxes section and merge/replace mode selector — but drives its
/// counts from an in-memory [ExportPayloadData] instead of a decrypted
/// archive. That way the user can opt into/out of every data type the same
/// way they can for archive imports, and pick between merge and replace
/// semantics.
class LinkImportPreviewDialog extends StatefulWidget {
  final ExportPayloadData payload;

  const LinkImportPreviewDialog({super.key, required this.payload});

  static Future<LinkImportPreviewResult?> show(
    BuildContext context, {
    required ExportPayloadData payload,
  }) {
    return AppDialog.show<LinkImportPreviewResult>(
      context,
      builder: (_) => LinkImportPreviewDialog(payload: payload),
    );
  }

  @override
  State<LinkImportPreviewDialog> createState() =>
      _LinkImportPreviewDialogState();
}

class _LinkImportPreviewDialogState extends State<LinkImportPreviewDialog> {
  var _mode = ImportMode.merge;
  bool _checkboxesExpanded = true;
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = _fullPreset;
  }

  static const ExportOptions _fullPreset = ExportOptions(
    includeSessions: true,
    includeConfig: true,
    includeKnownHosts: true,
    includeAllManagerKeys: true,
    includeTags: true,
    includeSnippets: true,
  );

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
    Navigator.pop(context, (mode: _mode, options: _options));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceHeader(),
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

  Widget _buildSourceHeader() {
    return Row(
      children: [
        Icon(Icons.link, size: 16, color: AppTheme.fgDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            S.of(context).pasteImportLinkTitle,
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
    final p = widget.payload;
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
          trailingLabel: '${p.sessions.length}',
        ),
        DataCheckboxRow(
          icon: Icons.settings,
          label: S.of(context).appSettings,
          value: _options.includeConfig,
          onTap: () => setState(
            () =>
                _options = _options.withIncludeConfig(!_options.includeConfig),
          ),
          trailingLabel: p.hasConfig ? yes : no,
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
          trailingLabel: '${p.managerKeys.length}',
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
          trailingLabel: '${p.managerKeys.length}',
        ),
        DataCheckboxRow(
          icon: Icons.label_outline,
          label: S.of(context).tags,
          value: _options.includeTags,
          onTap: () => setState(
            () => _options = _options.withIncludeTags(!_options.includeTags),
          ),
          trailingLabel: '${p.tags.length}',
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
          trailingLabel: '${p.snippets.length}',
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
          trailingLabel: p.hasKnownHosts ? yes : no,
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
