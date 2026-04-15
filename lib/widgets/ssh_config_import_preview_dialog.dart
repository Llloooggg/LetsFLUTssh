import 'package:flutter/material.dart';

import '../core/import/openssh_config_importer.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'hover_region.dart';

/// Preview dialog for the `~/.ssh/config` importer.
///
/// Renders every parsed host as a checkbox row so the user can cherry-pick
/// which hosts to import. Returns the filtered [ImportResult] on accept
/// (sessions + only the manager keys referenced by the kept sessions),
/// or null on cancel.
class SshConfigImportPreviewDialog extends StatefulWidget {
  final OpenSshConfigImportPreview preview;
  final String folderLabel;

  const SshConfigImportPreviewDialog({
    super.key,
    required this.preview,
    required this.folderLabel,
  });

  static Future<ImportResult?> show(
    BuildContext context, {
    required OpenSshConfigImportPreview preview,
    required String folderLabel,
  }) => AppDialog.show<ImportResult>(
    context,
    builder: (_) => SshConfigImportPreviewDialog(
      preview: preview,
      folderLabel: folderLabel,
    ),
  );

  @override
  State<SshConfigImportPreviewDialog> createState() =>
      _SshConfigImportPreviewDialogState();
}

class _SshConfigImportPreviewDialogState
    extends State<SshConfigImportPreviewDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.preview.result.sessions.map((s) => s.id).toSet();
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds = widget.preview.result.sessions.map((s) => s.id).toSet();
      } else {
        _selectedIds = {};
      }
    });
  }

  ImportResult _buildFilteredResult() {
    final selectedSessions = widget.preview.result.sessions
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    // Keep only manager keys referenced by the kept sessions so unselected
    // hosts don't silently import their identity file into the key manager.
    final referencedKeyIds = selectedSessions
        .map((s) => s.keyId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final filteredKeys = widget.preview.result.managerKeys
        .where((k) => referencedKeyIds.contains(k.id))
        .toList();
    return ImportResult(
      sessions: selectedSessions,
      managerKeys: filteredKeys,
      mode: widget.preview.result.mode,
      emptyFolders: selectedSessions.isEmpty ? const {} : {widget.folderLabel},
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final allSessions = widget.preview.result.sessions;
    final hasHosts = allSessions.isNotEmpty;
    final allSelected = _selectedIds.length == allSessions.length;
    final noneSelected = _selectedIds.isEmpty;
    final tristate = allSelected
        ? true
        : noneSelected
        ? false
        : null;

    return AppDialog(
      title: s.sshConfigPreviewTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasHosts
                ? s.sshConfigPreviewHostsFound(allSessions.length)
                : s.sshConfigPreviewNoHosts,
            style: AppFonts.inter(fontSize: AppFonts.md),
          ),
          if (hasHosts) ...[
            const SizedBox(height: 8),
            Text(
              s.sshConfigPreviewFolderLabel(widget.folderLabel),
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
              ),
            ),
            const SizedBox(height: 8),
            HoverRegion(
              onTap: () => _toggleAll(tristate != true),
              builder: (hovered) => Container(
                color: hovered ? AppTheme.hover : null,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: tristate,
                      tristate: true,
                      onChanged: _toggleAll,
                    ),
                    Text(
                      '${_selectedIds.length} / ${allSessions.length}',
                      style: AppFonts.inter(
                        fontSize: AppFonts.sm,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _HostList(
              sessions: allSessions,
              selected: _selectedIds,
              onToggle: _toggle,
            ),
            if (widget.preview.hostsWithMissingKeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                s.sshConfigPreviewMissingKeys(
                  widget.preview.hostsWithMissingKeys.join(', '),
                ),
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.yellow,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: s.importData,
          enabled: hasHosts && _selectedIds.isNotEmpty,
          onTap: () => Navigator.pop(context, _buildFilteredResult()),
        ),
      ],
    );
  }
}

class _HostList extends StatelessWidget {
  final List sessions;
  final Set<String> selected;
  final void Function(String id) onToggle;

  const _HostList({
    required this.sessions,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in sessions)
              HoverRegion(
                onTap: () => onToggle(s.id),
                builder: (hovered) => Container(
                  color: hovered ? AppTheme.hover : null,
                  child: Row(
                    children: [
                      Checkbox(
                        value: selected.contains(s.id),
                        onChanged: (_) => onToggle(s.id),
                      ),
                      Expanded(
                        child: Text(
                          '${s.label}  —  ${s.user.isEmpty ? '?' : s.user}'
                          '@${s.host}:${s.port}'
                          '${s.keyId.isNotEmpty ? '  (key)' : ''}',
                          style: AppFonts.mono(fontSize: AppFonts.sm),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
