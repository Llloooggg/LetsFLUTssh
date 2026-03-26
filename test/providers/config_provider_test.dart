import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/core/config/config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late ConfigStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_prov_test_');
    store = ConfigStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ConfigNotifier', () {
    test('starts with AppConfig.defaults', () {
      final container = ProviderContainer(overrides: [
        configStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      expect(notifier.state, equals(AppConfig.defaults));
    });

    test('load() updates state from store', () async {
      await store.save(const AppConfig(fontSize: 20.0, theme: 'light'));
      final container = ProviderContainer(overrides: [
        configStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);

      await notifier.load();
      expect(notifier.state.fontSize, 20.0);
      expect(notifier.state.theme, 'light');
    });

    test('update() applies updater and persists', () async {
      final container = ProviderContainer(overrides: [
        configStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      await notifier.update((c) => c.copyWith(fontSize: 24.0));
      expect(notifier.state.fontSize, 24.0);

      // Verify persisted
      final store2 = ConfigStore();
      final loaded = await store2.load();
      expect(loaded.fontSize, 24.0);
    });

    test('update() after load preserves other fields', () async {
      await store.save(const AppConfig(fontSize: 16.0, scrollback: 8000));
      final container = ProviderContainer(overrides: [
        configStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      await notifier.update((c) => c.copyWith(theme: 'system'));
      expect(notifier.state.fontSize, 16.0);
      expect(notifier.state.scrollback, 8000);
      expect(notifier.state.theme, 'system');
    });
  });
}
