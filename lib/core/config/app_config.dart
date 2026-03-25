/// Application configuration model.
///
/// Same fields and defaults as LetsGOssh config.
class AppConfig {
  final double fontSize;
  final String theme; // 'dark', 'light', 'system'
  final int scrollback;
  final int keepAliveSec;
  final int defaultPort;
  final int sshTimeoutSec;
  final int toastDurationMs;
  final int transferWorkers;
  final int maxHistory;
  final double windowWidth;
  final double windowHeight;

  const AppConfig({
    this.fontSize = 14.0,
    this.theme = 'dark',
    this.scrollback = 5000,
    this.keepAliveSec = 30,
    this.defaultPort = 22,
    this.sshTimeoutSec = 10,
    this.toastDurationMs = 4000,
    this.transferWorkers = 2,
    this.maxHistory = 500,
    this.windowWidth = 1100,
    this.windowHeight = 650,
  });

  static const AppConfig defaults = AppConfig();

  static const _validThemes = ['dark', 'light', 'system'];

  /// Validate config values. Returns error message or null.
  String? validate() {
    if (fontSize < 6 || fontSize > 72) return 'Font size must be 6-72';
    if (!_validThemes.contains(theme)) return 'Theme must be one of: ${_validThemes.join(', ')}';
    if (scrollback < 100) return 'Scrollback must be at least 100';
    if (keepAliveSec < 0) return 'Keep-alive must be non-negative';
    if (defaultPort < 1 || defaultPort > 65535) return 'Port must be 1-65535';
    if (sshTimeoutSec < 1) return 'SSH timeout must be at least 1 second';
    if (toastDurationMs < 500) return 'Toast duration must be at least 500ms';
    if (transferWorkers < 1) return 'Transfer workers must be at least 1';
    if (maxHistory < 0) return 'Max history must be non-negative';
    if (windowWidth < 200) return 'Window width must be at least 200';
    if (windowHeight < 200) return 'Window height must be at least 200';
    return null;
  }

  /// Return a copy with invalid values clamped to safe defaults.
  AppConfig sanitized() {
    const d = AppConfig.defaults;
    return AppConfig(
      fontSize: fontSize.clamp(6, 72),
      theme: _validThemes.contains(theme) ? theme : d.theme,
      scrollback: scrollback < 100 ? d.scrollback : scrollback,
      keepAliveSec: keepAliveSec < 0 ? d.keepAliveSec : keepAliveSec,
      defaultPort: (defaultPort < 1 || defaultPort > 65535) ? d.defaultPort : defaultPort,
      sshTimeoutSec: sshTimeoutSec < 1 ? d.sshTimeoutSec : sshTimeoutSec,
      toastDurationMs: toastDurationMs < 500 ? d.toastDurationMs : toastDurationMs,
      transferWorkers: transferWorkers < 1 ? d.transferWorkers : transferWorkers,
      maxHistory: maxHistory < 0 ? d.maxHistory : maxHistory,
      windowWidth: windowWidth < 200 ? d.windowWidth : windowWidth,
      windowHeight: windowHeight < 200 ? d.windowHeight : windowHeight,
    );
  }

  AppConfig copyWith({
    double? fontSize,
    String? theme,
    int? scrollback,
    int? keepAliveSec,
    int? defaultPort,
    int? sshTimeoutSec,
    int? toastDurationMs,
    int? transferWorkers,
    int? maxHistory,
    double? windowWidth,
    double? windowHeight,
  }) {
    return AppConfig(
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      scrollback: scrollback ?? this.scrollback,
      keepAliveSec: keepAliveSec ?? this.keepAliveSec,
      defaultPort: defaultPort ?? this.defaultPort,
      sshTimeoutSec: sshTimeoutSec ?? this.sshTimeoutSec,
      toastDurationMs: toastDurationMs ?? this.toastDurationMs,
      transferWorkers: transferWorkers ?? this.transferWorkers,
      maxHistory: maxHistory ?? this.maxHistory,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          fontSize == other.fontSize &&
          theme == other.theme &&
          scrollback == other.scrollback &&
          keepAliveSec == other.keepAliveSec &&
          defaultPort == other.defaultPort &&
          sshTimeoutSec == other.sshTimeoutSec &&
          toastDurationMs == other.toastDurationMs &&
          transferWorkers == other.transferWorkers &&
          maxHistory == other.maxHistory &&
          windowWidth == other.windowWidth &&
          windowHeight == other.windowHeight;

  @override
  int get hashCode => Object.hash(
        fontSize, theme, scrollback, keepAliveSec, defaultPort,
        sshTimeoutSec, toastDurationMs, transferWorkers, maxHistory,
        windowWidth, windowHeight,
      );

  Map<String, dynamic> toJson() => {
    'font_size': fontSize,
    'theme': theme,
    'scrollback': scrollback,
    'keepalive_sec': keepAliveSec,
    'default_port': defaultPort,
    'ssh_timeout_sec': sshTimeoutSec,
    'toast_duration_ms': toastDurationMs,
    'transfer_workers': transferWorkers,
    'max_history': maxHistory,
    'window_width': windowWidth,
    'window_height': windowHeight,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    const d = AppConfig.defaults;
    return AppConfig(
      fontSize: (json['font_size'] as num?)?.toDouble() ?? d.fontSize,
      theme: json['theme'] as String? ?? d.theme,
      scrollback: json['scrollback'] as int? ?? d.scrollback,
      keepAliveSec: json['keepalive_sec'] as int? ?? d.keepAliveSec,
      defaultPort: json['default_port'] as int? ?? d.defaultPort,
      sshTimeoutSec: json['ssh_timeout_sec'] as int? ?? d.sshTimeoutSec,
      toastDurationMs:
          json['toast_duration_ms'] as int? ?? d.toastDurationMs,
      transferWorkers:
          json['transfer_workers'] as int? ?? d.transferWorkers,
      maxHistory: json['max_history'] as int? ?? d.maxHistory,
      windowWidth:
          (json['window_width'] as num?)?.toDouble() ?? d.windowWidth,
      windowHeight:
          (json['window_height'] as num?)?.toDouble() ?? d.windowHeight,
    ).sanitized();
  }
}
