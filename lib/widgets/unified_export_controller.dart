import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/security/key_store.dart';
import '../core/session/qr_codec.dart';
import '../core/session/session.dart';
import '../core/ssh/ssh_config.dart';
import '../features/settings/export_import.dart';
import 'unified_export_dialog.dart';

/// Identity of the currently-active preset. Kept in the controller as a
/// plain enum so widget layers can map it to a localized label without
/// the controller knowing about [BuildContext] or [AppLocalizations].
enum ExportPreset { fullBackup, sessions, custom }

/// Headless controller for [UnifiedExportDialog]. Owns selection, option,
/// and cached-size state so the dialog's [State] stays a thin renderer.
///
/// Follows the same `ChangeNotifier + AnimatedBuilder` pattern used by
/// [FilePaneController] in the file browser — widget-local controllers
/// live here, app-wide state lives in Riverpod providers. Constructor
/// arguments (the dialog data + mode) make this a natural fit for a
/// plain `ChangeNotifier` rather than a side-channeled provider.
class UnifiedExportController extends ChangeNotifier {
  UnifiedExportController({required this.data, required this.isQrMode})
    : _options = isQrMode ? _qrInitial : _lfsInitial,
      _selectedIds = data.sessions.map((s) => s.id).toSet();

  final UnifiedExportDialogData data;
  final bool isQrMode;

  ExportOptions _options;
  final Set<String> _selectedIds;
  bool _checkboxesExpanded = false;

  // Size caches — invalidated on selection / option change. All values
  // are computed lazily on first access and reused across rebuilds.
  int? _cachedPayloadSize;
  int? _cachedPasswordsExtra;
  int? _cachedEmbeddedKeysExtra;
  int? _cachedManagerKeysExtra;
  int? _cachedConfigSize;
  int? _cachedKnownHostsSize;
  int? _cachedTagsSize;
  int? _cachedSnippetsSize;
  ExportOptions? _cachedPayloadOptions;
  Set<String>? _cachedPayloadSelectedIds;
  String? _cachedPayloadKnownHosts;

  ExportOptions get options => _options;
  Set<String> get selectedIds => _selectedIds;
  bool get checkboxesExpanded => _checkboxesExpanded;

  List<Session> get selectedSessions =>
      data.sessions.where((s) => _selectedIds.contains(s.id)).toList();

  Set<String> get relevantEmptyFolders {
    final selectedFolders = selectedSessions.map((s) => s.folder).toSet();
    final all = _selectedIds.length == data.sessions.length;
    final result = <String>{};

    // Explicitly record every ancestor path of each selected session's
    // folder. Resolving a session's folder on import already creates
    // ancestors, but including them here keeps the export payload
    // self-describing and robust against future import flows that rely
    // on the emptyFolders set for hierarchy.
    for (final folder in selectedFolders) {
      if (folder.isEmpty) continue;
      final parts = folder.split('/');
      for (var i = 1; i < parts.length; i++) {
        result.add(parts.take(i).join('/'));
      }
    }

    // Include an empty folder from the source set if:
    //   1. Any selected session belongs to it or a subfolder, OR
    //   2. The folder is an ancestor of a selected session's folder, OR
    //   3. All sessions are selected (export full structure).
    for (final folder in data.emptyFolders) {
      if (all) {
        result.add(folder);
        continue;
      }
      final related = selectedFolders.any(
        (selected) =>
            selected == folder ||
            selected.startsWith('$folder/') ||
            folder.startsWith('$selected/'),
      );
      if (related) result.add(folder);
    }
    return result;
  }

  bool get allSelected => _selectedIds.length == data.sessions.length;

  bool? get tristateValue {
    if (allSelected) return true;
    if (_selectedIds.isEmpty) return false;
    return null;
  }

  bool get fitsInQr => !isQrMode || payloadSize <= qrMaxPayloadBytes;

  bool get hasSelection =>
      _selectedIds.isNotEmpty ||
      _options.includeConfig ||
      _options.includeKnownHosts ||
      _options.includeAllManagerKeys ||
      (_options.includeTags && data.tags.isNotEmpty) ||
      (_options.includeSnippets && data.snippets.isNotEmpty);

  ExportPreset get activePreset {
    // In QR mode the Full-backup / Sessions presets default their
    // key toggles (embedded + manager) to *off* because QR payloads
    // are sharply size-limited and keys bloat them. Match either
    // the file-mode or QR-mode variant for each preset so the
    // active-chip highlight tracks the user's current selection
    // regardless of which mode they last switched.
    if (_isPresetActive(_fullBackupPreset) ||
        _isPresetActive(_fullBackupPresetQr)) {
      return ExportPreset.fullBackup;
    }
    if (_isPresetActive(_sessionsPreset) ||
        _isPresetActive(_sessionsPresetQr)) {
      return ExportPreset.sessions;
    }
    return ExportPreset.custom;
  }

  /// In QR mode only: warn when embedded-key content will materially
  /// inflate the payload. Widget layer maps this to a localized string.
  bool get showEmbeddedKeysWarning => isQrMode && _options.includeEmbeddedKeys;
  bool get showManagerKeysWarning => isQrMode && _options.includeManagerKeys;
  bool get showAllManagerKeysWarning =>
      isQrMode && _options.includeAllManagerKeys;

  /// Pure helper — kept on the controller so the widget doesn't need to
  /// reimplement the same 2-line formatter.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  bool get _payloadSizeCacheValid {
    return _cachedPayloadOptions == _options &&
        _cachedPayloadSelectedIds != null &&
        _cachedPayloadSelectedIds!.length == _selectedIds.length &&
        _cachedPayloadSelectedIds!.containsAll(_selectedIds) &&
        _cachedPayloadKnownHosts == data.knownHostsContent;
  }

  void _invalidatePayloadCache() {
    _cachedPayloadSize = null;
    _cachedPasswordsExtra = null;
    _cachedEmbeddedKeysExtra = null;
    _cachedManagerKeysExtra = null;
    _cachedConfigSize = null;
    _cachedKnownHostsSize = null;
    _cachedTagsSize = null;
    _cachedSnippetsSize = null;
    _cachedPayloadOptions = null;
    _cachedPayloadSelectedIds = null;
    _cachedPayloadKnownHosts = null;
  }

  /// Total payload size with the current options.
  ///
  /// Manager keys are calculated separately because sessions in the
  /// dialog have keyId but not keyData (resolved later during the actual
  /// export).
  int get payloadSize {
    if (_payloadSizeCacheValid && _cachedPayloadSize != null) {
      return _cachedPayloadSize!;
    }
    final result = isQrMode ? _qrPayloadSize() : _lfsArchiveSize();
    _cachedPayloadSize = result;
    _cachedPayloadOptions = _options;
    _cachedPayloadSelectedIds = Set.of(_selectedIds);
    _cachedPayloadKnownHosts = data.knownHostsContent;
    return result;
  }

  /// QR payload size: deflate-compressed JSON, base64url-encoded.
  ///
  /// Tags + snippets are folded into the estimate so the "fits in QR"
  /// gate reflects the full payload the real export at
  /// `settings_sections_data._generateQrExport` will emit. Omitting
  /// them here used to make the UI claim "fits" while the encoder
  /// silently appended the `tg` / `sn` sections on export and pushed
  /// past the 2 KB ceiling — the user then got a bare "QR too large"
  /// toast with no indication that tags were the culprit.
  ///
  /// Session↔tag / folder↔tag / session↔snippet link tables are NOT
  /// included here because the dialog data carrier does not hold them
  /// (they are collected lazily via DAO calls after the dialog closes).
  /// The compressed size contribution of link tables is small versus
  /// the tag / snippet bodies themselves, so the estimate remains
  /// conservative — worst case we slightly under-count by a few tens
  /// of bytes, not a kilobyte.
  int _qrPayloadSize() {
    final base = calculateExportPayloadSize(
      selectedSessions,
      input: ExportPayloadInput(
        emptyFolders: relevantEmptyFolders,
        options: _options
            .withIncludeManagerKeys(false)
            .withIncludeAllManagerKeys(false),
        config: _options.includeConfig ? data.config : null,
        knownHostsContent: _options.includeKnownHosts
            ? data.knownHostsContent
            : null,
        tags: _options.includeTags ? data.tags : const [],
        snippets: _options.includeSnippets ? data.snippets : const [],
      ),
    );
    return _options.hasManagerKeys ? base + managerKeysExtraSize : base;
  }

  /// .lfs archive size: ZIP + AES-GCM overhead (salt+IV+tag = 60 bytes).
  int _lfsArchiveSize() {
    final resolvedSessions = _resolveSessionsForLfsSize();
    final keyEntries = _selectedManagerKeyEntries();
    return ExportImport.calculateLfsSize(
      LfsExportInput(
        sessions: resolvedSessions,
        config: data.config ?? AppConfig.defaults,
        options: _options,
        emptyFolders: relevantEmptyFolders,
        knownHostsContent: data.knownHostsContent,
        managerKeyEntries: keyEntries,
        tags: _options.includeTags ? data.tags : const [],
        snippets: _options.includeSnippets ? data.snippets : const [],
      ),
    );
  }

  List<Session> _resolveSessionsForLfsSize() {
    final entries = data.managerKeyEntries;
    if (entries.isEmpty) return selectedSessions;
    return selectedSessions.map((s) {
      if (s.keyId.isEmpty || s.keyData.isNotEmpty) return s;
      final entry = entries[s.keyId];
      if (entry == null) return s;
      return s.copyWith(auth: s.auth.copyWith(keyData: entry.privateKey));
    }).toList();
  }

  List<SshKeyEntry> _selectedManagerKeyEntries() {
    if (!_options.hasManagerKeys) return const [];
    final all = data.managerKeyEntries;
    if (all.isEmpty) return const [];
    if (_options.includeAllManagerKeys) return all.values.toList();
    final usedIds = selectedSessions
        .where((s) => s.keyId.isNotEmpty)
        .map((s) => s.keyId)
        .toSet();
    return all.entries
        .where((e) => usedIds.contains(e.key))
        .map((e) => e.value)
        .toList();
  }

  /// Size contribution of one credential type, measured against a
  /// baseline of sessions-only (no other credentials). Deflate
  /// compression makes these non-additive, so values are approximate.
  int _credentialExtraSize({
    required bool includePasswords,
    required bool includeEmbeddedKeys,
    required bool includeManagerKeys,
  }) {
    if (selectedSessions.isEmpty) return 0;
    final baselineOptions = _options
        .withIncludePasswords(false)
        .withIncludeEmbeddedKeys(false)
        .withIncludeManagerKeys(false);
    final baseline = calculateExportPayloadSize(
      selectedSessions,
      input: ExportPayloadInput(options: baselineOptions),
    );
    final withCred = calculateExportPayloadSize(
      selectedSessions,
      input: ExportPayloadInput(
        options: _options
            .withIncludePasswords(includePasswords)
            .withIncludeEmbeddedKeys(includeEmbeddedKeys)
            .withIncludeManagerKeys(includeManagerKeys),
      ),
    );
    return (withCred - baseline).clamp(0, withCred);
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
      input: const ExportPayloadInput(options: baselineOptions),
    );
    final withCred = calculateExportPayloadSize(
      sessions,
      input: ExportPayloadInput(
        options: ExportOptions(
          includeSessions: true,
          includeConfig: false,
          includeKnownHosts: false,
          includePasswords: includePasswords,
          includeEmbeddedKeys: includeEmbeddedKeys,
          includeManagerKeys: includeManagerKeys,
        ),
      ),
    );
    return (withCred - baseline).clamp(0, withCred);
  }

  int get passwordsExtraSize {
    return _cachedPasswordsExtra ??= _credentialExtraSize(
      includePasswords: true,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
  }

  int get embeddedKeysExtraSize {
    if (_cachedEmbeddedKeysExtra != null) return _cachedEmbeddedKeysExtra!;
    // Only size sessions that carry embedded keys (keyId empty). We
    // check keyId (not keyData) because keyData may be populated from
    // storage even for manager-key sessions; keyId uniquely identifies
    // manager-key entries.
    final sessionsWithEmbedded = selectedSessions
        .where((s) => s.keyId.isEmpty)
        .toList();
    if (sessionsWithEmbedded.isEmpty) {
      return _cachedEmbeddedKeysExtra = 0;
    }
    return _cachedEmbeddedKeysExtra = _credentialExtraSizeForSessions(
      sessionsWithEmbedded,
      includePasswords: false,
      includeEmbeddedKeys: true,
      includeManagerKeys: false,
    );
  }

  int get managerKeysExtraSize {
    if (_cachedManagerKeysExtra != null) return _cachedManagerKeysExtra!;
    var managerKeys = data.managerKeys;
    if (managerKeys.isEmpty) return _cachedManagerKeysExtra = 0;

    // "Session keys" mode — filter to keys referenced by the current
    // session selection.
    if (_options.includeManagerKeys && !_options.includeAllManagerKeys) {
      final usedKeyIds = selectedSessions
          .where((s) => s.keyId.isNotEmpty)
          .map((s) => s.keyId)
          .toSet();
      managerKeys = Map.fromEntries(
        managerKeys.entries.where((e) => usedKeyIds.contains(e.key)),
      );
      if (managerKeys.isEmpty) return _cachedManagerKeysExtra = 0;
    }

    // Measure key-only payload size via a single dummy session.
    final dummySession = Session(
      label: 'x',
      server: const ServerAddress(host: 'x', user: 'x'),
    );

    final keyToShortId = <String, String>{};
    var keyCounter = 0;
    for (final keyData in managerKeys.values) {
      keyToShortId.putIfAbsent(keyData, () => 'k${keyCounter++}');
    }

    final keyMap = <String, String>{};
    keyToShortId.forEach((keyData, shortId) => keyMap[shortId] = keyData);
    final payload = <String, dynamic>{
      'km': keyMap,
      's': [encodeSessionCompact(dummySession)],
    };
    final json = jsonEncode(payload);
    final compressed = Deflate(utf8.encode(json)).getBytes();
    final withKeysSize = base64Url.encode(compressed).length;

    const baselineOptions = ExportOptions(
      includeSessions: true,
      includeConfig: false,
      includeKnownHosts: false,
      includePasswords: false,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
    final baselineSize = calculateExportPayloadSize([
      dummySession,
    ], input: const ExportPayloadInput(options: baselineOptions));

    return _cachedManagerKeysExtra = (withKeysSize - baselineSize).clamp(
      0,
      withKeysSize,
    );
  }

  int get configSize {
    if (_cachedConfigSize != null) return _cachedConfigSize!;
    if (data.config == null) return _cachedConfigSize = 0;
    return _cachedConfigSize = calculateExportPayloadSize(
      [],
      input: ExportPayloadInput(
        options: const ExportOptions(includeSessions: false),
        config: data.config,
      ),
    );
  }

  int get knownHostsSize {
    if (_cachedKnownHostsSize != null) return _cachedKnownHostsSize!;
    final content = data.knownHostsContent;
    if (content?.isNotEmpty != true) return _cachedKnownHostsSize = 0;
    return _cachedKnownHostsSize = calculateExportPayloadSize(
      [],
      input: ExportPayloadInput(
        options: const ExportOptions(
          includeSessions: false,
          includeConfig: false,
          includePasswords: false,
          includeEmbeddedKeys: false,
          includeManagerKeys: false,
        ),
        knownHostsContent: content,
      ),
    );
  }

  int get tagsSize {
    if (_cachedTagsSize != null) return _cachedTagsSize!;
    if (data.tags.isEmpty) return _cachedTagsSize = 0;
    return _cachedTagsSize = calculateExportPayloadSize(
      [],
      input: ExportPayloadInput(
        options: const ExportOptions(
          includeSessions: false,
          includeConfig: false,
          includeTags: true,
        ),
        tags: data.tags,
      ),
    );
  }

  int get snippetsSize {
    if (_cachedSnippetsSize != null) return _cachedSnippetsSize!;
    if (data.snippets.isEmpty) return _cachedSnippetsSize = 0;
    return _cachedSnippetsSize = calculateExportPayloadSize(
      [],
      input: ExportPayloadInput(
        options: const ExportOptions(
          includeSessions: false,
          includeConfig: false,
          includeSnippets: true,
        ),
        snippets: data.snippets,
      ),
    );
  }

  bool? isFolderPartial(String folderPath) {
    final folderSessionIds = data.sessions
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

  bool _isPresetActive(ExportOptions preset) {
    if (!allSelected) return false;
    return _options.includeSessions == preset.includeSessions &&
        _options.includeConfig == preset.includeConfig &&
        _options.includeKnownHosts == preset.includeKnownHosts &&
        _options.includePasswords == preset.includePasswords &&
        _options.includeEmbeddedKeys == preset.includeEmbeddedKeys &&
        _options.includeManagerKeys == preset.includeManagerKeys &&
        _options.includeAllManagerKeys == preset.includeAllManagerKeys &&
        _options.includeTags == preset.includeTags &&
        _options.includeSnippets == preset.includeSnippets;
  }

  // ---- Mutations -----------------------------------------------------

  void toggleCheckboxes() {
    _checkboxesExpanded = !_checkboxesExpanded;
    notifyListeners();
  }

  void toggleSession(String id) {
    _invalidatePayloadCache();
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void toggleFolder(String folderPath) {
    final folderSessionIds = data.sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .map((s) => s.id)
        .toSet();
    final everySelected = folderSessionIds.every(_selectedIds.contains);
    _invalidatePayloadCache();
    if (everySelected) {
      _selectedIds.removeAll(folderSessionIds);
    } else {
      _selectedIds.addAll(folderSessionIds);
    }
    notifyListeners();
  }

  void toggleAll(bool select) {
    _invalidatePayloadCache();
    if (select) {
      _selectedIds.addAll(data.sessions.map((s) => s.id));
    } else {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void applyFullBackupPreset() {
    _invalidatePayloadCache();
    _options = isQrMode ? _fullBackupPresetQr : _fullBackupPreset;
    _selectedIds.addAll(data.sessions.map((s) => s.id));
    notifyListeners();
  }

  /// "Sessions only" covers every session by definition — clicking the
  /// chip re-selects all so the highlight matches the chip's meaning.
  void applySessionsPreset() {
    _invalidatePayloadCache();
    _options = isQrMode ? _sessionsPresetQr : _sessionsPreset;
    _selectedIds.addAll(data.sessions.map((s) => s.id));
    notifyListeners();
  }

  void setIncludeConfig(bool value) =>
      _updateOptions((o) => o.withIncludeConfig(value));

  void setIncludePasswords(bool value) =>
      _updateOptions((o) => o.withIncludePasswords(value));

  void setIncludeEmbeddedKeys(bool value) =>
      _updateOptions((o) => o.withIncludeEmbeddedKeys(value));

  void setIncludeManagerKeys(bool value) => _updateOptions(
    (o) => o.withIncludeManagerKeys(value).withIncludeAllManagerKeys(false),
  );

  void setIncludeAllManagerKeys(bool value) => _updateOptions(
    (o) => o.withIncludeAllManagerKeys(value).withIncludeManagerKeys(false),
  );

  void setIncludeKnownHosts(bool value) =>
      _updateOptions((o) => o.withIncludeKnownHosts(value));

  void setIncludeTags(bool value) =>
      _updateOptions((o) => o.withIncludeTags(value));

  void setIncludeSnippets(bool value) =>
      _updateOptions((o) => o.withIncludeSnippets(value));

  void _updateOptions(ExportOptions Function(ExportOptions) f) {
    _invalidatePayloadCache();
    _options = f(_options);
    notifyListeners();
  }

  UnifiedExportResult buildResult() {
    return UnifiedExportResult(
      options: _options,
      selectedSessions: selectedSessions,
      selectedEmptyFolders: relevantEmptyFolders,
    );
  }

  // ---- Presets -------------------------------------------------------

  static const _qrInitial = ExportOptions(
    includeSessions: true,
    includeConfig: false,
    includeKnownHosts: false,
    includePasswords: true,
    includeEmbeddedKeys: false,
    includeManagerKeys: false,
    includeAllManagerKeys: false,
    includeTags: true,
    includeSnippets: true,
  );

  static const _lfsInitial = ExportOptions(
    includeConfig: true,
    includePasswords: true,
    includeEmbeddedKeys: true,
    includeAllManagerKeys: true,
    includeKnownHosts: true,
    includeTags: true,
    includeSnippets: true,
  );

  static const _fullBackupPreset = ExportOptions(
    includeSessions: true,
    includeConfig: true,
    includeKnownHosts: true,
    includePasswords: true,
    includeEmbeddedKeys: true,
    includeAllManagerKeys: true,
    includeTags: true,
    includeSnippets: true,
  );

  static const _sessionsPreset = ExportOptions(
    includeSessions: true,
    includeConfig: false,
    includeKnownHosts: false,
    includePasswords: true,
    includeEmbeddedKeys: true,
    includeManagerKeys: true,
    includeTags: true,
    includeSnippets: true,
  );

  /// QR-mode variants of the presets. SSH keys (both the embedded
  /// per-session slot and the manager-pulled slot) are off by default
  /// because QR payloads have a hard size ceiling and a single
  /// 4096-bit RSA key alone blows past it. Users who explicitly want
  /// keys over a QR scan toggle them on individually; the chip-level
  /// "Full backup" / "Sessions" one-click preset no longer ships them
  /// pre-selected in QR mode.
  static const _fullBackupPresetQr = ExportOptions(
    includeSessions: true,
    includeConfig: true,
    includeKnownHosts: true,
    includePasswords: true,
    includeEmbeddedKeys: false,
    includeAllManagerKeys: false,
    includeTags: true,
    includeSnippets: true,
  );

  static const _sessionsPresetQr = ExportOptions(
    includeSessions: true,
    includeConfig: false,
    includeKnownHosts: false,
    includePasswords: true,
    includeEmbeddedKeys: false,
    includeManagerKeys: false,
    includeTags: true,
    includeSnippets: true,
  );
}
