import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/security/key_store.dart';
import '../core/session/qr_codec.dart';
import '../core/session/session.dart';
import '../core/session/session_tree.dart';
import '../core/shortcut_registry.dart';
import '../core/snippets/snippet.dart';
import '../core/tags/tag.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_divider.dart';
import 'data_checkboxes.dart';
import 'hover_region.dart';
import 'unified_export_controller.dart';

part 'unified_export_dialog_tree.dart';

/// Bundle of data displayed by [UnifiedExportDialog]. Groups related
/// optional parameters so the dialog's `show()` stays small.
class UnifiedExportDialogData {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final AppConfig? config;
  final String? knownHostsContent;

  /// Map of keyId -> keyData for keys stored in the manager.
  /// Used for QR-mode manager key size estimation.
  final Map<String, String> managerKeys;

  /// Full SshKeyEntry map for .lfs archive size estimation.
  final Map<String, SshKeyEntry> managerKeyEntries;

  /// All tags for size calculation and export.
  final List<Tag> tags;

  /// All snippets for size calculation and export.
  final List<Snippet> snippets;

  const UnifiedExportDialogData({
    required this.sessions,
    required this.emptyFolders,
    this.config,
    this.knownHostsContent,
    this.managerKeys = const {},
    this.managerKeyEntries = const {},
    this.tags = const [],
    this.snippets = const [],
  });
}

/// Unified export dialog for both QR code and .lfs archive export.
class UnifiedExportDialog extends StatefulWidget {
  final UnifiedExportDialogData data;
  final bool isQrMode;

  const UnifiedExportDialog({
    super.key,
    required this.data,
    this.isQrMode = false,
  });

  static Future<UnifiedExportResult?> show(
    BuildContext context, {
    required UnifiedExportDialogData data,
    bool isQrMode = false,
  }) {
    return AppDialog.show<UnifiedExportResult>(
      context,
      builder: (_) => UnifiedExportDialog(data: data, isQrMode: isQrMode),
    );
  }

  @override
  State<UnifiedExportDialog> createState() => _UnifiedExportDialogState();
}

class _UnifiedExportDialogState extends State<UnifiedExportDialog> {
  late final UnifiedExportController _ctrl;

  @override
  void initState() {
    super.initState();
    // QR mode: mirror "Sessions only" preset without keys — sessions,
    // passwords, tags, snippets ON; keys and app-wide config OFF. Keys
    // drive QR payload growth, so they are opt-in for QR.
    // .lfs mode: all credentials ON (encrypted archive, user expects
    // full backup).
    _ctrl = UnifiedExportController(
      data: widget.data,
      isQrMode: widget.isQrMode,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _activePresetLabel() {
    final s = S.of(context);
    switch (_ctrl.activePreset) {
      case ExportPreset.fullBackup:
        return s.fullBackup;
      case ExportPreset.sessions:
        return s.sessionsOnly;
      case ExportPreset.custom:
        return s.presetCustom;
    }
  }

  void _export() {
    if (!_ctrl.fitsInQr) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).qrTooManyForSingleCode),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    Navigator.of(context).pop(_ctrl.buildResult());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final tree = SessionTree.build(
          widget.data.sessions,
          emptyFolders: widget.data.emptyFolders,
        );
        final sizePercent = widget.isQrMode && qrMaxPayloadBytes > 0
            ? (_ctrl.payloadSize / qrMaxPayloadBytes).clamp(0.0, 1.0)
            : 0.0;
        final sizeColor = _ctrl.fitsInQr ? AppTheme.green : AppTheme.red;

        return Dialog(
          backgroundColor: AppTheme.bg1,
          insetPadding: const EdgeInsets.all(24),
          child: CallbackShortcuts(
            bindings: AppShortcutRegistry.instance.buildCallbackMap({
              AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
            }),
            child: Focus(
              autofocus: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppDialogHeader(
                      title: widget.isQrMode
                          ? S.of(context).exportSessionsViaQr
                          : S.of(context).exportData,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPresets(),
                              _buildCheckboxesSection(),
                              if (widget.isQrMode) _buildQrSecurityWarning(),
                              const AppDivider(),
                              const SizedBox(height: 4),
                              _buildSelectAll(),
                              const AppDivider(),
                              ListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: _buildTreeItems(tree, 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Size indicator pinned below the scroll region so
                    // it stays visible regardless of how much content is
                    // above — content scrolls under it instead of
                    // pushing it out of view.
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bg1,
                        border: Border(
                          top: BorderSide(color: AppTheme.borderLight),
                        ),
                      ),
                      child: _buildSizeIndicator(sizePercent, sizeColor),
                    ),
                    AppDialogFooter(
                      actions: [
                        AppDialogAction.cancel(
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        AppDialogAction.primary(
                          label: widget.isQrMode
                              ? S.of(context).showQr
                              : S.of(context).export_,
                          enabled: _ctrl.hasSelection && _ctrl.fitsInQr,
                          onTap: _export,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.backup, size: 18),
              label: Text(S.of(context).fullBackup),
              selected: _ctrl.activePreset == ExportPreset.fullBackup,
              selectedColor: AppTheme.accent.withValues(alpha: 0.2),
              showCheckmark: false,
              onSelected: (_) => _ctrl.applyFullBackupPreset(),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.dns, size: 18),
              label: Text(S.of(context).sessionsOnly),
              selected: _ctrl.activePreset == ExportPreset.sessions,
              selectedColor: AppTheme.accent.withValues(alpha: 0.2),
              showCheckmark: false,
              onSelected: (_) => _ctrl.applySessionsPreset(),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCheckboxesSection() {
    return CollapsibleCheckboxesSection(
      title: S.of(context).exportWhatToExport,
      trailingLabel: _activePresetLabel(),
      expanded: _ctrl.checkboxesExpanded,
      onToggle: _ctrl.toggleCheckboxes,
      body: _buildDataCheckboxes(),
    );
  }

  Widget _buildDataCheckboxes() {
    final s = S.of(context);
    final opts = _ctrl.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data.config != null)
          _buildCheckboxRow(
            Icons.settings,
            s.appSettings,
            opts.includeConfig,
            () => _ctrl.setIncludeConfig(!opts.includeConfig),
            UnifiedExportController.formatSize(_ctrl.configSize),
          ),
        _buildCheckboxRow(
          Icons.lock,
          s.includePasswords,
          opts.includePasswords,
          () => _ctrl.setIncludePasswords(!opts.includePasswords),
          UnifiedExportController.formatSize(_ctrl.passwordsExtraSize),
        ),
        _buildCheckboxRow(
          Icons.key,
          s.embeddedKeys,
          opts.includeEmbeddedKeys,
          () => _ctrl.setIncludeEmbeddedKeys(!opts.includeEmbeddedKeys),
          UnifiedExportController.formatSize(_ctrl.embeddedKeysExtraSize),
          warningText: _ctrl.showEmbeddedKeysWarning
              ? s.sshKeysMayBeLarge
              : null,
        ),
        _buildCheckboxRow(
          Icons.vpn_key,
          s.sessionSshKeys,
          opts.includeManagerKeys,
          () => _ctrl.setIncludeManagerKeys(!opts.includeManagerKeys),
          UnifiedExportController.formatSize(_ctrl.managerKeysExtraSize),
          warningText: _ctrl.showManagerKeysWarning
              ? s.managerKeysMayBeLarge
              : null,
        ),
        _buildCheckboxRow(
          Icons.cloud_done,
          s.allManagerKeys,
          opts.includeAllManagerKeys,
          () => _ctrl.setIncludeAllManagerKeys(!opts.includeAllManagerKeys),
          UnifiedExportController.formatSize(_ctrl.managerKeysExtraSize),
          warningText: _ctrl.showAllManagerKeysWarning
              ? s.managerKeysMayBeLarge
              : null,
        ),
        if (widget.data.knownHostsContent?.isNotEmpty == true)
          _buildCheckboxRow(
            Icons.verified_user,
            s.knownHosts,
            opts.includeKnownHosts,
            () => _ctrl.setIncludeKnownHosts(!opts.includeKnownHosts),
            UnifiedExportController.formatSize(_ctrl.knownHostsSize),
          ),
        _buildCheckboxRow(
          Icons.label_outline,
          s.tags,
          opts.includeTags,
          () => _ctrl.setIncludeTags(!opts.includeTags),
          UnifiedExportController.formatSize(_ctrl.tagsSize),
        ),
        _buildCheckboxRow(
          Icons.code,
          s.snippets,
          opts.includeSnippets,
          () => _ctrl.setIncludeSnippets(!opts.includeSnippets),
          UnifiedExportController.formatSize(_ctrl.snippetsSize),
        ),
      ],
    );
  }

  Widget _buildQrSecurityWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: 0.1),
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 20, color: AppTheme.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.of(context).qrPasswordWarning,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxRow(
    IconData icon,
    String label,
    bool value,
    VoidCallback onTap,
    String? sizeLabel, {
    String? warningText,
  }) {
    return DataCheckboxRow(
      icon: icon,
      label: label,
      value: value,
      onTap: onTap,
      trailingLabel: sizeLabel,
      warningText: warningText,
    );
  }

  Widget _buildSelectAll() {
    return HoverRegion(
      onTap: () => _ctrl.toggleAll(!_ctrl.allSelected),
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Checkbox(
              value: _ctrl.tristateValue,
              tristate: true,
              onChanged: (v) => _ctrl.toggleAll(v == true),
            ),
            Text(
              S
                  .of(context)
                  .qrSelectAll(
                    _ctrl.selectedIds.length,
                    widget.data.sessions.length,
                  ),
              style: AppFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: AppFonts.md,
                color: AppTheme.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnifiedExportResult {
  final ExportOptions options;
  final List<Session> selectedSessions;
  final Set<String> selectedEmptyFolders;

  const UnifiedExportResult({
    required this.options,
    required this.selectedSessions,
    required this.selectedEmptyFolders,
  });
}
