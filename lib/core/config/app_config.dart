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
    );
  }
}
