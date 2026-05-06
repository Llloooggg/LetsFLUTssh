import 'dart:convert';

import '../../src/rust/api/config.dart' as rust_config;
import '../../utils/logger.dart'
    show LogLevel, logLevelFromJson, logLevelToJson;
import '../security/security_bootstrap.dart' show SecurityCapabilities;
import '../security/security_tier.dart';

/// Terminal display settings.
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
  static const _validThemes = ['dark', 'light', 'system'];

  /// Upper bound on the user-supplied `scrollback`. xterm allocates
  /// per-line buffers eagerly; an unclamped `cat /dev/urandom` into
  /// a window with `maxLines: 1_000_000_000` would OOM the renderer.
  /// 200 000 lines is enough for a full work-session of `tail -f` on
  /// a chatty log file (~12 hours of 5-line/s output) and stays
  /// below the ~50 MiB-per-pane cap on a typical 80x24 terminal.
  static const int maxScrollback = 200000;

  String? validate() {
    if (fontSize < 6 || fontSize > 72) return 'Font size must be 6-72';
    if (!_validThemes.contains(theme)) {
      return 'Theme must be one of: ${_validThemes.join(', ')}';
    }
    if (scrollback < 100) return 'Scrollback must be at least 100';
    if (scrollback > maxScrollback) {
      return 'Scrollback must be at most $maxScrollback';
    }
    return null;
  }

  TerminalConfig sanitized() {
    const d = TerminalConfig.defaults;
    final int sanitizedScrollback;
    if (scrollback < 100) {
      // Too-small / non-positive — fall back to the default rather
      // than the floor so a user who saw a confusing 100-line
      // window after typing 0 lands on the working-default value.
      sanitizedScrollback = d.scrollback;
    } else if (scrollback > maxScrollback) {
      sanitizedScrollback = maxScrollback;
    } else {
      sanitizedScrollback = scrollback;
    }
    return TerminalConfig(
      fontSize: fontSize.clamp(6, 72),
      theme: _validThemes.contains(theme) ? theme : d.theme,
      scrollback: sanitizedScrollback,
    );
  }

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

  Map<String, dynamic> toJson() => {
    'font_size': fontSize,
    'theme': theme,
    'scrollback': scrollback,
  };

  factory TerminalConfig.fromJson(Map<String, dynamic> json) {
    const d = TerminalConfig.defaults;
    return TerminalConfig(
      fontSize: (json['font_size'] as num?)?.toDouble() ?? d.fontSize,
      theme: json['theme'] as String? ?? d.theme,
      scrollback: json['scrollback'] as int? ?? d.scrollback,
    ).sanitized();
  }
}

/// SSH connection defaults.
class SshDefaults {
  final int keepAliveSec;
  final int defaultPort;
  final int sshTimeoutSec;

  const SshDefaults({
    this.keepAliveSec = 30,
    this.defaultPort = 22,
    this.sshTimeoutSec = 10,
  });

  static const defaults = SshDefaults();

  String? validate() {
    if (keepAliveSec < 0) return 'Keep-alive must be non-negative';
    if (defaultPort < 1 || defaultPort > 65535) return 'Port must be 1-65535';
    if (sshTimeoutSec < 1) return 'SSH timeout must be at least 1 second';
    return null;
  }

  SshDefaults sanitized() {
    const d = SshDefaults.defaults;
    return SshDefaults(
      keepAliveSec: keepAliveSec < 0 ? d.keepAliveSec : keepAliveSec,
      defaultPort: (defaultPort < 1 || defaultPort > 65535)
          ? d.defaultPort
          : defaultPort,
      sshTimeoutSec: sshTimeoutSec < 1 ? d.sshTimeoutSec : sshTimeoutSec,
    );
  }

  SshDefaults copyWith({
    int? keepAliveSec,
    int? defaultPort,
    int? sshTimeoutSec,
  }) => SshDefaults(
    keepAliveSec: keepAliveSec ?? this.keepAliveSec,
    defaultPort: defaultPort ?? this.defaultPort,
    sshTimeoutSec: sshTimeoutSec ?? this.sshTimeoutSec,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshDefaults &&
          keepAliveSec == other.keepAliveSec &&
          defaultPort == other.defaultPort &&
          sshTimeoutSec == other.sshTimeoutSec;

  @override
  int get hashCode => Object.hash(keepAliveSec, defaultPort, sshTimeoutSec);

  Map<String, dynamic> toJson() => {
    'keepalive_sec': keepAliveSec,
    'default_port': defaultPort,
    'ssh_timeout_sec': sshTimeoutSec,
  };

  factory SshDefaults.fromJson(Map<String, dynamic> json) {
    const d = SshDefaults.defaults;
    return SshDefaults(
      keepAliveSec: json['keepalive_sec'] as int? ?? d.keepAliveSec,
      defaultPort: json['default_port'] as int? ?? d.defaultPort,
      sshTimeoutSec: json['ssh_timeout_sec'] as int? ?? d.sshTimeoutSec,
    ).sanitized();
  }
}

/// UI and window settings.
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

  String? validate() {
    if (toastDurationMs < 500) return 'Toast duration must be at least 500ms';
    if (windowWidth < 200) return 'Window width must be at least 200';
    if (windowHeight < 200) return 'Window height must be at least 200';
    if (uiScale < 0.5 || uiScale > 2.0) return 'UI scale must be 0.5-2.0';
    return null;
  }

  UiConfig sanitized() {
    const d = UiConfig.defaults;
    return UiConfig(
      toastDurationMs: toastDurationMs < 500
          ? d.toastDurationMs
          : toastDurationMs,
      windowWidth: windowWidth < 200 ? d.windowWidth : windowWidth,
      windowHeight: windowHeight < 200 ? d.windowHeight : windowHeight,
      uiScale: uiScale.clamp(0.5, 2.0),
      showFolderSizes: showFolderSizes,
    );
  }

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

  Map<String, dynamic> toJson() => {
    'toast_duration_ms': toastDurationMs,
    'window_width': windowWidth,
    'window_height': windowHeight,
    'ui_scale': uiScale,
    'show_folder_sizes': showFolderSizes,
  };

  factory UiConfig.fromJson(Map<String, dynamic> json) {
    const d = UiConfig.defaults;
    return UiConfig(
      toastDurationMs: json['toast_duration_ms'] as int? ?? d.toastDurationMs,
      windowWidth: (json['window_width'] as num?)?.toDouble() ?? d.windowWidth,
      windowHeight:
          (json['window_height'] as num?)?.toDouble() ?? d.windowHeight,
      uiScale: (json['ui_scale'] as num?)?.toDouble() ?? d.uiScale,
      showFolderSizes: json['show_folder_sizes'] as bool? ?? d.showFolderSizes,
    ).sanitized();
  }
}

/// App behavior settings: logging, update checks, skipped versions.
///
/// Auto-lock timeout is NOT here — it lives in the encrypted DB
/// (`AppConfigs.auto_lock_minutes`) so an attacker with plaintext-disk
/// access cannot weaken the security control by editing a plaintext
/// file. See [autoLockMinutesProvider] in
/// `lib/providers/auto_lock_provider.dart`.
// See [LogLevel] in utils/logger.dart — imported here so the
// config-level serialisation stays the single source of truth for
// the log-level enum encoding.
class BehaviorConfig {
  /// Minimum severity the routine file sink admits. `null` = logging
  /// off (default). Picking any [LogLevel] opens the sink and writes
  /// lines at or above that level, so picking `warn` writes W + E,
  /// picking `info` writes everything. Replaces the old
  /// `enableLogging` bool — users who had that on will land on
  /// `null` after upgrade and can re-pick a level in Settings.
  final LogLevel? logLevel;
  final bool checkUpdatesOnStart;
  final String? skippedVersion;

  const BehaviorConfig({
    this.logLevel,
    this.checkUpdatesOnStart = true,
    this.skippedVersion,
  });

  static const defaults = BehaviorConfig();

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  BehaviorConfig copyWith({
    Object? logLevel = _unset,
    bool? checkUpdatesOnStart,
    Object? skippedVersion = _unset,
  }) => BehaviorConfig(
    logLevel: identical(logLevel, _unset)
        ? this.logLevel
        : logLevel as LogLevel?,
    checkUpdatesOnStart: checkUpdatesOnStart ?? this.checkUpdatesOnStart,
    skippedVersion: identical(skippedVersion, _unset)
        ? this.skippedVersion
        : skippedVersion as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorConfig &&
          logLevel == other.logLevel &&
          checkUpdatesOnStart == other.checkUpdatesOnStart &&
          skippedVersion == other.skippedVersion;

  @override
  int get hashCode =>
      Object.hash(logLevel, checkUpdatesOnStart, skippedVersion);

  Map<String, dynamic> toJson() => {
    if (logLevel != null) 'log_level': logLevelToJson(logLevel),
    'check_updates_on_start': checkUpdatesOnStart,
    if (skippedVersion != null) 'skipped_version': skippedVersion,
  };

  factory BehaviorConfig.fromJson(Map<String, dynamic> json) {
    const d = BehaviorConfig.defaults;
    return BehaviorConfig(
      logLevel: logLevelFromJson(json['log_level'] as String?) ?? d.logLevel,
      checkUpdatesOnStart:
          json['check_updates_on_start'] as bool? ?? d.checkUpdatesOnStart,
      skippedVersion: json['skipped_version'] as String?,
    );
  }
}

/// Application configuration model.
///
/// Same fields and defaults as LetsGOssh config.
/// Grouped into sub-configs: [terminal], [ssh], [ui], [behavior].
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
  final SecurityCapabilities? securityProbeCache;

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
  });

  static const AppConfig defaults = AppConfig();

  // --- Convenience accessors (keep call sites short) ---
  double get fontSize => terminal.fontSize;
  String get theme => terminal.theme;
  int get scrollback => terminal.scrollback;
  int get keepAliveSec => ssh.keepAliveSec;
  int get defaultPort => ssh.defaultPort;
  int get sshTimeoutSec => ssh.sshTimeoutSec;
  int get toastDurationMs => ui.toastDurationMs;
  double get windowWidth => ui.windowWidth;
  double get windowHeight => ui.windowHeight;
  double get uiScale => ui.uiScale;
  bool get showFolderSizes => ui.showFolderSizes;
  LogLevel? get logLevel => behavior.logLevel;
  bool get checkUpdatesOnStart => behavior.checkUpdatesOnStart;
  String? get skippedVersion => behavior.skippedVersion;

  /// Validate config values. Returns error message or null.
  ///
  /// Stays Dart-side: the Rust counterpart
  /// `config_app_config_validate_json` runs `from_json_value` first,
  /// which `.sanitized()`s out-of-range values during parse, so the
  /// validator can't ever observe a failing case. Until the Rust
  /// validator takes raw JSON without the sanitising parse, the
  /// per-sub-struct chain below is the source of truth.
  ///
  /// No production caller exercises this path today (settings UI
  /// uses Form-level validators on individual inputs); the test
  /// suite documents the per-field contract.
  String? validate() {
    return terminal.validate() ??
        ssh.validate() ??
        ui.validate() ??
        (transferWorkers < 1 ? 'Transfer workers must be at least 1' : null) ??
        (maxHistory < 0 ? 'Max history must be non-negative' : null);
  }

  /// Return a copy with invalid values clamped to safe defaults.
  AppConfig sanitized() {
    const d = AppConfig.defaults;
    return AppConfig(
      terminal: terminal.sanitized(),
      ssh: ssh.sanitized(),
      ui: ui.sanitized(),
      behavior: behavior,
      transferWorkers: transferWorkers < 1
          ? d.transferWorkers
          : transferWorkers,
      maxHistory: maxHistory < 0 ? d.maxHistory : maxHistory,
      locale: locale != null && supportedLocales.contains(locale)
          ? locale
          : null,
      security: security,
      securityProbeCache: securityProbeCache,
    );
  }

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
          : securityProbeCache as SecurityCapabilities?,
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
          securityProbeCache == other.securityProbeCache;

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
  );

  /// JSON stays flat for backward compatibility.
  ///
  /// Routes through `lfs_core::config::AppConfig` (FRB sync) — the
  /// field-name set + default-omit grammar (locale / security_tier
  /// / log_level only when set) lives one place across the two
  /// encoders. Tests that exercise the encoder bootstrap FRB via
  /// `requireFrbLoaded()`.
  Map<String, dynamic> toJson() {
    final dartShape = <String, dynamic>{
      ...terminal.toJson(),
      ...ssh.toJson(),
      ...ui.toJson(),
      ...behavior.toJson(),
      'transfer_workers': transferWorkers,
      'max_history': maxHistory,
      if (locale != null) 'locale': locale,
      if (security != null) 'security_tier': security!.tier.wireName,
      if (security != null) 'security_modifiers': security!.modifiers.toJson(),
      if (securityProbeCache != null)
        'security_probe_cache': securityProbeCache!.toJson(),
    };
    final canonical = rust_config.configAppConfigToJson(
      inputJson: jsonEncode(dartShape),
    );
    return jsonDecode(canonical) as Map<String, dynamic>;
  }

  /// Portable JSON for `.lfs` archive export. Strips every field that
  /// describes the LOCAL machine's security setup — `security_tier`,
  /// `security_modifiers`, `config_schema_version` — so importing the
  /// archive on a different machine does not try to adopt the
  /// exporter's tier / modifier shape. The security configuration is
  /// strictly per-install and is re-established through the wizard
  /// on each new device.
  ///
  /// Routes through `lfs_core::config::strip_for_export` (FRB sync)
  /// — the strip-list lives one place.
  Map<String, dynamic> toJsonForExport() {
    final stripped = rust_config.configAppConfigStripForExport(
      inputJson: jsonEncode(toJson()),
    );
    return jsonDecode(stripped) as Map<String, dynamic>;
  }

  /// Parse `config.json` JSON into a typed `AppConfig`.
  ///
  /// Pure Dart on purpose — `_mainBody` loads `config.json` BEFORE
  /// `RustLib.init` so the first frame paints with the user's real
  /// theme / locale / `ui_scale` from the first frame instead of
  /// flashing through `AppConfig.defaults` while the native blob
  /// loads. Routing through `lfs_core::config::AppConfig::
  /// from_json_value` would crash in that window with "RustLib not
  /// initialised". The per-sub-config `fromJson` factories
  /// (`TerminalConfig.fromJson`, `SshDefaults.fromJson`,
  /// `UiConfig.fromJson`, `BehaviorConfig.fromJson`) each call
  /// their own `.sanitized()` step (clamp out-of-range values,
  /// fall through unknown enum names to defaults), and the outer
  /// `.sanitized()` at the bottom of this factory re-runs the
  /// same Dart-side clamp pipeline. The Rust path used to handle
  /// values that bypass Dart's typed casts (e.g. a `"theme": 123`
  /// hand-edit), but every sub-config's `as String? ?? d.theme`
  /// pattern catches that already — the only marginal difference
  /// was canonical field ordering on save, which `_saveAppConfigToDisk`
  /// achieves through the Rust `configStoreSetJson` actor anyway.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    const d = AppConfig.defaults;
    return AppConfig(
      terminal: TerminalConfig.fromJson(json),
      ssh: SshDefaults.fromJson(json),
      ui: UiConfig.fromJson(json),
      behavior: BehaviorConfig.fromJson(json),
      transferWorkers: json['transfer_workers'] as int? ?? d.transferWorkers,
      maxHistory: json['max_history'] as int? ?? d.maxHistory,
      locale: json['locale'] as String?,
      security: _readSecurityConfig(json),
      securityProbeCache: SecurityCapabilities.fromJson(
        json['security_probe_cache'] as Map<String, dynamic>?,
      ),
    ).sanitized();
  }
}

SecurityConfig? _readSecurityConfig(Map<String, dynamic> json) {
  // Absence of the `security_tier` field means the user has not yet
  // completed the first-launch wizard. Returning `null` is the signal
  // `_initSecurity` keys off to fire the wizard. An *unknown* tier
  // string (e.g. a value from a newer version) is treated as "no
  // config" for the same reason — the user will re-run the wizard
  // rather than land in a silently-wrong tier.
  final tierStr = json['security_tier'];
  if (tierStr is! String) return null;
  final tier = _tierFromName(tierStr);
  if (tier == null) return null;
  final modifiersJson = json['security_modifiers'];
  final modifiers = modifiersJson is Map<String, dynamic>
      ? SecurityTierModifiers.fromJson(modifiersJson)
      : SecurityTierModifiers.defaults;
  return SecurityConfig(tier: tier, modifiers: modifiers);
}

SecurityTier? _tierFromName(String s) {
  switch (s) {
    case 'plaintext':
      return SecurityTier.plaintext;
    case 'keychain':
      return SecurityTier.keychain;
    case 'keychain_with_password':
      return SecurityTier.keychainWithPassword;
    case 'hardware':
      return SecurityTier.hardware;
    case 'paranoid':
      return SecurityTier.paranoid;
    default:
      return null;
  }
}
