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
      final updated = config.copyWith(fontSize: 18.0, theme: 'light');
      expect(updated.fontSize, 18.0);
      expect(updated.theme, 'light');
      expect(updated.scrollback, 5000); // unchanged
    });

    test('JSON roundtrip', () {
      const config = AppConfig(
        fontSize: 16.0,
        theme: 'light',
        scrollback: 10000,
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
      const config = AppConfig(fontSize: 3);
      expect(config.validate(), contains('Font size'));
    });

    test('returns error for fontSize > 72', () {
      const config = AppConfig(fontSize: 100);
      expect(config.validate(), contains('Font size'));
    });

    test('returns error for invalid theme', () {
      const config = AppConfig(theme: 'neon');
      expect(config.validate(), contains('Theme'));
    });

    test('accepts valid themes', () {
      for (final t in ['dark', 'light', 'system']) {
        expect(AppConfig(theme: t).validate(), isNull);
      }
    });

    test('returns error for scrollback < 100', () {
      const config = AppConfig(scrollback: 50);
      expect(config.validate(), contains('Scrollback'));
    });

    test('returns error for negative keepAlive', () {
      const config = AppConfig(keepAliveSec: -1);
      expect(config.validate(), contains('Keep-alive'));
    });

    test('accepts keepAlive = 0 (disabled)', () {
      const config = AppConfig(keepAliveSec: 0);
      expect(config.validate(), isNull);
    });

    test('returns error for port out of range', () {
      expect(const AppConfig(defaultPort: 0).validate(), contains('Port'));
      expect(const AppConfig(defaultPort: 70000).validate(), contains('Port'));
    });

    test('returns error for timeout < 1', () {
      expect(const AppConfig(sshTimeoutSec: 0).validate(), contains('timeout'));
    });

    test('returns error for transferWorkers < 1', () {
      expect(const AppConfig(transferWorkers: 0).validate(), contains('workers'));
    });

    test('returns error for negative maxHistory', () {
      expect(const AppConfig(maxHistory: -1).validate(), contains('history'));
    });

    test('returns error for small window dimensions', () {
      expect(const AppConfig(windowWidth: 50).validate(), contains('width'));
      expect(const AppConfig(windowHeight: 50).validate(), contains('height'));
    });
  });

  group('AppConfig.sanitized', () {
    test('clamps fontSize to range', () {
      expect(const AppConfig(fontSize: 2).sanitized().fontSize, 6);
      expect(const AppConfig(fontSize: 100).sanitized().fontSize, 72);
      expect(const AppConfig(fontSize: 14).sanitized().fontSize, 14);
    });

    test('replaces invalid theme with default', () {
      expect(const AppConfig(theme: 'neon').sanitized().theme, 'dark');
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

  group('AppConfig equality', () {
    test('equal configs are equal', () {
      const a = AppConfig(fontSize: 16, theme: 'light');
      const b = AppConfig(fontSize: 16, theme: 'light');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different configs are not equal', () {
      const a = AppConfig(fontSize: 14);
      const b = AppConfig(fontSize: 18);
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
