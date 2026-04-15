import 'package:flutter/material.dart';

import '../core/import/openssh_config_importer.dart';
import '../core/import/ssh_dir_key_scanner.dart';
import '../core/security/key_store.dart';
import '../core/session/session.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_divider.dart';
import 'app_dialog.dart';
import 'data_checkboxes.dart';

/// Input bundle for [SshDirImportDialog]. Groups the results of scanning
/// `~/.ssh` (keys) and parsing `~/.ssh/config` (hosts) so the dialog can
/// render both in a single pick-list and return one merged [ImportResult].
class SshDirImportSource {
  final OpenSshConfigImportPreview? hostsPreview;
  final List<ScannedKey> keys;
  final Set<String> existingKeyFingerprints;

  /// `user@host:port` strings for every session already in the session store.
  /// Lets the dialog flag a parsed host as "already in sessions" and default
  /// it to unchecked so the user isn't invited to create duplicates.
  final Set<String> existingSessionAddresses;
  final String folderLabel;

  const SshDirImportSource({
    required this.hostsPreview,
    required this.keys,
    required this.folderLabel,
    this.existingKeyFingerprints = const {},
    this.existingSessionAddresses = const {},
  });

  bool get hasHosts => (hostsPreview?.result.sessions.isNotEmpty ?? false);
  bool get hasKeys => keys.isNotEmpty;
}

/// Canonical "already in sessions?" key for a [Session]. The dialog and the
/// settings handler use the same format so the dedup check lines up.
String sshDirSessionAddress(Session s) => '${s.user}@${s.host}:${s.port}';

/// Returned by the "Browse..." picker for the hosts section — a parsed
/// config plus any keys the parser resolved from its IdentityFile lines.
class PickedConfigResult {
  final List<Session> sessions;
  final List<SshKeyEntry> managerKeys;
  final List<String> hostsWithMissingKeys;

  const PickedConfigResult({
    required this.sessions,
    this.managerKeys = const [],
    this.hostsWithMissingKeys = const [],
  });
}

/// Invoked when the user taps "Browse..." in a section. Returns `null` on
/// cancel. The caller (settings handler) owns the [FilePicker] call so this
/// widget stays free of platform plugins.
typedef PickConfigCallback = Future<PickedConfigResult?> Function();
typedef PickKeysCallback = Future<List<ScannedKey>?> Function();

/// Unified import dialog for `~/.ssh`.
///
/// Shows two collapsible sections using the shared [CollapsibleCheckboxesSection]
/// primitive so the layout matches the .lfs archive / export dialogs exactly
/// (same row metrics, same chevron, same tristate).
///
/// Each section has an optional "Browse..." action that lets the user pick
/// an additional config file or key file from outside `~/.ssh`. Newly picked
/// items are appended to the in-dialog list and default to checked.
///
/// The tristate "select-all" row is separated from the per-item rows by a
/// horizontal divider and the per-item rows are indented so the two visual
/// scopes stay distinct even though they use the same row primitive.
///
/// Returns a combined [ImportResult] on accept, or null on cancel. Sessions
/// pointing to a deselected key get their keyId nulled by [ImportService]'s
/// FK-safety pass.
class SshDirImportDialog extends StatefulWidget {
  final SshDirImportSource source;
  final PickConfigCallback? onPickConfigFile;
  final PickKeysCallback? onPickKeyFiles;

  const SshDirImportDialog({
    super.key,
    required this.source,
    this.onPickConfigFile,
    this.onPickKeyFiles,
  });

  static Future<ImportResult?> show(
    BuildContext context, {
    required SshDirImportSource source,
    PickConfigCallback? onPickConfigFile,
    PickKeysCallback? onPickKeyFiles,
  }) => AppDialog.show<ImportResult>(
    context,
    builder: (_) => SshDirImportDialog(
      source: source,
      onPickConfigFile: onPickConfigFile,
      onPickKeyFiles: onPickKeyFiles,
    ),
  );

  @override
  State<SshDirImportDialog> createState() => _SshDirImportDialogState();
}

class _SshDirImportDialogState extends State<SshDirImportDialog> {
  final List<Session> _hosts = [];
  final List<bool> _hostAlreadyInSessions = [];
  final List<SshKeyEntry> _hostManagerKeys = [];
  final List<String> _hostsWithMissingKeys = [];
  final List<ScannedKey> _keys = [];
  Set<String> _selectedHostIds = {};
  List<bool> _selectedKeys = [];
  List<bool> _keyAlreadyInStore = [];
  bool _hostsExpanded = true;
  bool _keysExpanded = true;
  bool _pickingHosts = false;
  bool _pickingKeys = false;

  @override
  void initState() {
    super.initState();
    final preview = widget.source.hostsPreview;
    if (preview != null) {
      for (final s in preview.result.sessions) {
        _hosts.add(s);
        _hostAlreadyInSessions.add(
          widget.source.existingSessionAddresses.contains(
            sshDirSessionAddress(s),
          ),
        );
      }
      _hostManagerKeys.addAll(preview.result.managerKeys);
      _hostsWithMissingKeys.addAll(preview.hostsWithMissingKeys);
    }
    // Default-uncheck hosts whose user@host:port is already in the session
    // store — importing them again would just create a duplicate row.
    _selectedHostIds = {
      for (var i = 0; i < _hosts.length; i++)
        if (!_hostAlreadyInSessions[i]) _hosts[i].id,
    };
    _keys.addAll(widget.source.keys);
    _keyAlreadyInStore = _keys
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
    if (_hosts.isEmpty) return false;
    if (_selectedHostIds.length == _hosts.length) return true;
    if (_selectedHostIds.isEmpty) return false;
    return null;
  }

  void _toggleAllHosts(bool? value) {
    setState(() {
      _selectedHostIds = value == true ? _hosts.map((s) => s.id).toSet() : {};
    });
  }

  Future<void> _browseConfig() async {
    final cb = widget.onPickConfigFile;
    if (cb == null || _pickingHosts) return;
    setState(() => _pickingHosts = true);
    try {
      final picked = await cb();
      if (picked == null || !mounted) return;
      setState(() {
        // Append, dedup by session id. Newly picked hosts default to checked
        // unless user@host:port already exists as a session.
        final existingIds = _hosts.map((s) => s.id).toSet();
        for (final s in picked.sessions) {
          if (existingIds.contains(s.id)) continue;
          _hosts.add(s);
          final already = widget.source.existingSessionAddresses.contains(
            sshDirSessionAddress(s),
          );
          _hostAlreadyInSessions.add(already);
          if (!already) _selectedHostIds.add(s.id);
        }
        final existingKeyIds = _hostManagerKeys.map((k) => k.id).toSet();
        for (final k in picked.managerKeys) {
          if (existingKeyIds.contains(k.id)) continue;
          _hostManagerKeys.add(k);
        }
        _hostsWithMissingKeys.addAll(picked.hostsWithMissingKeys);
      });
    } finally {
      if (mounted) setState(() => _pickingHosts = false);
    }
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

  Future<void> _browseKeys() async {
    final cb = widget.onPickKeyFiles;
    if (cb == null || _pickingKeys) return;
    setState(() => _pickingKeys = true);
    try {
      final picked = await cb();
      if (picked == null || picked.isEmpty || !mounted) return;
      setState(() {
        final existingFps = _keys
            .map((k) => KeyStore.privateKeyFingerprint(k.pem))
            .toSet();
        for (final k in picked) {
          final fp = KeyStore.privateKeyFingerprint(k.pem);
          if (!existingFps.add(fp)) continue;
          _keys.add(k);
          final existsInStore = widget.source.existingKeyFingerprints.contains(
            fp,
          );
          _keyAlreadyInStore.add(existsInStore);
          _selectedKeys.add(!existsInStore);
        }
      });
    } finally {
      if (mounted) setState(() => _pickingKeys = false);
    }
  }

  // --- Submit ---

  bool get _hasAnySelection =>
      _selectedHostIds.isNotEmpty || _selectedKeys.any((v) => v);

  ImportResult _buildResult(BuildContext context) {
    final sessions = _hosts
        .where((s) => _selectedHostIds.contains(s.id))
        .toList();

    // Manager keys come from two sources: keys already resolved by the config
    // importer (IdentityFile → SshKeyEntry) and raw keys picked up by the
    // scanner / file picker. We only keep keys the user opted into; dedup by
    // fingerprint so a key referenced by both paths doesn't import twice.
    final keyStore = KeyStore();
    final date = DateTime.now().toIso8601String().split('T').first;
    final pickedEntries = <SshKeyEntry>[];
    final seenFingerprints = <String>{};

    for (var i = 0; i < _keys.length; i++) {
      if (!_selectedKeys[i]) continue;
      final scanned = _keys[i];
      final fp = KeyStore.privateKeyFingerprint(scanned.pem);
      if (!seenFingerprints.add(fp)) continue;
      try {
        pickedEntries.add(
          keyStore.importKey(scanned.pem, '${scanned.suggestedLabel} $date'),
        );
      } catch (_) {
        // Skip unparseable PEM — the handler above already warns about each
        // malformed file; no user-facing toast needed.
      }
    }

    final referencedKeyIds = sessions
        .map((s) => s.keyId)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final entry in _hostManagerKeys) {
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
    final hostCount = _hosts.length;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hosts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
            child: Text(
              s.sshConfigPreviewNoHosts,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
              ),
            ),
          )
        else ...[
          DataCheckboxRow(
            icon: Icons.done_all,
            label: s.sshConfigPreviewHostsFound(_hosts.length),
            value: _hostsTristate,
            tristate: true,
            onTap: () => _toggleAllHosts(_hostsTristate != true),
            trailingLabel: '${_selectedHostIds.length} / ${_hosts.length}',
          ),
          const AppDivider(),
          // Indented list keeps the per-host rows visually distinct from the
          // section-wide "select all" row above.
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _hosts.length; i++)
                      DataCheckboxRow(
                        icon: Icons.computer,
                        label: _hosts[i].label,
                        value: _selectedHostIds.contains(_hosts[i].id),
                        onTap: () => _toggleHost(_hosts[i].id),
                        subtitle:
                            '${_hosts[i].user.isEmpty ? '?' : _hosts[i].user}'
                            '@${_hosts[i].host}:${_hosts[i].port}'
                            '${_hosts[i].keyId.isNotEmpty ? '  (key)' : ''}',
                        trailingLabel: _hostAlreadyInSessions[i]
                            ? s.sshDirSessionAlreadyImported
                            : null,
                        labelColor: _hostAlreadyInSessions[i]
                            ? AppTheme.fgDim
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (_hostsWithMissingKeys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              s.sshConfigPreviewMissingKeys(_hostsWithMissingKeys.join(', ')),
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.yellow,
              ),
            ),
          ),
        if (widget.onPickConfigFile != null)
          _buildBrowseButton(s, forKeys: false),
      ],
    );
  }

  Widget _buildKeysSection(S s) {
    final keyCount = _keys.length;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_keys.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
            child: Text(
              s.importSshKeysNoneFound,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
              ),
            ),
          )
        else ...[
          DataCheckboxRow(
            icon: Icons.done_all,
            label: s.importSshKeysFound(_keys.length),
            value: _keysTristate,
            tristate: true,
            onTap: () => _toggleAllKeys(_keysTristate != true),
            trailingLabel:
                '${_selectedKeys.where((v) => v).length} / ${_keys.length}',
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _keys.length; i++)
                      DataCheckboxRow(
                        icon: Icons.vpn_key,
                        label: _keys[i].suggestedLabel,
                        value: _selectedKeys[i],
                        onTap: () => _toggleKey(i),
                        subtitle: _keys[i].path,
                        trailingLabel: _keyAlreadyInStore[i]
                            ? s.sshKeyAlreadyImported
                            : null,
                        labelColor: _keyAlreadyInStore[i]
                            ? AppTheme.fgDim
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (widget.onPickKeyFiles != null) _buildBrowseButton(s, forKeys: true),
      ],
    );
  }

  Widget _buildBrowseButton(S s, {required bool forKeys}) {
    final busy = forKeys ? _pickingKeys : _pickingHosts;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy ? null : (forKeys ? _browseKeys : _browseConfig),
          icon: const Icon(Icons.folder_open, size: 16),
          label: Text(s.browseFiles),
        ),
      ),
    );
  }
}
