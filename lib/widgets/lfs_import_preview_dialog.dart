import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/session/qr_codec.dart';
import '../../features/settings/export_import.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'app_dialog.dart';
import 'hover_region.dart';
import 'mode_button.dart';
import 'styled_form_field.dart';

/// Result from the LFS import preview dialog.
typedef LfsImportPreviewResult = ({
  String filePath,
  String password,
  ImportMode mode,
  ExportOptions options,
});

/// Dialog for previewing .lfs archive and selecting what data to import.
///
/// Shows archive contents (sessions count, has config, has known_hosts),
/// allows user to select what to import, choose import mode, and enter password.
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
  final _passwordCtrl = TextEditingController();
  var _mode = ImportMode.merge;
  late ExportOptions _options;

  @override
  void initState() {
    super.initState();
    // Initialize options based on what's available in the archive.
    // Sessions, keys, tags, snippets, known_hosts default to enabled.
    // Config defaults to disabled — importing config would overwrite the
    // user's local app settings (theme, locale, font size, etc.).
    _options = ExportOptions(
      includeSessions: widget.preview.hasSessions,
      includeConfig: false,
      includeKnownHosts: widget.preview.hasKnownHosts,
      includeManagerKeys: widget.preview.managerKeyCount > 0,
      includeTags: widget.preview.tagCount > 0,
      includeSnippets: widget.preview.snippetCount > 0,
    );
    _passwordCtrl.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordCtrl.removeListener(_onPasswordChanged);
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  void _submit() {
    if (_passwordCtrl.text.isEmpty) return;
    if (!_options.hasAnySelection) return;

    Navigator.pop(context, (
      filePath: widget.filePath,
      password: _passwordCtrl.text,
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
          // Archive info
          _buildArchiveInfo(),
          const SizedBox(height: 16),

          // Data type checkboxes
          _buildDataTypeCheckboxes(),
          const SizedBox(height: 12),

          // Password input
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
              if (v.isNotEmpty && _options.hasAnySelection) {
                _submit();
              }
            },
          ),
          const SizedBox(height: 12),

          // Mode selector
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
        AppDialogAction.primary(
          label: S.of(context).import_,
          enabled: _passwordCtrl.text.isNotEmpty && _options.hasAnySelection,
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
            style: TextStyle(
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
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
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

  Widget _buildDataTypeCheckboxes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).importWhatToImport,
          style: TextStyle(
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
            (v) => setState(
              () => _options = _options.copyWith(includeSessions: v),
            ),
          ),
        if (widget.preview.hasConfig)
          _buildCheckbox(
            Icons.settings,
            S.of(context).appSettings,
            _options.includeConfig,
            (v) =>
                setState(() => _options = _options.copyWith(includeConfig: v)),
          ),
        _buildCheckbox(
          Icons.vpn_key,
          S.of(context).sshKeys,
          _options.includeManagerKeys,
          (v) => setState(
            () => _options = _options.copyWith(includeManagerKeys: v),
          ),
        ),
        _buildCheckbox(
          Icons.label_outline,
          S.of(context).tags,
          _options.includeTags,
          (v) => setState(() => _options = _options.copyWith(includeTags: v)),
        ),
        _buildCheckbox(
          Icons.code,
          S.of(context).snippets,
          _options.includeSnippets,
          (v) =>
              setState(() => _options = _options.copyWith(includeSnippets: v)),
        ),
        if (widget.preview.hasKnownHosts)
          _buildCheckbox(
            Icons.verified_user,
            S.of(context).knownHosts,
            _options.includeKnownHosts,
            (v) => setState(
              () => _options = _options.copyWith(includeKnownHosts: v),
            ),
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
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
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
