import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/config/config_store.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer({AppConfig? config}) {
    final store = ConfigStore();
    final container = ProviderContainer(
      overrides: [configStoreProvider.overrideWithValue(store)],
    );
    if (config != null) {
      container.read(configProvider.notifier).state = config;
    }
    return container;
  }

  group('localeProvider', () {
    test('returns null when config locale is null (system default)', () {
      final container = createContainer();
      addTearDown(container.dispose);
      expect(container.read(localeProvider), isNull);
    });

    test('returns Locale when config locale is set', () {
      final container = createContainer(config: const AppConfig(locale: 'ru'));
      addTearDown(container.dispose);
      expect(container.read(localeProvider), const Locale('ru'));
    });

    test('returns correct Locale for each supported language', () {
      for (final code in AppConfig.supportedLocales) {
        final container = createContainer(config: AppConfig(locale: code));
        addTearDown(container.dispose);
        expect(container.read(localeProvider), Locale(code));
      }
    });

    test('updates when config locale changes', () {
      final container = createContainer();
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);

      container.read(configProvider.notifier).state = const AppConfig(
        locale: 'de',
      );
      expect(container.read(localeProvider), const Locale('de'));

      container.read(configProvider.notifier).state = const AppConfig(
        locale: null,
      );
      expect(container.read(localeProvider), isNull);
    });
  });
}
