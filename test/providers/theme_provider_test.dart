import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/theme_provider.dart';

void main() {
  group('themeModeProvider', () {
    test('returns ThemeMode.dark for "dark"', () {
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(() => _FakeConfigNotifier('dark')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('returns ThemeMode.light for "light"', () {
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(() => _FakeConfigNotifier('light')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('returns ThemeMode.system for "system"', () {
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(() => _FakeConfigNotifier('system')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('returns ThemeMode.system for unknown value', () {
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith(() => _FakeConfigNotifier('garbage')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('returns ThemeMode.system for empty string', () {
      final container = ProviderContainer(
        overrides: [configProvider.overrideWith(() => _FakeConfigNotifier(''))],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}

class _FakeConfigNotifier extends ConfigNotifier {
  final String _theme;
  _FakeConfigNotifier(this._theme);

  @override
  AppConfig build() => AppConfig.defaults.copyWith(
    terminal: AppConfig.defaults.terminal.copyWith(theme: _theme),
  );
}
