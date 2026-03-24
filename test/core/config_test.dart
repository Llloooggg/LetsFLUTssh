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
  });
}
