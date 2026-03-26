import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/config/config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late ConfigStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_store_test_');
    store = ConfigStore();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void mockPathProvider() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  }

  group('ConfigStore', () {
    test('load returns defaults when no file exists', () async {
      mockPathProvider();
      final config = await store.load();
      expect(config.fontSize, 14.0);
      expect(config.theme, 'dark');
      expect(config.scrollback, 5000);
    });

    test('save and load roundtrip', () async {
      mockPathProvider();
      const custom = AppConfig(
        terminal: TerminalConfig(fontSize: 18.0, theme: 'light', scrollback: 10000),
        ssh: SshDefaults(keepAliveSec: 60),
      );
      await store.save(custom);

      // Create a new store to load from disk
      final store2 = ConfigStore();
      final loaded = await store2.load();
      expect(loaded.fontSize, 18.0);
      expect(loaded.theme, 'light');
      expect(loaded.scrollback, 10000);
      expect(loaded.keepAliveSec, 60);
    });

    test('config getter returns current config', () async {
      mockPathProvider();
      expect(store.config.fontSize, 14.0); // default before load
      await store.load();
      expect(store.config.fontSize, 14.0); // still default, no file
    });

    test('update applies updater function', () async {
      mockPathProvider();
      await store.load();
      await store.update((c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 20.0)));
      expect(store.config.fontSize, 20.0);

      // Verify persisted
      final store2 = ConfigStore();
      final loaded = await store2.load();
      expect(loaded.fontSize, 20.0);
    });

    test('load handles corrupted JSON gracefully', () async {
      mockPathProvider();
      // Write invalid JSON to the config file
      await store.save(AppConfig.defaults); // init the path
      final file = File('${tempDir.path}/config.json');
      await file.writeAsString('not valid json {{{');

      final store2 = ConfigStore();
      final config = await store2.load();
      // Should fall back to defaults
      expect(config.fontSize, 14.0);
      expect(config.theme, 'dark');
    });

    test('save creates parent directories', () async {
      // Use a nested path
      final nestedDir = Directory('${tempDir.path}/nested/deep');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => nestedDir.path,
      );

      await store.save(AppConfig.defaults);
      expect(File('${nestedDir.path}/config.json').existsSync(), isTrue);
    });

    test('saved file contains valid JSON', () async {
      mockPathProvider();
      const config = AppConfig(terminal: TerminalConfig(fontSize: 16.0, theme: 'system'));
      await store.save(config);

      final content = await File('${tempDir.path}/config.json').readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json['font_size'], 16.0);
      expect(json['theme'], 'system');
    });

    test('init is idempotent', () async {
      mockPathProvider();
      await store.load(); // calls init
      await store.load(); // calls init again, should not fail
      expect(store.config, isNotNull);
    });

    test('loadedFromFile is true after successful load', () async {
      mockPathProvider();
      await store.save(AppConfig.defaults);

      final store2 = ConfigStore();
      await store2.load();
      expect(store2.loadedFromFile, isTrue);
      expect(store2.loadError, isNull);
    });

    test('loadedFromFile is false when no file exists', () async {
      mockPathProvider();
      await store.load();
      expect(store.loadedFromFile, isFalse);
      expect(store.loadError, isNull);
    });

    test('loadError is set on corrupted JSON', () async {
      mockPathProvider();
      await store.save(AppConfig.defaults);
      final file = File('${tempDir.path}/config.json');
      await file.writeAsString('corrupted {{{');

      final store2 = ConfigStore();
      await store2.load();
      expect(store2.loadedFromFile, isFalse);
      expect(store2.loadError, isNotNull);
      expect(store2.loadError, contains('Failed to load'));
    });

    test('loadError is cleared on subsequent successful load', () async {
      mockPathProvider();
      // First: corrupt file
      final file = File('${tempDir.path}/config.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('bad');

      await store.load();
      expect(store.loadError, isNotNull);

      // Fix the file
      await store.save(AppConfig.defaults);
      await store.load();
      expect(store.loadError, isNull);
      expect(store.loadedFromFile, isTrue);
    });
  });
}
