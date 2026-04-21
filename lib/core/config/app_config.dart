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

  String? validate() {
    if (fontSize < 6 || fontSize > 72) return 'Font size must be 6-72';
    if (!_validThemes.contains(theme)) {
      return 'Theme must be one of: ${_validThemes.join(', ')}';
    }
    if (scrollback < 100) return 'Scrollback must be at least 100';
    return null;
  }

  TerminalConfig sanitized() {
    const d = TerminalConfig.defaults;
    return TerminalConfig(
      fontSize: fontSize.clamp(6, 72),
      theme: _validThemes.contains(theme) ? theme : d.theme,
      scrollback: scrollback < 100 ? d.scrollback : scrollback,
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
/// file. See [AutoLockStore].
class BehaviorConfig {
  final bool enableLogging;
  final bool checkUpdatesOnStart;
  final String? skippedVersion;

  const BehaviorConfig({
    this.enableLogging = true,
    this.checkUpdatesOnStart = true,
    this.skippedVersion,
  });

  static const defaults = BehaviorConfig();

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  BehaviorConfig copyWith({
    bool? enableLogging,
    bool? checkUpdatesOnStart,
    Object? skippedVersion = _unset,
  }) => BehaviorConfig(
    enableLogging: enableLogging ?? this.enableLogging,
    checkUpdatesOnStart: checkUpdatesOnStart ?? this.checkUpdatesOnStart,
    skippedVersion: identical(skippedVersion, _unset)
        ? this.skippedVersion
        : skippedVersion as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorConfig &&
          enableLogging == other.enableLogging &&
          checkUpdatesOnStart == other.checkUpdatesOnStart &&
          skippedVersion == other.skippedVersion;

  @override
  int get hashCode =>
      Object.hash(enableLogging, checkUpdatesOnStart, skippedVersion);

  Map<String, dynamic> toJson() => {
    'enable_logging': enableLogging,
    'check_updates_on_start': checkUpdatesOnStart,
    if (skippedVersion != null) 'skipped_version': skippedVersion,
  };

  factory BehaviorConfig.fromJson(Map<String, dynamic> json) {
    const d = BehaviorConfig.defaults;
    return BehaviorConfig(
      enableLogging: json['enable_logging'] as bool? ?? d.enableLogging,
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
  bool get enableLogging => behavior.enableLogging;
  bool get checkUpdatesOnStart => behavior.checkUpdatesOnStart;
  String? get skippedVersion => behavior.skippedVersion;

  /// Validate config values. Returns error message or null.
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
    );
  }

  /// Sentinel for clearing nullable fields in [copyWith].
  static const _unset = Object();

  AppConfig copyWith({
    TerminalConfig? terminal,
    SshDefaults? ssh,
    UiConfig? ui,
    BehaviorConfig? behavior,
    int? transferWorkers,
    int? maxHistory,
    Object? locale = _unset,
    Object? security = _unset,
  }) {
    return AppConfig(
      terminal: terminal ?? this.terminal,
      ssh: ssh ?? this.ssh,
      ui: ui ?? this.ui,
      behavior: behavior ?? this.behavior,
      transferWorkers: transferWorkers ?? this.transferWorkers,
      maxHistory: maxHistory ?? this.maxHistory,
      locale: identical(locale, _unset) ? this.locale : locale as String?,
      security: identical(security, _unset)
          ? this.security
          : security as SecurityConfig?,
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
          security == other.security;

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
  );

  /// JSON stays flat for backward compatibility.
  Map<String, dynamic> toJson() => {
    ...terminal.toJson(),
    ...ssh.toJson(),
    ...ui.toJson(),
    ...behavior.toJson(),
    'transfer_workers': transferWorkers,
    'max_history': maxHistory,
    if (locale != null) 'locale': locale,
    if (security != null) 'security_tier': _tierName(security!.tier),
    if (security != null) 'security_modifiers': security!.modifiers.toJson(),
  };

  /// Portable JSON for `.lfs` archive export. Strips every field that
  /// describes the LOCAL machine's security setup — `security_tier`,
  /// `security_modifiers`, `config_schema_version` — so importing the
  /// archive on a different machine does not try to adopt the
  /// exporter's tier / modifier shape. The security configuration is
  /// strictly per-install and is re-established through the wizard
  /// on each new device.
  Map<String, dynamic> toJsonForExport() {
    final json = toJson();
    json.remove('security_tier');
    json.remove('security_modifiers');
    json.remove('config_schema_version');
    return json;
  }

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
    ).sanitized();
  }
}

String _tierName(SecurityTier tier) {
  switch (tier) {
    case SecurityTier.plaintext:
      return 'plaintext';
    case SecurityTier.keychain:
      return 'keychain';
    case SecurityTier.keychainWithPassword:
      return 'keychain_with_password';
    case SecurityTier.hardware:
      return 'hardware';
    case SecurityTier.paranoid:
      return 'paranoid';
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
