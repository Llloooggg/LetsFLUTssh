import '../../src/rust/api/config.dart' as rust_config;
import '../../src/rust/api/config.dart'
    show
        DbAppConfigSnapshot,
        DbBehaviorConfig,
        DbSshDefaults,
        DbTerminalConfig,
        DbUiConfig;
import '../../src/rust/api/security_capabilities.dart'
    show DbSecurityCapabilities;
import '../../src/rust/api/security_config.dart' show DbSecurityConfig;
import '../../src/rust/api/sync.dart' show DbSyncConfig;
import '../../utils/logger.dart'
    show LogLevel, logLevelFromJson, logLevelToJson;
import '../security/security_tier.dart';

/// Terminal display settings.
///
/// Pure typed value object — the JSON wire shape lives in
/// `lfs_core::config::TerminalConfig` and the parse / validate /
/// clamp pipeline runs Rust-side via the [`DbAppConfigSnapshot`]
/// round-trip the `configStoreGetTyped` / `configStoreSetTyped`
/// endpoints expose. Constructors here build in-memory state only;
/// out-of-range inputs are clamped inside Rust before they reach the
/// store actor.
class TerminalConfig {
  final double fontSize;
  final String theme; // 'dark', 'light', 'system'
  final int scrollback;

  const TerminalConfig({
    this.fontSize = 14.0,
    this.theme = 'system',
    this.scrollback = 5000,
  });

  static const defaults = TerminalConfig();

  TerminalConfig copyWith({double? fontSize, String? theme, int? scrollback}) =>
      TerminalConfig(
        fontSize: fontSize ?? this.fontSize,
        theme: theme ?? this.theme,
        scrollback: scrollback ?? this.scrollback,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalConfig &&
          fontSize == other.fontSize &&
          theme == other.theme &&
          scrollback == other.scrollback;

  @override
  int get hashCode => Object.hash(fontSize, theme, scrollback);

  /// Rebuild from the FRB typed mirror. Rust-side sanitiser already
  /// clamped every field on the way out of [`configStoreGetTyped`].
  factory TerminalConfig.fromTyped(DbTerminalConfig db) => TerminalConfig(
    fontSize: db.fontSize,
    theme: db.theme,
    scrollback: db.scrollback.toInt(),
  );

  /// Build the FRB typed mirror for a set call. The Rust side will
  /// re-clamp out-of-range values during [`AppConfig::sanitized`].
  DbTerminalConfig toTyped() => DbTerminalConfig(
    fontSize: fontSize,
    theme: theme,
    scrollback: scrollback,
  );
}

/// SSH connection defaults. See [TerminalConfig] for the parser
/// ownership rule — Rust owns the grammar.
class SshDefaults {
  final int keepAliveSec;
  final int defaultPort;
  final int sshTimeoutSec;

  /// Capture russh's verbose handshake / auth trace into the opt-in
  /// file log (ssh -vvv-style). Off by default — noisy, diagnostic-only.
  final bool verboseConnectionLog;

  const SshDefaults({
    this.keepAliveSec = 30,
    this.defaultPort = 22,
    this.sshTimeoutSec = 10,
    this.verboseConnectionLog = false,
  });

  static const defaults = SshDefaults();

  SshDefaults copyWith({
    int? keepAliveSec,
    int? defaultPort,
    int? sshTimeoutSec,
    bool? verboseConnectionLog,
  }) => SshDefaults(
    keepAliveSec: keepAliveSec ?? this.keepAliveSec,
    defaultPort: defaultPort ?? this.defaultPort,
    sshTimeoutSec: sshTimeoutSec ?? this.sshTimeoutSec,
    verboseConnectionLog: verboseConnectionLog ?? this.verboseConnectionLog,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshDefaults &&
          keepAliveSec == other.keepAliveSec &&
          defaultPort == other.defaultPort &&
          sshTimeoutSec == other.sshTimeoutSec &&
          verboseConnectionLog == other.verboseConnectionLog;

  @override
  int get hashCode => Object.hash(
    keepAliveSec,
    defaultPort,
    sshTimeoutSec,
    verboseConnectionLog,
  );

  factory SshDefaults.fromTyped(DbSshDefaults db) => SshDefaults(
    keepAliveSec: db.keepaliveSec.toInt(),
    defaultPort: db.defaultPort.toInt(),
    sshTimeoutSec: db.sshTimeoutSec.toInt(),
    verboseConnectionLog: db.verboseConnectionLog,
  );

  DbSshDefaults toTyped() => DbSshDefaults(
    keepaliveSec: keepAliveSec,
    defaultPort: defaultPort,
    sshTimeoutSec: sshTimeoutSec,
    verboseConnectionLog: verboseConnectionLog,
  );
}

/// UI and window settings. See [TerminalConfig] for the parser
/// ownership rule — Rust owns the grammar.
class UiConfig {
  final int toastDurationMs;
  final double windowWidth;
  final double windowHeight;
  final double uiScale;
  final bool showFolderSizes;

  const UiConfig({
    this.toastDurationMs = 4000,
    this.windowWidth = 1100,
    this.windowHeight = 650,
    this.uiScale = 1.0,
    this.showFolderSizes = false,
  });

  static const defaults = UiConfig();

  UiConfig copyWith({
    int? toastDurationMs,
    double? windowWidth,
    double? windowHeight,
    double? uiScale,
    bool? showFolderSizes,
  }) => UiConfig(
    toastDurationMs: toastDurationMs ?? this.toastDurationMs,
    windowWidth: windowWidth ?? this.windowWidth,
    windowHeight: windowHeight ?? this.windowHeight,
    uiScale: uiScale ?? this.uiScale,
    showFolderSizes: showFolderSizes ?? this.showFolderSizes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UiConfig &&
          toastDurationMs == other.toastDurationMs &&
          windowWidth == other.windowWidth &&
          windowHeight == other.windowHeight &&
          uiScale == other.uiScale &&
          showFolderSizes == other.showFolderSizes;

  @override
  int get hashCode => Object.hash(
    toastDurationMs,
    windowWidth,
    windowHeight,
    uiScale,
    showFolderSizes,
  );

  factory UiConfig.fromTyped(DbUiConfig db) => UiConfig(
    toastDurationMs: db.toastDurationMs.toInt(),
    windowWidth: db.windowWidth,
    windowHeight: db.windowHeight,
    uiScale: db.uiScale,
    showFolderSizes: db.showFolderSizes,
  );

  DbUiConfig toTyped() => DbUiConfig(
    toastDurationMs: toastDurationMs,
    windowWidth: windowWidth,
    windowHeight: windowHeight,
    uiScale: uiScale,
    showFolderSizes: showFolderSizes,
  );
}

/// App behavior settings: logging, update checks, skipped versions.
///
/// Auto-lock timeout is NOT here — it lives in the encrypted DB
/// (`AppConfigs.auto_lock_minutes`) so an attacker with plaintext-disk
/// access cannot weaken the security control by editing a plaintext
/// file. See [autoLockMinutesProvider] in
/// `lib/providers/auto_lock_provider.dart`.
class BehaviorConfig {
  /// Minimum severity the routine file sink admits. `null` = logging
  /// off (default). Picking any [LogLevel] opens the sink and writes
  /// lines at or above that level, so picking `warn` writes W + E,
  /// picking `info` writes everything.
  final LogLevel? logLevel;
  final bool checkUpdatesOnStart;
  final String? skippedVersion;

  /// "Prefer direct USB HID over system dialog" toggle from the
  /// Settings security section. Off by default. On Windows / macOS
  /// the dispatcher in `lfs_core::fido2::brokers` skips the OS
  /// security-key dialog and uses the direct CTAP2 HID transport
  /// when this is on. Linux ignores it (no broker exists there);
  /// iOS / Android ignore it (only the broker path works there).
  final bool fido2PreferDirectHid;

  const BehaviorConfig({
    this.logLevel,
    this.checkUpdatesOnStart = true,
    this.skippedVersion,
    this.fido2PreferDirectHid = false,
  });

  static const defaults = BehaviorConfig();

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  BehaviorConfig copyWith({
    Object? logLevel = _unset,
    bool? checkUpdatesOnStart,
    Object? skippedVersion = _unset,
    bool? fido2PreferDirectHid,
  }) => BehaviorConfig(
    logLevel: identical(logLevel, _unset)
        ? this.logLevel
        : logLevel as LogLevel?,
    checkUpdatesOnStart: checkUpdatesOnStart ?? this.checkUpdatesOnStart,
    skippedVersion: identical(skippedVersion, _unset)
        ? this.skippedVersion
        : skippedVersion as String?,
    fido2PreferDirectHid: fido2PreferDirectHid ?? this.fido2PreferDirectHid,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorConfig &&
          logLevel == other.logLevel &&
          checkUpdatesOnStart == other.checkUpdatesOnStart &&
          skippedVersion == other.skippedVersion &&
          fido2PreferDirectHid == other.fido2PreferDirectHid;

  @override
  int get hashCode => Object.hash(
    logLevel,
    checkUpdatesOnStart,
    skippedVersion,
    fido2PreferDirectHid,
  );

  factory BehaviorConfig.fromTyped(DbBehaviorConfig db) => BehaviorConfig(
    logLevel: logLevelFromJson(db.logLevelWireName),
    checkUpdatesOnStart: db.checkUpdatesOnStart,
    skippedVersion: db.skippedVersion,
    fido2PreferDirectHid: db.fido2PreferDirectHid,
  );

  DbBehaviorConfig toTyped() => DbBehaviorConfig(
    logLevelWireName: logLevelToJson(logLevel),
    checkUpdatesOnStart: checkUpdatesOnStart,
    skippedVersion: skippedVersion,
    fido2PreferDirectHid: fido2PreferDirectHid,
  );
}

/// Application configuration model.
///
/// Same fields and defaults as LetsGOssh config.
/// Grouped into sub-configs: [terminal], [ssh], [ui], [behavior].
///
/// Persistence + JSON grammar + range validation all live in
/// `lfs_core::config::AppConfig`. The Dart side only carries the
/// parsed snapshot; mutations route back through
/// `configStoreSetTyped` (or the partial-update FRB endpoints for
/// sync / security tier / probe cache). The Rust sanitiser clamps
/// every out-of-range field before the disk write.
class AppConfig {
  final TerminalConfig terminal;
  final SshDefaults ssh;
  final UiConfig ui;
  final BehaviorConfig behavior;
  final int transferWorkers;
  final int maxHistory;
  final String? locale;

  /// Persisted security tier + modifiers. `null` means the user has
  /// not yet been through the first-launch security wizard — the app
  /// shows the wizard on next launch and writes the chosen config
  /// back. Non-null (including `SecurityConfig.none` variants) means
  /// the wizard has already run and the tier is authoritative.
  final SecurityConfig? security;

  /// Cached snapshot of the last `probeCapabilities` run — keychain
  /// + hardware-vault + biometric availability plus the raw probe
  /// reason codes. The `securityCapabilitiesProvider` reads this on
  /// startup and returns it instead of paying the real SE / TPM /
  /// Keystore round-trip cost, so Settings opens against ready data
  /// and the tier cards stop flickering during the first paint.
  ///
  /// Null = no probe has run yet (fresh install) or the cache was
  /// invalidated (Recheck button, corruption-retry path, wipe).
  /// Stale-positive risk is by design — probe is host state, the
  /// Recheck button is the user's tool to force a fresh read after
  /// they change the host (enable TPM in BIOS, run
  /// `macos-resign.sh`, enrol a biometric, etc.).
  final DbSecurityCapabilities? securityProbeCache;

  /// Aggregate byte ceiling for the recordings tree under
  /// `<appSupport>/recordings/`. The Rust recorder's
  /// `register_with_io` + `close_with_io` hooks call
  /// `enforce_storage_cap` (LRU eviction sweep, oldest-mtime first)
  /// against this value so the on-disk total stays at or below the
  /// configured cap. Mirror of `AppConfig.recordings_storage_cap_bytes`
  /// in `lfs_core::config`. Default
  /// `defaultRecordingsStorageCapBytes` (500 MiB).
  final int recordingsStorageCapBytes;

  /// 500 MiB, mirror of
  /// `lfs_core::config::DEFAULT_RECORDINGS_STORAGE_CAP_BYTES`. Pinned
  /// as a Dart-side constant so tests / call sites can reference the
  /// canonical value without re-running the Rust round-trip.
  static const int defaultRecordingsStorageCapBytes = 500 * 1024 * 1024;

  /// Locale codes supported by the app.
  static const supportedLocales = [
    'en',
    'ru',
    'zh',
    'de',
    'ja',
    'pt',
    'es',
    'fr',
    'ko',
    'ar',
    'fa',
    'tr',
    'vi',
    'id',
    'hi',
  ];

  const AppConfig({
    this.terminal = const TerminalConfig(),
    this.ssh = const SshDefaults(),
    this.ui = const UiConfig(),
    this.behavior = const BehaviorConfig(),
    this.transferWorkers = 2,
    this.maxHistory = 500,
    this.locale,
    this.security,
    this.securityProbeCache,
    this.recordingsStorageCapBytes = defaultRecordingsStorageCapBytes,
  });

  static const AppConfig defaults = AppConfig();

  // --- Convenience accessors (keep call sites short) ---
  double get fontSize => terminal.fontSize;
  String get theme => terminal.theme;
  int get scrollback => terminal.scrollback;
  int get keepAliveSec => ssh.keepAliveSec;
  int get defaultPort => ssh.defaultPort;
  int get sshTimeoutSec => ssh.sshTimeoutSec;
  bool get verboseConnectionLog => ssh.verboseConnectionLog;
  int get toastDurationMs => ui.toastDurationMs;
  double get windowWidth => ui.windowWidth;
  double get windowHeight => ui.windowHeight;
  double get uiScale => ui.uiScale;
  bool get showFolderSizes => ui.showFolderSizes;
  LogLevel? get logLevel => behavior.logLevel;
  bool get checkUpdatesOnStart => behavior.checkUpdatesOnStart;
  String? get skippedVersion => behavior.skippedVersion;

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  /// Non-security preferences copy. Split out from [copyWithSecurity]
  /// to keep the parameter count below the S107 threshold and to
  /// encode the two axes the UI actually uses: preference screens
  /// only ever touch these fields, while the unlock / tier flow
  /// only ever touches [security] / [securityProbeCache].
  AppConfig copyWith({
    TerminalConfig? terminal,
    SshDefaults? ssh,
    UiConfig? ui,
    BehaviorConfig? behavior,
    int? transferWorkers,
    int? maxHistory,
    Object? locale = _unset,
    int? recordingsStorageCapBytes,
  }) {
    return AppConfig(
      terminal: terminal ?? this.terminal,
      ssh: ssh ?? this.ssh,
      ui: ui ?? this.ui,
      behavior: behavior ?? this.behavior,
      transferWorkers: transferWorkers ?? this.transferWorkers,
      maxHistory: maxHistory ?? this.maxHistory,
      locale: identical(locale, _unset) ? this.locale : locale as String?,
      security: security,
      securityProbeCache: securityProbeCache,
      recordingsStorageCapBytes:
          recordingsStorageCapBytes ?? this.recordingsStorageCapBytes,
    );
  }

  /// Security-only copy. Pair for [copyWith] — see its docs for why
  /// the split exists. Either or both fields may be cleared by
  /// passing `null`; omitting a parameter leaves the current value
  /// in place.
  AppConfig copyWithSecurity({
    Object? security = _unset,
    Object? securityProbeCache = _unset,
  }) {
    return AppConfig(
      terminal: terminal,
      ssh: ssh,
      ui: ui,
      behavior: behavior,
      transferWorkers: transferWorkers,
      maxHistory: maxHistory,
      locale: locale,
      security: identical(security, _unset)
          ? this.security
          : security as SecurityConfig?,
      securityProbeCache: identical(securityProbeCache, _unset)
          ? this.securityProbeCache
          : securityProbeCache as DbSecurityCapabilities?,
      recordingsStorageCapBytes: recordingsStorageCapBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          terminal == other.terminal &&
          ssh == other.ssh &&
          ui == other.ui &&
          behavior == other.behavior &&
          transferWorkers == other.transferWorkers &&
          maxHistory == other.maxHistory &&
          locale == other.locale &&
          security == other.security &&
          securityProbeCache == other.securityProbeCache &&
          recordingsStorageCapBytes == other.recordingsStorageCapBytes;

  @override
  int get hashCode => Object.hash(
    terminal,
    ssh,
    ui,
    behavior,
    transferWorkers,
    maxHistory,
    locale,
    security,
    securityProbeCache,
    recordingsStorageCapBytes,
  );

  /// Rebuild from the FRB typed mirror that
  /// [`configStoreGetTyped`] hands back. The Rust side already ran
  /// [`AppConfig::sanitized`] before the snapshot crossed the
  /// boundary, so the values land in valid ranges.
  factory AppConfig.fromTyped(DbAppConfigSnapshot db) {
    final security = _securityConfigFromTyped(db.security);
    return AppConfig(
      terminal: TerminalConfig.fromTyped(db.terminal),
      ssh: SshDefaults.fromTyped(db.ssh),
      ui: UiConfig.fromTyped(db.ui),
      behavior: BehaviorConfig.fromTyped(db.behavior),
      transferWorkers: db.transferWorkers.toInt(),
      maxHistory: db.maxHistory.toInt(),
      locale: db.locale,
      security: security,
      securityProbeCache: db.securityProbeCache,
      recordingsStorageCapBytes: db.recordingsStorageCapBytes.toInt(),
    );
  }

  /// Build the FRB typed mirror for a `set` call. Sync sub-bag and
  /// [securityProbeCache] both come from [`configStoreGetTyped`]
  /// verbatim — both are Rust-owned and the Dart side never holds
  /// the authoritative copy. [sync] is the per-push / per-pull state;
  /// [probeCache] is the device-local hardware-capability cache the
  /// Rust capabilities-persister writes. Passing them through (rather
  /// than the possibly-stale Dart fields) stops an unrelated settings
  /// change from wiping the value Rust just wrote: a full `set_json`
  /// replaces the whole snapshot, so a stale Dart `null` would
  /// otherwise clobber the cache and force a TPM/Secure-Enclave
  /// re-probe on the next launch. Callers that haven't observed a
  /// snapshot fall back to the canonical empty sync bag / the local
  /// [securityProbeCache] field.
  DbAppConfigSnapshot toTyped({
    DbSyncConfig? sync,
    DbSecurityCapabilities? probeCache,
  }) {
    final effectiveSync =
        sync ?? rust_config.configAppConfigDefaultsTyped().sync_;
    return DbAppConfigSnapshot(
      terminal: terminal.toTyped(),
      ssh: ssh.toTyped(),
      ui: ui.toTyped(),
      behavior: behavior.toTyped(),
      transferWorkers: transferWorkers,
      maxHistory: maxHistory,
      locale: locale,
      security: _securityConfigToTyped(security),
      securityProbeCache: probeCache ?? securityProbeCache,
      recordingsStorageCapBytes: BigInt.from(recordingsStorageCapBytes),
      sync_: effectiveSync,
    );
  }
}

SecurityConfig? _securityConfigFromTyped(DbSecurityConfig? db) {
  if (db == null) return null;
  // The typed `DbSecurityConfig.tier` already filtered unknown wire
  // names Rust-side (`SecurityTier::from_wire_name` returns Option;
  // the `From<AppConfig>` impl in the FRB layer collapses unknown
  // tiers to `Plaintext` so the caller routes into the wizard rather
  // than landing on a silently-wrong tier). No second decode needed
  // here — the field is already the typed enum.
  return SecurityConfig(
    tier: db.tier,
    modifiers: SecurityTierModifiers(
      password: db.password,
      biometric: db.biometric,
    ),
  );
}

DbSecurityConfig? _securityConfigToTyped(SecurityConfig? config) {
  if (config == null) return null;
  return DbSecurityConfig(
    tier: config.tier,
    password: config.modifiers.password,
    biometric: config.modifiers.biometric,
  );
}
