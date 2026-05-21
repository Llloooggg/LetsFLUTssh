import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/session/qr_codec.dart' show ExportOptions, qrMaxPayloadBytes;
import '../core/session/session.dart';
import '../core/import/export_import.dart';
import '../src/rust/api/archive.dart' as rust_archive;
import '../src/rust/api/config.dart' as rust_config;
import '../src/rust/api/qr_compose.dart' as rust_compose;
import '../utils/format.dart' as utils_format;
import 'unified_export_models.dart';

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

  /// Thin forward over `lfs_core::archive::resolve_relevant_empty_folders`.
  /// The folder-tree union rule (ancestor expansion + descendant /
  /// ancestor / equal source-set entries + full-tree on all-selected)
  /// lives Rust-side so Dart and the archive composer agree on the
  /// shape byte-for-byte. The dialog still owns the inputs (selected
  /// sessions' folders + `all_selected` flag) since they're trivial
  /// to derive from Dart-side selection state.
  Set<String> get relevantEmptyFolders {
    final selectedFolders = selectedSessions
        .map((s) => s.folder)
        .toList(growable: false);
    final all = _selectedIds.length == data.sessions.length;
    final resolved = rust_archive.archiveResolveRelevantEmptyFolders(
      selectedSessionFolders: selectedFolders,
      sourceEmptyFolders: data.emptyFolders.toList(growable: false),
      allSelected: all,
    );
    return resolved.toSet();
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
  /// Routes through the canonical `lfs_core::format::format_size`
  /// via `utils/format.dart` so the QR-export size readout shares
  /// the project-wide B / KB / MB / GB ladder. QR payloads cap at
  /// `qrMaxPayloadBytes` (~2 KB), so in production this only ever
  /// renders B or KB; the wider ladder is dead-but-correct branch.
  static String formatSize(int bytes) => utils_format.formatSize(bytes);

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
  /// `settings_sections_data._generateQrExport` will emit. Trap:
  /// omitting them underestimates the payload, so the UI claims
  /// "fits" while the encoder appends the `tg` / `sn` sections on
  /// export and pushes past the 2 KB ceiling — the user then gets a
  /// bare "QR too large" toast with no indication that tags were the
  /// culprit.
  ///
  /// Routes through `lfs_core::archive::qr_export_payload_size` (FRB
  /// sync, id-based) so the wire shape stays one place across the
  /// estimator + the production `db_export_qr_payload` path. The
  /// composer reads sessions / keys / tags / snippets straight from
  /// the open SQLCipher connection — manager-key PEM bytes never
  /// cross the FRB boundary into Dart memory for the gauge.
  int _qrPayloadSize() {
    return _qrEstimateSize(options: _options);
  }

  /// Hand the option flags + selected ids to the Rust composer; it
  /// pulls every payload component (sessions, keys, tags, snippets,
  /// link tables) from the DB by id.
  ///
  /// `sessionIds` defaults to the dialog's current selection. The
  /// per-credential-type extras helpers below override it (e.g.
  /// "size delta from embedded keys" filters to sessions that
  /// actually carry embedded material).
  int _qrEstimateSize({
    required ExportOptions options,
    Iterable<String>? sessionIds,
    Iterable<String>? emptyFolders,
  }) {
    final ids = (sessionIds ?? selectedSessions.map((s) => s.id)).toList(
      growable: false,
    );
    final folders = (emptyFolders ?? relevantEmptyFolders).toList(
      growable: false,
    );
    return rust_compose.qrEstimateExportSize(
      input: rust_archive.DbQrExportInput(
        options: rust_archive.DbQrExportOptions(
          includeSessions: options.includeSessions,
          includeConfig: options.includeConfig,
          includeKnownHosts: options.includeKnownHosts,
          includePasswords: options.includePasswords,
          includeEmbeddedKeys: options.includeEmbeddedKeys,
          includeManagerKeys: options.includeManagerKeys,
          includeAllManagerKeys: options.includeAllManagerKeys,
          includeTags: options.includeTags,
          includeSnippets: options.includeSnippets,
        ),
        selectedSessionIds: ids,
        selectedEmptyFolders: folders,
        configJson: options.includeConfig && data.config != null
            ? rust_config.configAppConfigToJsonTyped(
                value: data.config!.toTyped(),
              )
            : null,
      ),
    );
  }

  /// `.lfs` archive size for the live preview line. Routes through
  /// `lfs_core::archive::export_archive_size` (FRB sync, id-based) —
  /// the composer builds the inner ZIP exactly the way the
  /// production `export_archive` does, then adds the LFSE envelope
  /// overhead constant when the master-password slot is set. PEM
  /// bytes for manager keys never cross the FRB boundary.
  int _lfsArchiveSize() {
    final selectedIds = selectedSessions
        .map((s) => s.id)
        .toList(growable: false);
    return rust_archive.dbLfsExportSize(
      input: rust_archive.DbExportInput(
        options: rust_archive.DbExportOptions(
          includeSessions: _options.includeSessions,
          includeKnownHosts: _options.includeKnownHosts,
          includeConfig: _options.includeConfig,
          includeTags: _options.includeTags,
          includeSnippets: _options.includeSnippets,
          includeAllManagerKeys: _options.includeAllManagerKeys,
          hasManagerKeys: _options.hasManagerKeys,
          includeRecordings: _options.includeRecordings,
        ),
        selectedSessionIds: selectedIds,
        selectedEmptyFolders: relevantEmptyFolders.toList(growable: false),
        configJson: _options.includeConfig && data.config != null
            ? rust_config.configAppConfigStripForExportTyped(
                value: (data.config ?? AppConfig.defaults).toTyped(),
              )
            : '',
        schemaVersion: ExportImport.currentSchemaVersion,
        appVersion: null,
        // Empty bytes — the live preview runs before the user
        // reaches the master-password prompt, so the estimator
        // measures the unencrypted shape. The 75-byte LFSE
        // envelope overhead is tiny vs typical archive sizes; the
        // gauge is accurate within rounding.
        masterPassword: Uint8List(0),
        kdfMemoryKib: 0,
        kdfIterations: 0,
        kdfParallelism: 0,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Size contribution of one credential type, measured as the
  /// delta between two id-based estimator runs. Deflate
  /// compression makes these non-additive, so values are
  /// approximate. Both runs go through the same Rust composer, so
  /// the delta is the only Dart-side arithmetic.
  int _credentialExtraSize({
    required bool includePasswords,
    required bool includeEmbeddedKeys,
    required bool includeManagerKeys,
    Iterable<String>? sessionIds,
  }) {
    final ids = sessionIds ?? selectedSessions.map((s) => s.id);
    final idsList = ids.toList(growable: false);
    if (idsList.isEmpty) return 0;
    const baselineOptions = ExportOptions(
      includeSessions: true,
      includeConfig: false,
      includeKnownHosts: false,
      includePasswords: false,
      includeEmbeddedKeys: false,
      includeManagerKeys: false,
    );
    final baseline = _qrEstimateSize(
      options: baselineOptions,
      sessionIds: idsList,
      emptyFolders: const <String>{},
    );
    final withCred = _qrEstimateSize(
      options: ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: false,
        includePasswords: includePasswords,
        includeEmbeddedKeys: includeEmbeddedKeys,
        includeManagerKeys: includeManagerKeys,
      ),
      sessionIds: idsList,
      emptyFolders: const <String>{},
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
    // Only size sessions that carry embedded keys (keyId empty).
    // keyId (not keyData) uniquely identifies manager-key sessions
    // because keyData may be populated from storage even for
    // manager-key sessions.
    final embeddedIds = selectedSessions
        .where((s) => s.keyId.isEmpty)
        .map((s) => s.id)
        .toList(growable: false);
    if (embeddedIds.isEmpty) return _cachedEmbeddedKeysExtra = 0;
    return _cachedEmbeddedKeysExtra = _credentialExtraSize(
      includePasswords: false,
      includeEmbeddedKeys: true,
      includeManagerKeys: false,
      sessionIds: embeddedIds,
    );
  }

  /// Size delta between "manager keys included" and "manager keys
  /// excluded" estimator runs. The Rust composer pulls the keys
  /// (and the per-session keyId references that anchor them) from
  /// the SQLCipher row by id — the Dart heap never sees the PEM.
  int get managerKeysExtraSize {
    if (_cachedManagerKeysExtra != null) return _cachedManagerKeysExtra!;
    final ids = selectedSessions.map((s) => s.id).toList(growable: false);
    if (ids.isEmpty) return _cachedManagerKeysExtra = 0;
    final baseline = _qrEstimateSize(
      options: const ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: false,
        includePasswords: false,
        includeEmbeddedKeys: false,
        includeManagerKeys: false,
      ),
      sessionIds: ids,
      emptyFolders: const <String>{},
    );
    final withKeys = _qrEstimateSize(
      options: ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: false,
        includePasswords: false,
        includeEmbeddedKeys: false,
        includeManagerKeys: _options.includeManagerKeys,
        includeAllManagerKeys: _options.includeAllManagerKeys,
      ),
      sessionIds: ids,
      emptyFolders: const <String>{},
    );
    return _cachedManagerKeysExtra = (withKeys - baseline).clamp(0, withKeys);
  }

  int get configSize {
    if (_cachedConfigSize != null) return _cachedConfigSize!;
    if (data.config == null) return _cachedConfigSize = 0;
    return _cachedConfigSize = _qrEstimateSize(
      options: const ExportOptions(includeSessions: false, includeConfig: true),
      sessionIds: const <String>[],
      emptyFolders: const <String>{},
    );
  }

  int get knownHostsSize {
    if (_cachedKnownHostsSize != null) return _cachedKnownHostsSize!;
    final content = data.knownHostsContent;
    if (content?.isNotEmpty != true) return _cachedKnownHostsSize = 0;
    return _cachedKnownHostsSize = _qrEstimateSize(
      options: const ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includeKnownHosts: true,
      ),
      sessionIds: const <String>[],
      emptyFolders: const <String>{},
    );
  }

  int get tagsSize {
    if (_cachedTagsSize != null) return _cachedTagsSize!;
    if (data.tags.isEmpty) return _cachedTagsSize = 0;
    return _cachedTagsSize = _qrEstimateSize(
      options: const ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includeTags: true,
      ),
      sessionIds: const <String>[],
      emptyFolders: const <String>{},
    );
  }

  int get snippetsSize {
    if (_cachedSnippetsSize != null) return _cachedSnippetsSize!;
    if (data.snippets.isEmpty) return _cachedSnippetsSize = 0;
    return _cachedSnippetsSize = _qrEstimateSize(
      options: const ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includeSnippets: true,
      ),
      sessionIds: const <String>[],
      emptyFolders: const <String>{},
    );
  }

  /// Total `<appSupport>/recordings/` size — drives the per-row
  /// label on the Recordings checkbox so the user sees the
  /// archive's true cost before ticking it on. Pre-measured by the
  /// caller (the Rust getter is async) and threaded in via
  /// [UnifiedExportDialogData.recordingsBytes], same number the
  /// Settings → Data → Recordings tile shows.
  ///
  /// The estimate is the on-disk total; the compose path decrypts
  /// `.lfsr` to plaintext `.cast` (typically smaller because GCM
  /// tags + per-file-header overhead drop), so the actual archive
  /// delta sits at or below this number.
  int get recordingsSize => data.recordingsBytes;

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
        _options.includeSnippets == preset.includeSnippets &&
        _options.includeRecordings == preset.includeRecordings;
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

  void setIncludeRecordings(bool value) =>
      _updateOptions((o) => o.withIncludeRecordings(value));

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
    includeRecordings: true,
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
    includeRecordings: true,
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
