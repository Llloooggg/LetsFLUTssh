import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';

void main() {
  // ===== TerminalConfig =====
  group('TerminalConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = TerminalConfig();
        expect(config.fontSize, 14.0);
        expect(config.theme, 'dark');
        expect(config.scrollback, 5000);
      });

      test('static defaults matches default constructor', () {
        expect(TerminalConfig.defaults, const TerminalConfig());
      });
    });

    group('validate()', () {
      test('returns null for valid config', () {
        expect(const TerminalConfig().validate(), isNull);
      });

      test('returns null for boundary values', () {
        expect(
          const TerminalConfig(fontSize: 6).validate(),
          isNull,
        );
        expect(
          const TerminalConfig(fontSize: 72).validate(),
          isNull,
        );
        expect(
          const TerminalConfig(scrollback: 100).validate(),
          isNull,
        );
        expect(
          const TerminalConfig(theme: 'light').validate(),
          isNull,
        );
        expect(
          const TerminalConfig(theme: 'system').validate(),
          isNull,
        );
      });

      test('rejects fontSize below 6', () {
        const config = TerminalConfig(fontSize: 5.9);
        expect(config.validate(), contains('Font size'));
      });

      test('rejects fontSize above 72', () {
        const config = TerminalConfig(fontSize: 72.1);
        expect(config.validate(), contains('Font size'));
      });

      test('rejects invalid theme', () {
        const config = TerminalConfig(theme: 'neon');
        expect(config.validate(), contains('Theme'));
      });

      test('rejects scrollback below 100', () {
        const config = TerminalConfig(scrollback: 99);
        expect(config.validate(), contains('Scrollback'));
      });
    });

    group('sanitized()', () {
      test('clamps fontSize below 6 to 6', () {
        const config = TerminalConfig(fontSize: 2);
        expect(config.sanitized().fontSize, 6);
      });

      test('clamps fontSize above 72 to 72', () {
        const config = TerminalConfig(fontSize: 100);
        expect(config.sanitized().fontSize, 72);
      });

      test('replaces invalid theme with default', () {
        const config = TerminalConfig(theme: 'invalid');
        expect(config.sanitized().theme, TerminalConfig.defaults.theme);
      });

      test('replaces scrollback below 100 with default', () {
        const config = TerminalConfig(scrollback: 50);
        expect(config.sanitized().scrollback, TerminalConfig.defaults.scrollback);
      });

      test('preserves valid values', () {
        const config = TerminalConfig(
          fontSize: 20,
          theme: 'light',
          scrollback: 200,
        );
        final sanitized = config.sanitized();
        expect(sanitized.fontSize, 20);
        expect(sanitized.theme, 'light');
        expect(sanitized.scrollback, 200);
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = TerminalConfig();
        final copy = config.copyWith(fontSize: 18);
        expect(copy.fontSize, 18);
        expect(copy.theme, config.theme);
        expect(copy.scrollback, config.scrollback);
      });

      test('replaces all fields', () {
        const config = TerminalConfig();
        final copy = config.copyWith(
          fontSize: 20,
          theme: 'light',
          scrollback: 300,
        );
        expect(copy.fontSize, 20);
        expect(copy.theme, 'light');
        expect(copy.scrollback, 300);
      });

      test('returns equal object when no arguments given', () {
        const config = TerminalConfig(fontSize: 16, theme: 'light', scrollback: 1000);
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal configs are equal', () {
        const a = TerminalConfig(fontSize: 16, theme: 'light', scrollback: 1000);
        const b = TerminalConfig(fontSize: 16, theme: 'light', scrollback: 1000);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different fontSize makes unequal', () {
        const a = TerminalConfig(fontSize: 14);
        const b = TerminalConfig(fontSize: 16);
        expect(a, isNot(equals(b)));
      });

      test('different theme makes unequal', () {
        const a = TerminalConfig(theme: 'dark');
        const b = TerminalConfig(theme: 'light');
        expect(a, isNot(equals(b)));
      });

      test('different scrollback makes unequal', () {
        const a = TerminalConfig(scrollback: 5000);
        const b = TerminalConfig(scrollback: 10000);
        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same instance', () {
        const config = TerminalConfig();
        expect(config == config, isTrue);
      });

      test('not equal to different type', () {
        const config = TerminalConfig();
        expect(config == Object(), isFalse);
      });
    });

    group('toJson() / fromJson()', () {
      test('roundtrip preserves values', () {
        const config = TerminalConfig(fontSize: 18, theme: 'system', scrollback: 2000);
        final json = config.toJson();
        final restored = TerminalConfig.fromJson(json);
        expect(restored, config);
      });

      test('toJson() produces expected keys', () {
        final json = const TerminalConfig().toJson();
        expect(json, containsPair('font_size', 14.0));
        expect(json, containsPair('theme', 'dark'));
        expect(json, containsPair('scrollback', 5000));
      });

      test('fromJson() with empty map falls back to defaults', () {
        final config = TerminalConfig.fromJson({});
        expect(config, TerminalConfig.defaults);
      });

      test('fromJson() with missing fields uses defaults for those fields', () {
        final config = TerminalConfig.fromJson({'font_size': 20.0});
        expect(config.fontSize, 20.0);
        expect(config.theme, TerminalConfig.defaults.theme);
        expect(config.scrollback, TerminalConfig.defaults.scrollback);
      });

      test('fromJson() sanitizes invalid values', () {
        final config = TerminalConfig.fromJson({
          'font_size': 2.0,
          'theme': 'invalid',
          'scrollback': 10,
        });
        expect(config.fontSize, 6.0);
        expect(config.theme, TerminalConfig.defaults.theme);
        expect(config.scrollback, TerminalConfig.defaults.scrollback);
      });

      test('fromJson() handles num font_size (int passed as num)', () {
        final config = TerminalConfig.fromJson({'font_size': 16});
        expect(config.fontSize, 16.0);
      });
    });
  });

  // ===== SshDefaults =====
  group('SshDefaults', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = SshDefaults();
        expect(config.keepAliveSec, 30);
        expect(config.defaultPort, 22);
        expect(config.sshTimeoutSec, 10);
      });

      test('static defaults matches default constructor', () {
        expect(SshDefaults.defaults, const SshDefaults());
      });
    });

    group('validate()', () {
      test('returns null for valid config', () {
        expect(const SshDefaults().validate(), isNull);
      });

      test('returns null for boundary values', () {
        expect(const SshDefaults(keepAliveSec: 0).validate(), isNull);
        expect(const SshDefaults(defaultPort: 1).validate(), isNull);
        expect(const SshDefaults(defaultPort: 65535).validate(), isNull);
        expect(const SshDefaults(sshTimeoutSec: 1).validate(), isNull);
      });

      test('rejects negative keepAliveSec', () {
        const config = SshDefaults(keepAliveSec: -1);
        expect(config.validate(), contains('Keep-alive'));
      });

      test('rejects port below 1', () {
        const config = SshDefaults(defaultPort: 0);
        expect(config.validate(), contains('Port'));
      });

      test('rejects port above 65535', () {
        const config = SshDefaults(defaultPort: 65536);
        expect(config.validate(), contains('Port'));
      });

      test('rejects sshTimeoutSec below 1', () {
        const config = SshDefaults(sshTimeoutSec: 0);
        expect(config.validate(), contains('SSH timeout'));
      });
    });

    group('sanitized()', () {
      test('replaces negative keepAliveSec with default', () {
        const config = SshDefaults(keepAliveSec: -5);
        expect(config.sanitized().keepAliveSec, SshDefaults.defaults.keepAliveSec);
      });

      test('replaces port 0 with default', () {
        const config = SshDefaults(defaultPort: 0);
        expect(config.sanitized().defaultPort, SshDefaults.defaults.defaultPort);
      });

      test('replaces port above 65535 with default', () {
        const config = SshDefaults(defaultPort: 70000);
        expect(config.sanitized().defaultPort, SshDefaults.defaults.defaultPort);
      });

      test('replaces sshTimeoutSec 0 with default', () {
        const config = SshDefaults(sshTimeoutSec: 0);
        expect(config.sanitized().sshTimeoutSec, SshDefaults.defaults.sshTimeoutSec);
      });

      test('preserves valid values', () {
        const config = SshDefaults(
          keepAliveSec: 60,
          defaultPort: 2222,
          sshTimeoutSec: 30,
        );
        final sanitized = config.sanitized();
        expect(sanitized.keepAliveSec, 60);
        expect(sanitized.defaultPort, 2222);
        expect(sanitized.sshTimeoutSec, 30);
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = SshDefaults();
        final copy = config.copyWith(defaultPort: 2222);
        expect(copy.defaultPort, 2222);
        expect(copy.keepAliveSec, config.keepAliveSec);
        expect(copy.sshTimeoutSec, config.sshTimeoutSec);
      });

      test('replaces all fields', () {
        final copy = const SshDefaults().copyWith(
          keepAliveSec: 60,
          defaultPort: 8022,
          sshTimeoutSec: 5,
        );
        expect(copy.keepAliveSec, 60);
        expect(copy.defaultPort, 8022);
        expect(copy.sshTimeoutSec, 5);
      });

      test('returns equal object when no arguments given', () {
        const config = SshDefaults(keepAliveSec: 45, defaultPort: 443, sshTimeoutSec: 20);
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal configs are equal', () {
        const a = SshDefaults(keepAliveSec: 10, defaultPort: 22, sshTimeoutSec: 5);
        const b = SshDefaults(keepAliveSec: 10, defaultPort: 22, sshTimeoutSec: 5);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different keepAliveSec makes unequal', () {
        const a = SshDefaults(keepAliveSec: 10);
        const b = SshDefaults(keepAliveSec: 20);
        expect(a, isNot(equals(b)));
      });

      test('different defaultPort makes unequal', () {
        const a = SshDefaults(defaultPort: 22);
        const b = SshDefaults(defaultPort: 2222);
        expect(a, isNot(equals(b)));
      });

      test('different sshTimeoutSec makes unequal', () {
        const a = SshDefaults(sshTimeoutSec: 10);
        const b = SshDefaults(sshTimeoutSec: 30);
        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same instance', () {
        const config = SshDefaults();
        expect(config == config, isTrue);
      });

      test('not equal to different type', () {
        const config = SshDefaults();
        expect(config == Object(), isFalse);
      });
    });

    group('toJson() / fromJson()', () {
      test('roundtrip preserves values', () {
        const config = SshDefaults(keepAliveSec: 60, defaultPort: 2222, sshTimeoutSec: 15);
        final json = config.toJson();
        final restored = SshDefaults.fromJson(json);
        expect(restored, config);
      });

      test('toJson() produces expected keys', () {
        final json = const SshDefaults().toJson();
        expect(json, containsPair('keepalive_sec', 30));
        expect(json, containsPair('default_port', 22));
        expect(json, containsPair('ssh_timeout_sec', 10));
      });

      test('fromJson() with empty map falls back to defaults', () {
        final config = SshDefaults.fromJson({});
        expect(config, SshDefaults.defaults);
      });

      test('fromJson() with missing fields uses defaults for those fields', () {
        final config = SshDefaults.fromJson({'default_port': 8022});
        expect(config.defaultPort, 8022);
        expect(config.keepAliveSec, SshDefaults.defaults.keepAliveSec);
        expect(config.sshTimeoutSec, SshDefaults.defaults.sshTimeoutSec);
      });

      test('fromJson() sanitizes invalid values', () {
        final config = SshDefaults.fromJson({
          'keepalive_sec': -1,
          'default_port': 0,
          'ssh_timeout_sec': 0,
        });
        expect(config.keepAliveSec, SshDefaults.defaults.keepAliveSec);
        expect(config.defaultPort, SshDefaults.defaults.defaultPort);
        expect(config.sshTimeoutSec, SshDefaults.defaults.sshTimeoutSec);
      });
    });
  });

  // ===== UiConfig =====
  group('UiConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = UiConfig();
        expect(config.toastDurationMs, 4000);
        expect(config.windowWidth, 1100);
        expect(config.windowHeight, 650);
      });

      test('static defaults matches default constructor', () {
        expect(UiConfig.defaults, const UiConfig());
      });
    });

    group('validate()', () {
      test('returns null for valid config', () {
        expect(const UiConfig().validate(), isNull);
      });

      test('returns null for boundary values', () {
        expect(const UiConfig(toastDurationMs: 500).validate(), isNull);
        expect(const UiConfig(windowWidth: 200).validate(), isNull);
        expect(const UiConfig(windowHeight: 200).validate(), isNull);
      });

      test('rejects toastDurationMs below 500', () {
        const config = UiConfig(toastDurationMs: 499);
        expect(config.validate(), contains('Toast duration'));
      });

      test('rejects windowWidth below 200', () {
        const config = UiConfig(windowWidth: 199);
        expect(config.validate(), contains('Window width'));
      });

      test('rejects windowHeight below 200', () {
        const config = UiConfig(windowHeight: 199);
        expect(config.validate(), contains('Window height'));
      });
    });

    group('sanitized()', () {
      test('replaces toastDurationMs below 500 with default', () {
        const config = UiConfig(toastDurationMs: 100);
        expect(config.sanitized().toastDurationMs, UiConfig.defaults.toastDurationMs);
      });

      test('replaces windowWidth below 200 with default', () {
        const config = UiConfig(windowWidth: 50);
        expect(config.sanitized().windowWidth, UiConfig.defaults.windowWidth);
      });

      test('replaces windowHeight below 200 with default', () {
        const config = UiConfig(windowHeight: 50);
        expect(config.sanitized().windowHeight, UiConfig.defaults.windowHeight);
      });

      test('preserves valid values', () {
        const config = UiConfig(
          toastDurationMs: 3000,
          windowWidth: 800,
          windowHeight: 600,
        );
        final sanitized = config.sanitized();
        expect(sanitized.toastDurationMs, 3000);
        expect(sanitized.windowWidth, 800);
        expect(sanitized.windowHeight, 600);
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = UiConfig();
        final copy = config.copyWith(windowWidth: 1920);
        expect(copy.windowWidth, 1920);
        expect(copy.toastDurationMs, config.toastDurationMs);
        expect(copy.windowHeight, config.windowHeight);
      });

      test('replaces all fields', () {
        final copy = const UiConfig().copyWith(
          toastDurationMs: 2000,
          windowWidth: 1920,
          windowHeight: 1080,
        );
        expect(copy.toastDurationMs, 2000);
        expect(copy.windowWidth, 1920);
        expect(copy.windowHeight, 1080);
      });

      test('returns equal object when no arguments given', () {
        const config = UiConfig(toastDurationMs: 5000, windowWidth: 800, windowHeight: 600);
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal configs are equal', () {
        const a = UiConfig(toastDurationMs: 3000, windowWidth: 800, windowHeight: 600);
        const b = UiConfig(toastDurationMs: 3000, windowWidth: 800, windowHeight: 600);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different toastDurationMs makes unequal', () {
        const a = UiConfig(toastDurationMs: 3000);
        const b = UiConfig(toastDurationMs: 5000);
        expect(a, isNot(equals(b)));
      });

      test('different windowWidth makes unequal', () {
        const a = UiConfig(windowWidth: 800);
        const b = UiConfig(windowWidth: 1200);
        expect(a, isNot(equals(b)));
      });

      test('different windowHeight makes unequal', () {
        const a = UiConfig(windowHeight: 600);
        const b = UiConfig(windowHeight: 900);
        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same instance', () {
        const config = UiConfig();
        expect(config == config, isTrue);
      });

      test('not equal to different type', () {
        const config = UiConfig();
        expect(config == Object(), isFalse);
      });
    });

    group('toJson() / fromJson()', () {
      test('roundtrip preserves values', () {
        const config = UiConfig(toastDurationMs: 2000, windowWidth: 1920, windowHeight: 1080);
        final json = config.toJson();
        final restored = UiConfig.fromJson(json);
        expect(restored, config);
      });

      test('toJson() produces expected keys', () {
        final json = const UiConfig().toJson();
        expect(json, containsPair('toast_duration_ms', 4000));
        expect(json, containsPair('window_width', 1100.0));
        expect(json, containsPair('window_height', 650.0));
      });

      test('fromJson() with empty map falls back to defaults', () {
        final config = UiConfig.fromJson({});
        expect(config, UiConfig.defaults);
      });

      test('fromJson() with missing fields uses defaults for those fields', () {
        final config = UiConfig.fromJson({'window_width': 1920.0});
        expect(config.windowWidth, 1920.0);
        expect(config.toastDurationMs, UiConfig.defaults.toastDurationMs);
        expect(config.windowHeight, UiConfig.defaults.windowHeight);
      });

      test('fromJson() sanitizes invalid values', () {
        final config = UiConfig.fromJson({
          'toast_duration_ms': 100,
          'window_width': 50.0,
          'window_height': 50.0,
        });
        expect(config.toastDurationMs, UiConfig.defaults.toastDurationMs);
        expect(config.windowWidth, UiConfig.defaults.windowWidth);
        expect(config.windowHeight, UiConfig.defaults.windowHeight);
      });

      test('fromJson() handles num window dimensions (int passed as num)', () {
        final config = UiConfig.fromJson({
          'window_width': 800,
          'window_height': 600,
        });
        expect(config.windowWidth, 800.0);
        expect(config.windowHeight, 600.0);
      });
    });
  });

  // ===== AppConfig =====
  group('AppConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = AppConfig();
        expect(config.terminal, const TerminalConfig());
        expect(config.ssh, const SshDefaults());
        expect(config.ui, const UiConfig());
        expect(config.transferWorkers, 2);
        expect(config.maxHistory, 500);
        expect(config.enableLogging, false);
      });

      test('static defaults matches default constructor', () {
        expect(AppConfig.defaults, const AppConfig());
      });
    });

    group('convenience accessors', () {
      test('fontSize delegates to terminal', () {
        const config = AppConfig(terminal: TerminalConfig(fontSize: 20));
        expect(config.fontSize, 20);
      });

      test('theme delegates to terminal', () {
        const config = AppConfig(terminal: TerminalConfig(theme: 'light'));
        expect(config.theme, 'light');
      });

      test('scrollback delegates to terminal', () {
        const config = AppConfig(terminal: TerminalConfig(scrollback: 3000));
        expect(config.scrollback, 3000);
      });

      test('keepAliveSec delegates to ssh', () {
        const config = AppConfig(ssh: SshDefaults(keepAliveSec: 60));
        expect(config.keepAliveSec, 60);
      });

      test('defaultPort delegates to ssh', () {
        const config = AppConfig(ssh: SshDefaults(defaultPort: 2222));
        expect(config.defaultPort, 2222);
      });

      test('sshTimeoutSec delegates to ssh', () {
        const config = AppConfig(ssh: SshDefaults(sshTimeoutSec: 20));
        expect(config.sshTimeoutSec, 20);
      });

      test('toastDurationMs delegates to ui', () {
        const config = AppConfig(ui: UiConfig(toastDurationMs: 2000));
        expect(config.toastDurationMs, 2000);
      });

      test('windowWidth delegates to ui', () {
        const config = AppConfig(ui: UiConfig(windowWidth: 1920));
        expect(config.windowWidth, 1920);
      });

      test('windowHeight delegates to ui', () {
        const config = AppConfig(ui: UiConfig(windowHeight: 1080));
        expect(config.windowHeight, 1080);
      });
    });

    group('validate()', () {
      test('returns null for valid config', () {
        expect(const AppConfig().validate(), isNull);
      });

      test('propagates terminal validation error', () {
        const config = AppConfig(terminal: TerminalConfig(fontSize: 2));
        expect(config.validate(), contains('Font size'));
      });

      test('propagates ssh validation error', () {
        const config = AppConfig(ssh: SshDefaults(defaultPort: 0));
        expect(config.validate(), contains('Port'));
      });

      test('propagates ui validation error', () {
        const config = AppConfig(ui: UiConfig(windowWidth: 50));
        expect(config.validate(), contains('Window width'));
      });

      test('rejects transferWorkers below 1', () {
        const config = AppConfig(transferWorkers: 0);
        expect(config.validate(), contains('Transfer workers'));
      });

      test('rejects negative maxHistory', () {
        const config = AppConfig(maxHistory: -1);
        expect(config.validate(), contains('Max history'));
      });

      test('returns first error found (terminal before ssh)', () {
        const config = AppConfig(
          terminal: TerminalConfig(fontSize: 2),
          ssh: SshDefaults(defaultPort: 0),
        );
        expect(config.validate(), contains('Font size'));
      });

      test('accepts boundary values', () {
        const config = AppConfig(
          transferWorkers: 1,
          maxHistory: 0,
        );
        expect(config.validate(), isNull);
      });
    });

    group('sanitized()', () {
      test('sanitizes sub-configs', () {
        const config = AppConfig(
          terminal: TerminalConfig(fontSize: 2),
          ssh: SshDefaults(defaultPort: 0),
          ui: UiConfig(windowWidth: 50),
        );
        final sanitized = config.sanitized();
        expect(sanitized.terminal.fontSize, 6);
        expect(sanitized.ssh.defaultPort, SshDefaults.defaults.defaultPort);
        expect(sanitized.ui.windowWidth, UiConfig.defaults.windowWidth);
      });

      test('replaces transferWorkers below 1 with default', () {
        const config = AppConfig(transferWorkers: 0);
        expect(config.sanitized().transferWorkers, AppConfig.defaults.transferWorkers);
      });

      test('replaces negative maxHistory with default', () {
        const config = AppConfig(maxHistory: -1);
        expect(config.sanitized().maxHistory, AppConfig.defaults.maxHistory);
      });

      test('preserves enableLogging', () {
        const config = AppConfig(enableLogging: true);
        expect(config.sanitized().enableLogging, true);
      });

      test('preserves valid values', () {
        const config = AppConfig(
          transferWorkers: 4,
          maxHistory: 1000,
          enableLogging: true,
        );
        final sanitized = config.sanitized();
        expect(sanitized.transferWorkers, 4);
        expect(sanitized.maxHistory, 1000);
        expect(sanitized.enableLogging, true);
      });
    });

    group('copyWith()', () {
      test('replaces terminal', () {
        const config = AppConfig();
        final copy = config.copyWith(
          terminal: const TerminalConfig(fontSize: 20),
        );
        expect(copy.terminal.fontSize, 20);
        expect(copy.ssh, config.ssh);
        expect(copy.ui, config.ui);
        expect(copy.transferWorkers, config.transferWorkers);
      });

      test('replaces ssh', () {
        const config = AppConfig();
        final copy = config.copyWith(
          ssh: const SshDefaults(defaultPort: 2222),
        );
        expect(copy.ssh.defaultPort, 2222);
        expect(copy.terminal, config.terminal);
      });

      test('replaces ui', () {
        const config = AppConfig();
        final copy = config.copyWith(
          ui: const UiConfig(windowWidth: 1920),
        );
        expect(copy.ui.windowWidth, 1920);
      });

      test('replaces transferWorkers', () {
        const config = AppConfig();
        final copy = config.copyWith(transferWorkers: 8);
        expect(copy.transferWorkers, 8);
      });

      test('replaces maxHistory', () {
        const config = AppConfig();
        final copy = config.copyWith(maxHistory: 100);
        expect(copy.maxHistory, 100);
      });

      test('replaces enableLogging', () {
        const config = AppConfig();
        final copy = config.copyWith(enableLogging: true);
        expect(copy.enableLogging, true);
      });

      test('returns equal object when no arguments given', () {
        const config = AppConfig(
          terminal: TerminalConfig(fontSize: 18),
          transferWorkers: 4,
          enableLogging: true,
        );
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal configs are equal', () {
        const a = AppConfig(transferWorkers: 4, maxHistory: 100, enableLogging: true);
        const b = AppConfig(transferWorkers: 4, maxHistory: 100, enableLogging: true);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different terminal makes unequal', () {
        const a = AppConfig(terminal: TerminalConfig(fontSize: 14));
        const b = AppConfig(terminal: TerminalConfig(fontSize: 20));
        expect(a, isNot(equals(b)));
      });

      test('different ssh makes unequal', () {
        const a = AppConfig(ssh: SshDefaults(defaultPort: 22));
        const b = AppConfig(ssh: SshDefaults(defaultPort: 2222));
        expect(a, isNot(equals(b)));
      });

      test('different ui makes unequal', () {
        const a = AppConfig(ui: UiConfig(windowWidth: 800));
        const b = AppConfig(ui: UiConfig(windowWidth: 1200));
        expect(a, isNot(equals(b)));
      });

      test('different transferWorkers makes unequal', () {
        const a = AppConfig(transferWorkers: 2);
        const b = AppConfig(transferWorkers: 4);
        expect(a, isNot(equals(b)));
      });

      test('different maxHistory makes unequal', () {
        const a = AppConfig(maxHistory: 500);
        const b = AppConfig(maxHistory: 1000);
        expect(a, isNot(equals(b)));
      });

      test('different enableLogging makes unequal', () {
        const a = AppConfig(enableLogging: false);
        const b = AppConfig(enableLogging: true);
        expect(a, isNot(equals(b)));
      });

      test('identical returns true for same instance', () {
        const config = AppConfig();
        expect(config == config, isTrue);
      });

      test('not equal to different type', () {
        const config = AppConfig();
        expect(config == Object(), isFalse);
      });
    });

    group('toJson() / fromJson()', () {
      test('roundtrip preserves all values', () {
        const config = AppConfig(
          terminal: TerminalConfig(fontSize: 18, theme: 'system', scrollback: 2000),
          ssh: SshDefaults(keepAliveSec: 60, defaultPort: 2222, sshTimeoutSec: 15),
          ui: UiConfig(toastDurationMs: 2000, windowWidth: 1920, windowHeight: 1080),
          transferWorkers: 4,
          maxHistory: 1000,
          enableLogging: true,
        );
        final json = config.toJson();
        final restored = AppConfig.fromJson(json);
        expect(restored, config);
      });

      test('toJson() produces flat JSON with all keys', () {
        final json = const AppConfig().toJson();
        // Terminal keys
        expect(json, containsPair('font_size', 14.0));
        expect(json, containsPair('theme', 'dark'));
        expect(json, containsPair('scrollback', 5000));
        // SSH keys
        expect(json, containsPair('keepalive_sec', 30));
        expect(json, containsPair('default_port', 22));
        expect(json, containsPair('ssh_timeout_sec', 10));
        // UI keys
        expect(json, containsPair('toast_duration_ms', 4000));
        expect(json, containsPair('window_width', 1100.0));
        expect(json, containsPair('window_height', 650.0));
        // AppConfig-level keys
        expect(json, containsPair('transfer_workers', 2));
        expect(json, containsPair('max_history', 500));
        expect(json, containsPair('enable_logging', false));
      });

      test('fromJson() with empty map falls back to defaults', () {
        final config = AppConfig.fromJson({});
        expect(config, AppConfig.defaults);
      });

      test('fromJson() with missing fields uses defaults for those fields', () {
        final config = AppConfig.fromJson({
          'font_size': 20.0,
          'transfer_workers': 8,
        });
        expect(config.terminal.fontSize, 20.0);
        expect(config.transferWorkers, 8);
        // Other fields should be defaults
        expect(config.terminal.theme, TerminalConfig.defaults.theme);
        expect(config.ssh, SshDefaults.defaults);
        expect(config.ui, UiConfig.defaults);
        expect(config.maxHistory, AppConfig.defaults.maxHistory);
        expect(config.enableLogging, AppConfig.defaults.enableLogging);
      });

      test('fromJson() sanitizes invalid values across all sub-configs', () {
        final config = AppConfig.fromJson({
          'font_size': 1.0,
          'theme': 'invalid',
          'scrollback': 10,
          'keepalive_sec': -1,
          'default_port': 0,
          'ssh_timeout_sec': 0,
          'toast_duration_ms': 100,
          'window_width': 50.0,
          'window_height': 50.0,
          'transfer_workers': 0,
          'max_history': -1,
        });
        expect(config.validate(), isNull);
        expect(config.terminal.fontSize, 6.0);
        expect(config.terminal.theme, TerminalConfig.defaults.theme);
        expect(config.terminal.scrollback, TerminalConfig.defaults.scrollback);
        expect(config.ssh.keepAliveSec, SshDefaults.defaults.keepAliveSec);
        expect(config.ssh.defaultPort, SshDefaults.defaults.defaultPort);
        expect(config.ssh.sshTimeoutSec, SshDefaults.defaults.sshTimeoutSec);
        expect(config.ui.toastDurationMs, UiConfig.defaults.toastDurationMs);
        expect(config.ui.windowWidth, UiConfig.defaults.windowWidth);
        expect(config.ui.windowHeight, UiConfig.defaults.windowHeight);
        expect(config.transferWorkers, AppConfig.defaults.transferWorkers);
        expect(config.maxHistory, AppConfig.defaults.maxHistory);
      });

      test('fromJson() preserves enableLogging true', () {
        final config = AppConfig.fromJson({'enable_logging': true});
        expect(config.enableLogging, true);
      });

      test('fromJson() defaults enableLogging to false', () {
        final config = AppConfig.fromJson({});
        expect(config.enableLogging, false);
      });
    });
  });
}
