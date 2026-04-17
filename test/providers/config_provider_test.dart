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
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      expect(notifier.state, equals(AppConfig.defaults));
    });

    test('load() updates state from store', () async {
      await store.save(
        const AppConfig(
          terminal: TerminalConfig(fontSize: 20.0, theme: 'light'),
        ),
      );
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);

      await notifier.load();
      expect(notifier.state.fontSize, 20.0);
      expect(notifier.state.theme, 'light');
    });

    test('update() applies updater and persists', () async {
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      await notifier.update(
        (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 24.0)),
      );
      expect(notifier.state.fontSize, 24.0);

      // Verify persisted
      final store2 = ConfigStore();
      final loaded = await store2.load();
      expect(loaded.fontSize, 24.0);
    });

    test('update() after load preserves other fields', () async {
      await store.save(
        const AppConfig(
          terminal: TerminalConfig(fontSize: 16.0, scrollback: 8000),
        ),
      );
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      await notifier.update(
        (c) => c.copyWith(terminal: c.terminal.copyWith(theme: 'system')),
      );
      expect(notifier.state.fontSize, 16.0);
      expect(notifier.state.scrollback, 8000);
      expect(notifier.state.theme, 'system');
    });

    test('rapid update bursts coalesce into a single trailing save', () async {
      // Wrap the real ConfigStore so we can count save() invocations
      // without rewriting the rest of the assertion model.
      final spy = _SaveCountingStore(store);
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(spy)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      // Simulate a slider drag: 20 updates inside the 300 ms debounce
      // window. Each one mutates state synchronously but they should
      // all share one trailing disk write.
      Future<void>? last;
      for (var i = 0; i < 20; i++) {
        last = notifier.update(
          (c) => c.copyWith(
            terminal: c.terminal.copyWith(fontSize: 12.0 + i.toDouble()),
          ),
        );
      }
      await last;

      expect(notifier.state.fontSize, 31.0);
      expect(
        spy.saveCount,
        1,
        reason: '20 updates inside the debounce window must coalesce',
      );
    });

    test('concurrent updates do not corrupt saved config', () async {
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      await notifier.load();

      // Fire two updates concurrently — saves should be serialized
      await Future.wait([
        notifier.update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 20.0)),
        ),
        notifier.update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(theme: 'dark')),
        ),
      ]);

      // State should reflect both updates (second reads after first's sync update)
      expect(notifier.state.fontSize, 20.0);
      expect(notifier.state.theme, 'dark');

      // Persisted config should also have both
      final loaded = await ConfigStore().load();
      expect(loaded.theme, 'dark');
    });
  });
}

/// Wraps an existing [ConfigStore] and counts how many times save() runs.
class _SaveCountingStore extends ConfigStore {
  final ConfigStore _inner;
  int saveCount = 0;

  _SaveCountingStore(this._inner);

  @override
  AppConfig get config => _inner.config;

  @override
  Future<AppConfig> load() => _inner.load();

  @override
  Future<void> save(AppConfig config) {
    saveCount++;
    return _inner.save(config);
  }
}
