import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/providers/config_provider.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ConfigNotifier persistence routes through `loadAppConfigFromDisk`
  // / `_saveAppConfigToDisk`, which encode via `AppConfig.toJson` →
  // Rust canonical encoder. Bootstrap FRB so the round-trip survives.
  setUpAll(requireFrbLoaded);
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_prov_test_');
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
    test('starts with AppConfig.defaults when no preload', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      expect(notifier.state, equals(AppConfig.defaults));
    });

    test('seeds state from preloadedAppConfigProvider when set', () {
      const seed = AppConfig(
        terminal: TerminalConfig(fontSize: 22.0, theme: 'light'),
      );
      final container = ProviderContainer(
        overrides: [preloadedAppConfigProvider.overrideWithValue(seed)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);
      expect(notifier.state.fontSize, 22.0);
      expect(notifier.state.theme, 'light');
    });

    test('load() reads disk into state', () async {
      // Pre-write a config file in the temp dir so load() finds it.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seed = container.read(configProvider.notifier);
      await seed.update(
        (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 20.0)),
      );

      // Fresh container — load from the file we just wrote.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final n2 = c2.read(configProvider.notifier);
      await n2.load();
      expect(n2.state.fontSize, 20.0);
    });

    test('update() applies updater and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);

      await notifier.update(
        (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 24.0)),
      );
      expect(notifier.state.fontSize, 24.0);

      // Verify persisted by re-loading from a fresh container.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final n2 = c2.read(configProvider.notifier);
      await n2.load();
      expect(n2.state.fontSize, 24.0);
    });

    test('update() preserves untouched fields', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);

      await notifier.update(
        (c) => c.copyWith(
          terminal: c.terminal.copyWith(fontSize: 16.0, scrollback: 8000),
        ),
      );

      await notifier.update(
        (c) => c.copyWith(terminal: c.terminal.copyWith(theme: 'system')),
      );
      expect(notifier.state.fontSize, 16.0);
      expect(notifier.state.scrollback, 8000);
      expect(notifier.state.theme, 'system');
    });

    test('rapid update bursts coalesce into a single trailing save', () async {
      final container = ProviderContainer(
        overrides: [configProvider.overrideWith(_SaveCountingNotifier.new)],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(configProvider.notifier) as _SaveCountingNotifier;

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
        notifier.saveCount,
        1,
        reason: '20 updates inside the debounce window must coalesce',
      );
    });

    test('concurrent updates do not corrupt saved config', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(configProvider.notifier);

      // Fire two updates concurrently — saves are serialized.
      await Future.wait([
        notifier.update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 20.0)),
        ),
        notifier.update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(theme: 'dark')),
        ),
      ]);

      expect(notifier.state.fontSize, 20.0);
      expect(notifier.state.theme, 'dark');

      // Persisted config should have both.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final n2 = c2.read(configProvider.notifier);
      await n2.load();
      expect(n2.state.theme, 'dark');
    });
  });
}

/// Counts how many times the production [ConfigNotifier.persist] method
/// runs so the debounce-coalescing assertion has a numeric handle.
class _SaveCountingNotifier extends ConfigNotifier {
  int saveCount = 0;

  @override
  Future<void> persist(AppConfig config) {
    saveCount++;
    return super.persist(config);
  }
}
