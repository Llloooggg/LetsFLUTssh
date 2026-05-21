import 'package:flutter/material.dart';

import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../core/shortcut_registry.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_divider.dart';
import '../core/app_picker_chip.dart';
import '../core/data_checkboxes.dart';
import '../core/hover_region.dart';
import '../core/toast.dart';
import 'unified_export_controller.dart';
import 'unified_export_models.dart';
export 'unified_export_models.dart'
    show UnifiedExportDialogData, UnifiedExportResult;

part 'unified_export_dialog_tree.dart';

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
      Toast.show(
        context,
        message: S.of(context).qrTooManyForSingleCode,
        level: ToastLevel.warning,
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
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          16,
                          16,
                          0,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPresets(),
                              _buildCheckboxesSection(),
                              if (widget.isQrMode) _buildQrSecurityWarning(),
                              const AppDivider(),
                              const SizedBox(height: AppSpacing.xs),
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        12,
                        16,
                        12,
                      ),
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
                        AppButton.cancel(
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        AppButton.primary(
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
          // `AppPickerChip` paints the active state synchronously
          // — Material's `ChoiceChip` cross-fades through the
          // previously-selected chip's tint before the accent
          // settles. Matches the import-preview + keygen pickers.
          children: [
            AppPickerChip(
              active: _ctrl.activePreset == ExportPreset.fullBackup,
              label: S.of(context).fullBackup,
              icon: Icons.backup,
              expand: false,
              onTap: _ctrl.applyFullBackupPreset,
            ),
            AppPickerChip(
              active: _ctrl.activePreset == ExportPreset.sessions,
              label: S.of(context).sessionsOnly,
              icon: Icons.dns,
              expand: false,
              onTap: _ctrl.applySessionsPreset,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
        // Recordings live on the filesystem under `<appSupport>/recordings/`,
        // not in `letsflutssh.db`; the QR composer does not bundle them.
        // Hide the row in QR mode and when the folder is empty, matching
        // the knownHosts / tags row guards above.
        if (!widget.isQrMode && _ctrl.recordingsSize > 0)
          _buildCheckboxRow(
            Icons.fiber_manual_record_outlined,
            s.exportRecordings,
            opts.includeRecordings,
            () => _ctrl.setIncludeRecordings(!opts.includeRecordings),
            UnifiedExportController.formatSize(_ctrl.recordingsSize),
          ),
      ],
    );
  }

  Widget _buildQrSecurityWarning() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
          const SizedBox(width: AppSpacing.sm),
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
