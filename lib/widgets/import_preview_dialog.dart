import 'package:flutter/material.dart';

import '../core/session/qr_codec.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'data_checkboxes.dart';
import 'mode_button.dart';

/// Per-type counts surfaced by the import preview dialog. One record shape
/// shared by both archive (`.lfs`) and deep-link / QR payload sources so the
/// dialog itself stays agnostic of where the data came from.
typedef ImportPreviewCounts = ({
  int sessions,
  bool hasConfig,
  int managerKeys,
  int tags,
  int snippets,
  bool hasKnownHosts,
});

/// What the user chose in the preview dialog.
typedef ImportPreviewSelection = ({ImportMode mode, ExportOptions options});

/// Shared preview dialog body used by both LFS archive imports and deep-link /
/// QR imports.
///
/// Layout: caller-supplied [header] on top (archive filename row or link-title
/// row), two preset chips, collapsible "What to import" checkbox grid with
/// every supported data type and its count on the right, then the
/// merge/replace mode selector with its description line.
///
/// Every checkbox is always clickable regardless of [counts]. That matters in
/// replace mode, where checking a type with zero entries in the payload is a
/// deliberate "wipe it out" intent — the checkbox state carries through to
/// `ImportResult.includeX` and `ImportService` honors it.
class ImportPreviewDialog extends StatefulWidget {
  final Widget header;
  final ImportPreviewCounts counts;

  const ImportPreviewDialog({
    super.key,
    required this.header,
    required this.counts,
  });

  /// Show the dialog and return `(mode, options)` on Import, `null` on Cancel.
  static Future<ImportPreviewSelection?> show(
    BuildContext context, {
    required Widget header,
    required ImportPreviewCounts counts,
  }) {
    return AppDialog.show<ImportPreviewSelection>(
      context,
      builder: (_) => ImportPreviewDialog(header: header, counts: counts),
    );
  }

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  var _mode = ImportMode.merge;
  bool _checkboxesExpanded = true;
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    _options = _fullPreset;
  }

  /// Full import — every type ON, including types the payload doesn't carry.
  /// Reason: in replace mode the checkbox intent is authoritative (checked +
  /// empty payload = wipe), so the preset has to surface that toggle up front.
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
          widget.header,
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
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        AppButton.primary(
          label: S.of(context).import_,
          enabled: _options.hasAnySelection,
          onTap: _submit,
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
            showCheckmark: false,
            onSelected: (_) => setState(() => _options = _fullPreset),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.filter_alt, size: 18),
            label: Text(S.of(context).presetSelective),
            selected: _isPresetActive(_selectivePreset),
            selectedColor: AppTheme.accent.withValues(alpha: 0.2),
            showCheckmark: false,
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
    final c = widget.counts;
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
          trailingLabel: '${c.sessions}',
        ),
        DataCheckboxRow(
          icon: Icons.settings,
          label: S.of(context).appSettings,
          value: _options.includeConfig,
          onTap: () => setState(
            () =>
                _options = _options.withIncludeConfig(!_options.includeConfig),
          ),
          trailingLabel: c.hasConfig ? yes : no,
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
          trailingLabel: '${c.managerKeys}',
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
          trailingLabel: '${c.managerKeys}',
        ),
        DataCheckboxRow(
          icon: Icons.label_outline,
          label: S.of(context).tags,
          value: _options.includeTags,
          onTap: () => setState(
            () => _options = _options.withIncludeTags(!_options.includeTags),
          ),
          trailingLabel: '${c.tags}',
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
          trailingLabel: '${c.snippets}',
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
          trailingLabel: c.hasKnownHosts ? yes : no,
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
