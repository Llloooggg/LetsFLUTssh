import 'package:flutter/material.dart';

import '../core/import/openssh_config_importer.dart';
import '../core/import/ssh_dir_key_scanner.dart';
import '../core/security/key_store.dart';
import '../core/session/session.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'data_checkboxes.dart';

/// Input bundle for [SshDirImportDialog]. Groups the results of scanning
/// `~/.ssh` (keys) and parsing `~/.ssh/config` (hosts) so the dialog can
/// render both in a single pick-list and return one merged [ImportResult].
class SshDirImportSource {
  final OpenSshConfigImportPreview? hostsPreview;
  final List<ScannedKey> keys;
  final Set<String> existingKeyFingerprints;
  final String folderLabel;

  const SshDirImportSource({
    required this.hostsPreview,
    required this.keys,
    required this.folderLabel,
    this.existingKeyFingerprints = const {},
  });

  bool get hasHosts => (hostsPreview?.result.sessions.isNotEmpty ?? false);
  bool get hasKeys => keys.isNotEmpty;
}

/// Unified import dialog for `~/.ssh`.
///
/// Shows two collapsible sections using the shared [CollapsibleCheckboxesSection]
/// primitive so the layout matches the .lfs archive / export dialogs exactly
/// (same row metrics, same chevron, same tristate). Replaces the two separate
/// "Import OpenSSH config" and "Import SSH keys from ~/.ssh" dialogs.
///
/// The raw key rows need a path subtitle + "already in store" badge that the
/// generic [DataCheckboxRow] doesn't carry, so key rows are rendered with a
/// compatible layout (checkbox + icon + label + trailing).
///
/// Returns a combined [ImportResult] on accept, or null on cancel. Sessions
/// pointing to a deselected key get their keyId nulled by [ImportService]'s
/// FK-safety pass.
class SshDirImportDialog extends StatefulWidget {
  final SshDirImportSource source;

  const SshDirImportDialog({super.key, required this.source});

  static Future<ImportResult?> show(
    BuildContext context, {
    required SshDirImportSource source,
  }) => AppDialog.show<ImportResult>(
    context,
    builder: (_) => SshDirImportDialog(source: source),
  );

  @override
  State<SshDirImportDialog> createState() => _SshDirImportDialogState();
}

class _SshDirImportDialogState extends State<SshDirImportDialog> {
  late Set<String> _selectedHostIds;
  late List<bool> _selectedKeys;
  late List<bool> _keyAlreadyInStore;
  bool _hostsExpanded = true;
  bool _keysExpanded = true;

  List<Session> get _hostSessions =>
      widget.source.hostsPreview?.result.sessions ?? const [];

  @override
  void initState() {
    super.initState();
    _selectedHostIds = _hostSessions.map((s) => s.id).toSet();
    _keyAlreadyInStore = widget.source.keys
        .map(
          (k) => widget.source.existingKeyFingerprints.contains(
            KeyStore.privateKeyFingerprint(k.pem),
          ),
        )
        .toList();
    // Default-uncheck keys already in the store — they'd dedup to no-ops.
    _selectedKeys = _keyAlreadyInStore.map((e) => !e).toList();
  }

  // --- Hosts section ---

  void _toggleHost(String id) {
    setState(() {
      if (_selectedHostIds.contains(id)) {
        _selectedHostIds.remove(id);
      } else {
        _selectedHostIds.add(id);
      }
    });
  }

  bool? get _hostsTristate {
    if (_hostSessions.isEmpty) return false;
    if (_selectedHostIds.length == _hostSessions.length) return true;
    if (_selectedHostIds.isEmpty) return false;
    return null;
  }

  void _toggleAllHosts(bool? value) {
    setState(() {
      _selectedHostIds = value == true
          ? _hostSessions.map((s) => s.id).toSet()
          : {};
    });
  }

  // --- Keys section ---

  void _toggleKey(int i) {
    setState(() => _selectedKeys[i] = !_selectedKeys[i]);
  }

  bool? get _keysTristate {
    if (_selectedKeys.isEmpty) return false;
    final on = _selectedKeys.where((v) => v).length;
    if (on == _selectedKeys.length) return true;
    if (on == 0) return false;
    return null;
  }

  void _toggleAllKeys(bool? value) {
    setState(() {
      for (var i = 0; i < _selectedKeys.length; i++) {
        _selectedKeys[i] = value == true;
      }
    });
  }

  // --- Submit ---

  bool get _hasAnySelection =>
      _selectedHostIds.isNotEmpty || _selectedKeys.any((v) => v);

  ImportResult _buildResult(BuildContext context) {
    final sessions = _hostSessions
        .where((s) => _selectedHostIds.contains(s.id))
        .toList();

    // Manager keys come from two sources: keys already resolved by the config
    // importer (IdentityFile → SshKeyEntry) and raw keys picked up by the
    // scanner. We only keep keys the user opted into; dedup by fingerprint
    // so a key referenced by both paths doesn't import twice.
    final keyStore = KeyStore();
    final date = DateTime.now().toIso8601String().split('T').first;
    final pickedEntries = <SshKeyEntry>[];
    final seenFingerprints = <String>{};

    // Add selected scanned keys first — they keep a nice human label.
    for (var i = 0; i < widget.source.keys.length; i++) {
      if (!_selectedKeys[i]) continue;
      final scanned = widget.source.keys[i];
      final fp = KeyStore.privateKeyFingerprint(scanned.pem);
      if (!seenFingerprints.add(fp)) continue;
      try {
        pickedEntries.add(
          keyStore.importKey(scanned.pem, '${scanned.suggestedLabel} $date'),
        );
      } catch (_) {
        // Skip unparseable PEM — the logger above in the handler already
        // warns about each malformed file; no user-facing toast needed.
      }
    }

    // Add config-resolved keys ONLY if a selected host references them,
    // and we haven't already added that key via the scanner path.
    final referencedKeyIds = sessions
        .map((s) => s.keyId)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final entry
        in widget.source.hostsPreview?.result.managerKeys ??
            const <SshKeyEntry>[]) {
      if (!referencedKeyIds.contains(entry.id)) continue;
      final fp = KeyStore.privateKeyFingerprint(entry.privateKey);
      if (!seenFingerprints.add(fp)) continue;
      pickedEntries.add(entry);
    }

    return ImportResult(
      sessions: sessions,
      managerKeys: pickedEntries,
      mode: ImportMode.merge,
      emptyFolders: sessions.isEmpty ? const {} : {widget.source.folderLabel},
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final source = widget.source;

    return AppDialog(
      title: s.importFromSshDir,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            source.folderLabel,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 8),
          _buildHostsSection(s),
          const SizedBox(height: 8),
          _buildKeysSection(s),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: s.importData,
          enabled: _hasAnySelection,
          onTap: () => Navigator.pop(context, _buildResult(context)),
        ),
      ],
    );
  }

  Widget _buildHostsSection(S s) {
    final hostCount = _hostSessions.length;
    final trailing = hostCount == 0
        ? s.sshConfigPreviewNoHosts
        : '${_selectedHostIds.length} / $hostCount';
    return CollapsibleCheckboxesSection(
      title: s.sshDirImportHostsSection,
      trailingLabel: trailing,
      expanded: _hostsExpanded,
      onToggle: () => setState(() => _hostsExpanded = !_hostsExpanded),
      body: _buildHostsBody(s),
    );
  }

  Widget _buildHostsBody(S s) {
    if (_hostSessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
        child: Text(
          s.sshConfigPreviewNoHosts,
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
      );
    }
    final missing =
        widget.source.hostsPreview?.hostsWithMissingKeys ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataCheckboxRow(
          icon: Icons.done_all,
          label: s.sshConfigPreviewHostsFound(_hostSessions.length),
          value: _hostsTristate ?? false,
          onTap: () => _toggleAllHosts(_hostsTristate != true),
          trailingLabel: '${_selectedHostIds.length} / ${_hostSessions.length}',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final session in _hostSessions)
                  DataCheckboxRow(
                    icon: Icons.computer,
                    label: session.label,
                    value: _selectedHostIds.contains(session.id),
                    onTap: () => _toggleHost(session.id),
                    trailingLabel:
                        '${session.user.isEmpty ? '?' : session.user}'
                        '@${session.host}:${session.port}'
                        '${session.keyId.isNotEmpty ? '  (key)' : ''}',
                  ),
              ],
            ),
          ),
        ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              s.sshConfigPreviewMissingKeys(missing.join(', ')),
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.yellow,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKeysSection(S s) {
    final keyCount = widget.source.keys.length;
    final selectedCount = _selectedKeys.where((v) => v).length;
    final trailing = keyCount == 0
        ? s.importSshKeysNoneFound
        : '$selectedCount / $keyCount';
    return CollapsibleCheckboxesSection(
      title: s.sshDirImportKeysSection,
      trailingLabel: trailing,
      expanded: _keysExpanded,
      onToggle: () => setState(() => _keysExpanded = !_keysExpanded),
      body: _buildKeysBody(s),
    );
  }

  Widget _buildKeysBody(S s) {
    if (widget.source.keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
        child: Text(
          s.importSshKeysNoneFound,
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataCheckboxRow(
          icon: Icons.done_all,
          label: s.importSshKeysFound(widget.source.keys.length),
          value: _keysTristate ?? false,
          onTap: () => _toggleAllKeys(_keysTristate != true),
          trailingLabel:
              '${_selectedKeys.where((v) => v).length} / ${widget.source.keys.length}',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.source.keys.length; i++)
                  DataCheckboxRow(
                    icon: Icons.vpn_key,
                    label: widget.source.keys[i].suggestedLabel,
                    value: _selectedKeys[i],
                    onTap: () => _toggleKey(i),
                    trailingLabel: _keyAlreadyInStore[i]
                        ? s.sshKeyAlreadyImported
                        : null,
                    warningText: _keyAlreadyInStore[i]
                        ? widget.source.keys[i].path
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
