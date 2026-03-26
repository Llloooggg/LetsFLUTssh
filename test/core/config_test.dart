import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('defaults are correct', () {
      const config = AppConfig.defaults;
      expect(config.fontSize, 14.0);
      expect(config.theme, 'dark');
      expect(config.scrollback, 5000);
      expect(config.keepAliveSec, 30);
      expect(config.defaultPort, 22);
      expect(config.sshTimeoutSec, 10);
      expect(config.transferWorkers, 2);
    });

    test('copyWith works', () {
      const config = AppConfig.defaults;
      final updated = config.copyWith(
        terminal: config.terminal.copyWith(fontSize: 18.0, theme: 'light'),
      );
      expect(updated.fontSize, 18.0);
      expect(updated.theme, 'light');
      expect(updated.scrollback, 5000); // unchanged
    });

    test('JSON roundtrip', () {
      const config = AppConfig(
        terminal: TerminalConfig(fontSize: 16.0, theme: 'light', scrollback: 10000),
      );
      final json = config.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.fontSize, 16.0);
      expect(restored.theme, 'light');
      expect(restored.scrollback, 10000);
      expect(restored.keepAliveSec, 30); // default
    });

    test('fromJson handles missing fields', () {
      final config = AppConfig.fromJson({});
      expect(config.fontSize, 14.0);
      expect(config.theme, 'dark');
    });

    test('fromJson sanitizes invalid values', () {
      final config = AppConfig.fromJson({
        'font_size': 0.5,
        'theme': 'invalid',
        'scrollback': -10,
        'transfer_workers': 0,
        'default_port': 99999,
        'ssh_timeout_sec': 0,
      });
      // Should be clamped/replaced to safe defaults
      expect(config.fontSize, 6.0); // clamped to min
      expect(config.theme, 'dark'); // replaced with default
      expect(config.scrollback, 5000); // replaced with default
      expect(config.transferWorkers, 2); // replaced with default
      expect(config.defaultPort, 22); // replaced with default
      expect(config.sshTimeoutSec, 10); // replaced with default
    });
  });

  group('AppConfig.validate', () {
    test('returns null for valid defaults', () {
      expect(AppConfig.defaults.validate(), isNull);
    });

    test('returns error for fontSize < 6', () {
      const config = AppConfig(terminal: TerminalConfig(fontSize: 3));
      expect(config.validate(), contains('Font size'));
    });

    test('returns error for fontSize > 72', () {
      const config = AppConfig(terminal: TerminalConfig(fontSize: 100));
      expect(config.validate(), contains('Font size'));
    });

    test('returns error for invalid theme', () {
      const config = AppConfig(terminal: TerminalConfig(theme: 'neon'));
      expect(config.validate(), contains('Theme'));
    });

    test('accepts valid themes', () {
      for (final t in ['dark', 'light', 'system']) {
        expect(AppConfig(terminal: TerminalConfig(theme: t)).validate(), isNull);
      }
    });

    test('returns error for scrollback < 100', () {
      const config = AppConfig(terminal: TerminalConfig(scrollback: 50));
      expect(config.validate(), contains('Scrollback'));
    });

    test('returns error for negative keepAlive', () {
      const config = AppConfig(ssh: SshDefaults(keepAliveSec: -1));
      expect(config.validate(), contains('Keep-alive'));
    });

    test('accepts keepAlive = 0 (disabled)', () {
      const config = AppConfig(ssh: SshDefaults(keepAliveSec: 0));
      expect(config.validate(), isNull);
    });

    test('returns error for port out of range', () {
      expect(const AppConfig(ssh: SshDefaults(defaultPort: 0)).validate(), contains('Port'));
      expect(const AppConfig(ssh: SshDefaults(defaultPort: 70000)).validate(), contains('Port'));
    });

    test('returns error for timeout < 1', () {
      expect(const AppConfig(ssh: SshDefaults(sshTimeoutSec: 0)).validate(), contains('timeout'));
    });

    test('returns error for transferWorkers < 1', () {
      expect(const AppConfig(transferWorkers: 0).validate(), contains('workers'));
    });

    test('returns error for negative maxHistory', () {
      expect(const AppConfig(maxHistory: -1).validate(), contains('history'));
    });

    test('returns error for small window dimensions', () {
      expect(const AppConfig(ui: UiConfig(windowWidth: 50)).validate(), contains('width'));
      expect(const AppConfig(ui: UiConfig(windowHeight: 50)).validate(), contains('height'));
    });
  });

  group('AppConfig.sanitized', () {
    test('clamps fontSize to range', () {
      expect(const AppConfig(terminal: TerminalConfig(fontSize: 2)).sanitized().fontSize, 6);
      expect(const AppConfig(terminal: TerminalConfig(fontSize: 100)).sanitized().fontSize, 72);
      expect(const AppConfig(terminal: TerminalConfig(fontSize: 14)).sanitized().fontSize, 14);
    });

    test('replaces invalid theme with default', () {
      expect(const AppConfig(terminal: TerminalConfig(theme: 'neon')).sanitized().theme, 'dark');
    });

    test('replaces invalid transferWorkers with default', () {
      expect(const AppConfig(transferWorkers: 0).sanitized().transferWorkers, 2);
    });

    test('valid config unchanged', () {
      const config = AppConfig.defaults;
      final sanitized = config.sanitized();
      expect(sanitized, equals(config));
    });
  });

  group('UiConfig.copyWith', () {
    test('copies with partial fields', () {
      const ui = UiConfig(toastDurationMs: 3000, windowWidth: 1000.0, windowHeight: 700.0);
      final copy = ui.copyWith(toastDurationMs: 5000);
      expect(copy.toastDurationMs, 5000);
      expect(copy.windowWidth, 1000.0);
      expect(copy.windowHeight, 700.0);
    });

    test('copies all fields', () {
      const ui = UiConfig.defaults;
      final copy = ui.copyWith(toastDurationMs: 1000, windowWidth: 800.0, windowHeight: 500.0);
      expect(copy.toastDurationMs, 1000);
      expect(copy.windowWidth, 800.0);
      expect(copy.windowHeight, 500.0);
    });

    test('no args returns equal copy', () {
      const ui = UiConfig(toastDurationMs: 2000, windowWidth: 900.0, windowHeight: 600.0);
      final copy = ui.copyWith();
      expect(copy, equals(ui));
    });
  });

  group('UiConfig.sanitized edge cases', () {
    test('clamps toastDurationMs below 500', () {
      const ui = UiConfig(toastDurationMs: 100);
      final s = ui.sanitized();
      expect(s.toastDurationMs, UiConfig.defaults.toastDurationMs);
    });

    test('clamps windowWidth below 200', () {
      const ui = UiConfig(windowWidth: 50.0);
      final s = ui.sanitized();
      expect(s.windowWidth, UiConfig.defaults.windowWidth);
    });

    test('clamps windowHeight below 200', () {
      const ui = UiConfig(windowHeight: 100.0);
      final s = ui.sanitized();
      expect(s.windowHeight, UiConfig.defaults.windowHeight);
    });
  });

  group('AppConfig UI convenience accessors', () {
    test('toastDurationMs delegates to ui', () {
      const config = AppConfig(ui: UiConfig(toastDurationMs: 5000));
      expect(config.toastDurationMs, 5000);
    });

    test('windowWidth delegates to ui', () {
      const config = AppConfig(ui: UiConfig(windowWidth: 1200.0));
      expect(config.windowWidth, 1200.0);
    });

    test('windowHeight delegates to ui', () {
      const config = AppConfig(ui: UiConfig(windowHeight: 900.0));
      expect(config.windowHeight, 900.0);
    });
  });

  group('AppConfig equality', () {
    test('equal configs are equal', () {
      const a = AppConfig(terminal: TerminalConfig(fontSize: 16, theme: 'light'));
      const b = AppConfig(terminal: TerminalConfig(fontSize: 16, theme: 'light'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different configs are not equal', () {
      const a = AppConfig(terminal: TerminalConfig(fontSize: 14));
      const b = AppConfig(terminal: TerminalConfig(fontSize: 18));
      expect(a, isNot(equals(b)));
    });

    test('defaults equal defaults', () {
      expect(AppConfig.defaults, equals(const AppConfig()));
    });

    test('identical returns true', () {
      const a = AppConfig.defaults;
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      expect(AppConfig.defaults == Object(), isFalse);
    });
  });
}
