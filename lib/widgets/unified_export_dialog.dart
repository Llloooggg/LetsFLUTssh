import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/session/qr_codec.dart';
import '../core/session/session.dart';
import '../core/session/session_tree.dart';
import '../core/shortcut_registry.dart';
import '../core/ssh/ssh_config.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_divider.dart';
import 'hover_region.dart';

/// Unified export dialog for both QR code and .lfs archive export.
class UnifiedExportDialog extends StatefulWidget {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final AppConfig? config;
  final String? knownHostsContent;
  final bool isQrMode;

  /// Map of keyId -> keyData for keys stored in the manager.
  /// Used to calculate export size for manager keys separately from embedded keys.
  final Map<String, String> managerKeys;

  const UnifiedExportDialog({
    super.key,
    required this.sessions,
    required this.emptyFolders,
    this.config,
    this.knownHostsContent,
    this.isQrMode = false,
    this.managerKeys = const {},
  });

  static Future<UnifiedExportResult?> show(
    BuildContext context, {
    required List<Session> sessions,
    required Set<String> emptyFolders,
    AppConfig? config,
    String? knownHostsContent,
    bool isQrMode = false,
    Map<String, String> managerKeys = const {},
  }) {
    return AppDialog.show<UnifiedExportResult>(
      context,
      builder: (_) => UnifiedExportDialog(
        sessions: sessions,
        emptyFolders: emptyFolders,
        config: config,
        knownHostsContent: knownHostsContent,
        isQrMode: isQrMode,
        managerKeys: managerKeys,
      ),
    );
  }

  @override
  State<UnifiedExportDialog> createState() => _UnifiedExportDialogState();
}

class _UnifiedExportDialogState extends State<UnifiedExportDialog> {
  late ExportOptions _options;
  late final Set<String> _selectedIds;

  // Cache for size calculations — invalidated on every selection/option change.
  // All size values are computed together in a single pass to avoid redundant
  // deflate+base64 calls on every rebuild.
  int? _cachedPayloadSize;
  int? _cachedPasswordsExtra;
  int? _cachedEmbeddedKeysExtra;
  int? _cachedManagerKeysExtra;
  int? _cachedConfigSize;
  int? _cachedKnownHostsSize;
  ExportOptions? _cachedPayloadOptions;
  Set<String>? _cachedPayloadSelectedIds;
  String? _cachedPayloadKnownHosts;

  @override
  void initState() {
    super.initState();
    // QR mode: passwords ON, keys OFF (keys can be huge for QR).
    // .lfs mode: all credentials ON (encrypted archive, user expects full backup).
    _options = widget.isQrMode
        ? const ExportOptions(
            includeConfig: false,
            includePasswords: true,
            includeEmbeddedKeys: false,
            includeManagerKeys: false,
          )
        : const ExportOptions(
            includeConfig: false,
            includePasswords: true,
            includeEmbeddedKeys: true,
            includeManagerKeys: true,
          );
    _selectedIds = widget.sessions.map((s) => s.id).toSet();
  }

  List<Session> get _selectedSessions =>
      widget.sessions.where((s) => _selectedIds.contains(s.id)).toList();

  Set<String> get _relevantEmptyFolders {
    final selectedFolders = _selectedSessions.map((s) => s.folder).toSet();
    // Include an empty folder if:
    //   1. Any selected session belongs to it or a subfolder (preserve hierarchy), OR
    //   2. The folder is an ancestor of a selected session's folder, OR
    //   3. All sessions are selected (export full structure).
    // This ensures the folder hierarchy is preserved on import even when
    // empty folders contain no sessions.
    return widget.emptyFolders.where((folder) {
      return selectedFolders.any(
            (selected) =>
                selected == folder ||
                selected.startsWith('$folder/') ||
                folder.startsWith('$selected/'),
          ) ||
          _selectedIds.length == widget.sessions.length;
    }).toSet();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  bool get _payloadSizeCacheValid {
    return _cachedPayloadOptions == _options &&
        _cachedPayloadSelectedIds != null &&
        _cachedPayloadSelectedIds!.length == _selectedIds.length &&
        _cachedPayloadSelectedIds!.containsAll(_selectedIds) &&
        _cachedPayloadKnownHosts == widget.knownHostsContent;
  }

  void _invalidatePayloadCache() {
    _cachedPayloadSize = null;
    _cachedPasswordsExtra = null;
    _cachedEmbeddedKeysExtra = null;
    _cachedManagerKeysExtra = null;
    _cachedConfigSize = null;
    _cachedKnownHostsSize = null;
    _cachedPayloadOptions = null;
    _cachedPayloadSelectedIds = null;
    _cachedPayloadKnownHosts = null;
  }

  /// Total payload size with current options. Calculated directly (one call).
  int get _payloadSize {
    if (_payloadSizeCacheValid && _cachedPayloadSize != null) {
      return _cachedPayloadSize!;
    }
    final result = calculateExportPayloadSize(
      _selectedSessions,
      emptyFolders: _relevantEmptyFolders,
      options: _options,
      config: _options.includeConfig ? widget.config : null,
      knownHostsContent: _options.includeKnownHosts
          ? widget.knownHostsContent
          : null,
    );
    _cachedPayloadSize = result;
    _cachedPayloadOptions = _options;
    _cachedPayloadSelectedIds = Set.of(_selectedIds);
    _cachedPayloadKnownHosts = widget.knownHostsContent;
    return result;
  }

  /// Size contribution of one credential type, measured against a baseline
  /// of sessions-only (no other credentials). This gives stable sizes that
  /// don't change when toggling between different credential options.
  ///
  /// Deflate compression makes sizes non-additive, so these are approximate
  /// marginal costs. The total [_payloadSize] is always calculated directly.
  int _credentialExtraSize({
    required bool includePasswords,
    required bool includeEmbeddedKeys,
    required bool includeManagerKeys,
  }) {
    if (_selectedSessions.isEmpty) return 0;
    final baselineOptions = _options.copyWith(
      includePasswords: false,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
    final baseline = calculateExportPayloadSize(
      _selectedSessions,
      emptyFolders: {},
      options: baselineOptions,
      knownHostsContent: null,
    );
    final withCred = calculateExportPayloadSize(
      _selectedSessions,
      emptyFolders: {},
      options: _options.copyWith(
        includePasswords: includePasswords,
        includeEmbeddedKeys: includeEmbeddedKeys,
        includeManagerKeys: includeManagerKeys,
      ),
      knownHostsContent: null,
    );
    return (withCred - baseline).clamp(0, withCred);
  }

  int _passwordsExtraSize() {
    return _cachedPasswordsExtra ??= _credentialExtraSize(
      includePasswords: true,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
  }

  int _embeddedKeysExtraSize() {
    if (_cachedEmbeddedKeysExtra != null) return _cachedEmbeddedKeysExtra!;
    // Only calculate size for sessions that have embedded keys (keyId is empty)
    // Note: we check keyId (not keyData) because keyData may be populated from
    // storage even for manager keys, but keyId uniquely identifies manager keys
    final sessionsWithEmbedded = _selectedSessions
        .where((s) => s.keyId.isEmpty)
        .toList();
    if (sessionsWithEmbedded.isEmpty) return _cachedEmbeddedKeysExtra = 0;
    return _cachedEmbeddedKeysExtra = _credentialExtraSizeForSessions(
      sessionsWithEmbedded,
      includePasswords: false,
      includeEmbeddedKeys: true,
      includeManagerKeys: false,
    );
  }

  int _managerKeysExtraSize() {
    if (_cachedManagerKeysExtra != null) return _cachedManagerKeysExtra!;
    // Sum of all unique manager keys (regardless of selected sessions)
    final managerKeys = widget.managerKeys;
    if (managerKeys.isEmpty) return _cachedManagerKeysExtra = 0;

    // Calculate size of all manager keys as if they were in the payload
    // Using a single dummy session to measure key-only payload size
    final dummySession = Session(
      label: 'x',
      server: const ServerAddress(host: 'x', user: 'x'),
    );

    // Build key map as encodeExportPayload does
    final keyToShortId = <String, String>{};
    var keyCounter = 0;
    for (final keyData in managerKeys.values) {
      keyToShortId.putIfAbsent(keyData, () => 'k${keyCounter++}');
    }

    // Calculate raw JSON size with keys
    final keyMap = <String, String>{};
    keyToShortId.forEach((keyData, shortId) => keyMap[shortId] = keyData);
    final payload = <String, dynamic>{
      'km': keyMap,
      's': [encodeSessionCompact(dummySession)],
    };
    final json = jsonEncode(payload);
    final compressed = Deflate(utf8.encode(json)).getBytes();
    final withKeysSize = base64Url.encode(compressed).length;

    // Calculate baseline (sessions without keys)
    const baselineOptions = ExportOptions(
      includeSessions: true,
      includeConfig: false,
      includeKnownHosts: false,
      includePasswords: false,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
    final baselineSize = calculateExportPayloadSize(
      [dummySession],
      emptyFolders: {},
      options: baselineOptions,
      knownHostsContent: null,
    );

    return _cachedManagerKeysExtra = (withKeysSize - baselineSize).clamp(
      0,
      withKeysSize,
    );
  }

  int _credentialExtraSizeForSessions(
    List<Session> sessions, {
    required bool includePasswords,
    required bool includeEmbeddedKeys,
    required bool includeManagerKeys,
  }) {
    if (sessions.isEmpty) return 0;
    const baselineOptions = ExportOptions(
      includeSessions: true,
      includeConfig: false,
      includeKnownHosts: false,
      includePasswords: false,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
    final baseline = calculateExportPayloadSize(
      sessions,
      emptyFolders: {},
      options: baselineOptions,
      knownHostsContent: null,
    );
    final withCred = calculateExportPayloadSize(
      sessions,
      emptyFolders: {},
      options: ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: false,
        includePasswords: includePasswords,
        includeEmbeddedKeys: includeEmbeddedKeys,
        includeManagerKeys: includeManagerKeys,
      ),
      knownHostsContent: null,
    );
    return (withCred - baseline).clamp(0, withCred);
  }

  int _configSize() {
    if (_cachedConfigSize != null) return _cachedConfigSize!;
    if (widget.config == null) return _cachedConfigSize = 0;
    return _cachedConfigSize = calculateExportPayloadSize(
      [],
      options: const ExportOptions(includeSessions: false),
      config: widget.config,
      knownHostsContent: null,
    );
  }

  int _knownHostsSize() {
    if (_cachedKnownHostsSize != null) return _cachedKnownHostsSize!;
    final content = widget.knownHostsContent;
    if (content?.isNotEmpty != true) return _cachedKnownHostsSize = 0;
    return _cachedKnownHostsSize = calculateExportPayloadSize(
      [],
      options: const ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includePasswords: false,
        includeEmbeddedKeys: false,
        includeManagerKeys: false,
      ),
      knownHostsContent: content,
    );
  }

  bool get _fitsInQr => !widget.isQrMode || _payloadSize <= qrMaxPayloadBytes;
  bool get _hasSelection =>
      _selectedIds.isNotEmpty ||
      _options.includeConfig ||
      _options.includeKnownHosts;
  bool get _allSelected => _selectedIds.length == widget.sessions.length;
  bool? get _tristateValue {
    if (_allSelected) return true;
    if (_selectedIds.isEmpty) return false;
    return null;
  }

  void _toggleAll(bool select) {
    setState(() {
      _invalidatePayloadCache();
      if (select) {
        _selectedIds.addAll(widget.sessions.map((s) => s.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSession(String id) {
    setState(() {
      _invalidatePayloadCache();
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleFolder(String folderPath) {
    final folderSessionIds = widget.sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .map((s) => s.id)
        .toSet();
    final allSelected = folderSessionIds.every(_selectedIds.contains);
    setState(() {
      _invalidatePayloadCache();
      if (allSelected) {
        _selectedIds.removeAll(folderSessionIds);
      } else {
        _selectedIds.addAll(folderSessionIds);
      }
    });
  }

  bool? _isFolderPartial(String folderPath) {
    final folderSessionIds = widget.sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .map((s) => s.id)
        .toSet();
    if (folderSessionIds.isEmpty) return false;
    final selectedCount = folderSessionIds.where(_selectedIds.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == folderSessionIds.length) return true;
    return null;
  }

  void _export() {
    if (!_fitsInQr) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).qrTooManyForSingleCode),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      UnifiedExportResult(
        options: _options,
        selectedSessions: _selectedSessions,
        selectedEmptyFolders: _relevantEmptyFolders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = SessionTree.build(
      widget.sessions,
      emptyFolders: widget.emptyFolders,
    );
    final sizePercent = widget.isQrMode && qrMaxPayloadBytes > 0
        ? (_payloadSize / qrMaxPayloadBytes).clamp(0.0, 1.0)
        : 0.0;
    final sizeColor = _fitsInQr ? AppTheme.green : AppTheme.red;

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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDataCheckboxes(),
                        if (widget.isQrMode && _options.includePasswords)
                          _buildQrSecurityWarning(),
                        const AppDivider(),
                        const SizedBox(height: 4),
                        _buildSelectAll(),
                        const AppDivider(),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: _buildTreeItems(tree, 0),
                          ),
                        ),
                        if (widget.isQrMode) ...[
                          const SizedBox(height: 12),
                          _buildSizeIndicator(sizePercent, sizeColor),
                        ],
                      ],
                    ),
                  ),
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
                      enabled: _hasSelection && _fitsInQr,
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
  }

  Widget _buildDataCheckboxes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.config != null)
          _buildCheckboxRow(
            Icons.settings,
            S.of(context).appSettings,
            _options.includeConfig,
            () => setState(() {
              _invalidatePayloadCache();
              _options = _options.copyWith(
                includeConfig: !_options.includeConfig,
              );
            }),
            _formatSize(_configSize()),
          ),
        _buildCheckboxRow(
          Icons.lock,
          S.of(context).includePasswords,
          _options.includePasswords,
          () => setState(() {
            _invalidatePayloadCache();
            _options = _options.copyWith(
              includePasswords: !_options.includePasswords,
            );
          }),
          _formatSize(_passwordsExtraSize()),
        ),
        _buildCheckboxRow(
          Icons.key,
          S.of(context).embeddedKeys,
          _options.includeEmbeddedKeys,
          () => setState(() {
            _invalidatePayloadCache();
            _options = _options.copyWith(
              includeEmbeddedKeys: !_options.includeEmbeddedKeys,
            );
          }),
          _formatSize(_embeddedKeysExtraSize()),
          warningText: _embeddedKeysWarningText,
        ),
        _buildCheckboxRow(
          Icons.cloud,
          S.of(context).managerKeys,
          _options.includeManagerKeys,
          () => setState(() {
            _invalidatePayloadCache();
            _options = _options.copyWith(
              includeManagerKeys: !_options.includeManagerKeys,
            );
          }),
          _formatSize(_managerKeysExtraSize()),
          warningText: _managerKeysWarningText,
        ),
        if (widget.knownHostsContent?.isNotEmpty == true)
          _buildCheckboxRow(
            Icons.verified_user,
            S.of(context).knownHosts,
            _options.includeKnownHosts,
            () => setState(() {
              _invalidatePayloadCache();
              _options = _options.copyWith(
                includeKnownHosts: !_options.includeKnownHosts,
              );
            }),
            _formatSize(_knownHostsSize()),
          ),
      ],
    );
  }

  String? get _embeddedKeysWarningText {
    if (!widget.isQrMode || !_options.includeEmbeddedKeys) return null;
    return S.of(context).sshKeysMayBeLarge;
  }

  String? get _managerKeysWarningText {
    if (!widget.isQrMode || !_options.includeManagerKeys) return null;
    return S.of(context).managerKeysMayBeLarge;
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
              style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.orange),
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
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (_) => onTap()),
            Icon(
              icon,
              size: 16,
              color: warningText != null ? AppTheme.orange : AppTheme.fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppFonts.md,
                      color: warningText != null
                          ? AppTheme.orange
                          : AppTheme.fg,
                    ),
                  ),
                  if (warningText != null)
                    Text(
                      warningText,
                      style: TextStyle(
                        fontSize: AppFonts.xs,
                        color: AppTheme.orange,
                      ),
                    ),
                ],
              ),
            ),
            if (sizeLabel != null)
              Text(
                sizeLabel,
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAll() {
    return HoverRegion(
      onTap: () => _toggleAll(!_allSelected),
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Checkbox(
              value: _tristateValue,
              tristate: true,
              onChanged: (v) => _toggleAll(v == true),
            ),
            Text(
              S
                  .of(context)
                  .qrSelectAll(_selectedIds.length, widget.sessions.length),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppFonts.md,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTreeItems(List<SessionTreeNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      if (node.isGroup) {
        items.add(_buildGroupItem(node, depth));
        items.addAll(_buildTreeItems(node.children, depth + 1));
      } else if (node.session != null) {
        items.add(_buildSessionItem(node.session!, depth));
      }
    }
    return items;
  }

  Widget _buildGroupItem(SessionTreeNode node, int depth) {
    final tristate = _isFolderPartial(node.fullPath);
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: HoverRegion(
        onTap: () => _toggleFolder(node.fullPath),
        builder: (hovered) => Container(
          color: hovered ? AppTheme.hover : null,
          child: Row(
            children: [
              Checkbox(
                value: tristate,
                tristate: true,
                onChanged: (_) => _toggleFolder(node.fullPath),
              ),
              const Icon(Icons.folder, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  node.name,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionItem(Session session, int depth) {
    final isSelected = _selectedIds.contains(session.id);
    final isIncomplete = !session.isValid;
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: HoverRegion(
        onTap: () => _toggleSession(session.id),
        builder: (hovered) => Container(
          color: hovered ? AppTheme.hover : null,
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSession(session.id),
              ),
              Icon(
                isIncomplete ? Icons.warning_amber : Icons.computer,
                size: 16,
                color: isIncomplete ? AppTheme.orange : AppTheme.fg,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  session.label.isNotEmpty
                      ? session.label
                      : session.displayName,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    color: isIncomplete ? AppTheme.orange : AppTheme.fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeIndicator(double sizePercent, Color sizeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isQrMode)
          Text(
            S
                .of(context)
                .qrPayloadSize(
                  (_payloadSize / 1024).toStringAsFixed(1),
                  (qrMaxPayloadBytes / 1024).toStringAsFixed(1),
                ),
            style: TextStyle(fontSize: AppFonts.sm, color: sizeColor),
          )
        else
          Text(
            S.of(context).exportTotalSize(_formatSize(_payloadSize)),
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        if (widget.isQrMode) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppTheme.radiusSm,
            child: LinearProgressIndicator(
              value: sizePercent,
              backgroundColor: AppTheme.bg3,
              color: sizeColor,
            ),
          ),
          if (!_fitsInQr && _hasSelection) ...[
            const SizedBox(height: 8),
            Text(
              S.of(context).qrTooLarge,
              style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.red),
            ),
          ],
        ],
      ],
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
