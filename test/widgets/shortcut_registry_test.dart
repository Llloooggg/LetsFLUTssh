import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/shortcut_registry.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
  final registry = AppShortcutRegistry.instance;

  group('AppShortcutRegistry', () {
    test('binding returns the default SingleActivator for each shortcut', () {
      for (final shortcut in AppShortcut.values) {
        expect(
          registry.binding(shortcut),
          equals(shortcut.defaultBinding),
          reason: '${shortcut.name} binding should equal its default',
        );
      }
    });

    test(
      'buildCallbackMap maps shortcuts to callbacks via current bindings',
      () {
        var called = false;
        final map = registry.buildCallbackMap({
          AppShortcut.newSession: () => called = true,
        });

        expect(map.length, 1);
        expect(map.keys.first, equals(AppShortcut.newSession.defaultBinding));
        map.values.first();
        expect(called, isTrue);
      },
    );

    test('buildCallbackMap handles multiple shortcuts', () {
      final calls = <String>[];
      final map = registry.buildCallbackMap({
        AppShortcut.newSession: () => calls.add('new'),
        AppShortcut.closeTab: () => calls.add('close'),
        AppShortcut.toggleSidebar: () => calls.add('sidebar'),
      });

      expect(map.length, 3);
      for (final cb in map.values) {
        cb();
      }
      expect(calls, containsAll(['new', 'close', 'sidebar']));
    });

    test('buildCallbackMap returns empty map for empty input', () {
      final map = registry.buildCallbackMap({});
      expect(map, isEmpty);
    });

    test('buildCallbackMap throws on duplicate activator', () {
      // sessionCopy (Ctrl+C) and fileCopy (Ctrl+C) share an activator
      // by design — each is mounted under its own subtree. Mounting
      // both in one callback map silently dropped one of them to a
      // no-op (last-write-wins on the raw SingleActivator key). Fail
      // loud instead so future widget-tree refactors surface the
      // collision at build time.
      expect(
        () => registry.buildCallbackMap({
          AppShortcut.sessionCopy: () {},
          AppShortcut.fileCopy: () {},
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Duplicate shortcut activator'), contains('Ctrl+C')),
          ),
        ),
      );
    });

    group('matches', () {
      testWidgets('matches Ctrl+N for newSession', (tester) async {
        await tester.pumpWidget(
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyN) {
                expect(registry.matches(AppShortcut.newSession, event), isTrue);
              }
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });

      testWidgets('does not match Ctrl+N when shift is also pressed', (
        tester,
      ) async {
        await tester.pumpWidget(
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyN) {
                expect(
                  registry.matches(AppShortcut.newSession, event),
                  isFalse,
                );
              }
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });

      testWidgets('matches Ctrl+Shift+C for terminalCopy', (tester) async {
        await tester.pumpWidget(
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyC) {
                expect(
                  registry.matches(AppShortcut.terminalCopy, event),
                  isTrue,
                );
              }
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });

      testWidgets('matches plain Delete for fileDelete', (tester) async {
        await tester.pumpWidget(
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                expect(registry.matches(AppShortcut.fileDelete, event), isTrue);
              }
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
      });

      testWidgets('does not match wrong key', (tester) async {
        await tester.pumpWidget(
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                expect(
                  registry.matches(AppShortcut.newSession, event),
                  isFalse,
                );
              }
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });
    });

    test('every AppShortcut has a non-null defaultBinding', () {
      for (final shortcut in AppShortcut.values) {
        expect(shortcut.defaultBinding, isNotNull);
        expect(shortcut.defaultBinding.trigger, isNotNull);
      }
    });

    testWidgets('CallbackShortcuts fires callback from buildCallbackMap', (
      tester,
    ) async {
      var fired = false;
      final map = registry.buildCallbackMap({
        AppShortcut.toggleSidebar: () => fired = true,
      });

      await tester.pumpWidget(
        CallbackShortcuts(
          bindings: map,
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      );
      await tester.pump();

      // Ctrl+B = toggleSidebar
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(fired, isTrue);
    });

    testWidgets('CallbackShortcuts does not fire for unregistered shortcut', (
      tester,
    ) async {
      var fired = false;
      final map = registry.buildCallbackMap({
        AppShortcut.newSession: () => fired = true,
      });

      await tester.pumpWidget(
        CallbackShortcuts(
          bindings: map,
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      );
      await tester.pump();

      // Ctrl+B is toggleSidebar, not registered
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(fired, isFalse);
    });

    group('formatShortcut', () {
      test('Ctrl+Shift+V for terminalPaste', () {
        expect(
          formatShortcut(AppShortcut.terminalPaste.defaultBinding),
          'Ctrl+Shift+V',
        );
      });

      test('Ctrl+C for sessionCopy (no shift)', () {
        expect(
          formatShortcut(AppShortcut.sessionCopy.defaultBinding),
          'Ctrl+C',
        );
      });

      test('F2 for fileRename — printable function key', () {
        expect(formatShortcut(AppShortcut.fileRename.defaultBinding), 'F2');
      });

      test('Delete renders as "Delete", not raw keyId or blank', () {
        expect(formatShortcut(AppShortcut.fileDelete.defaultBinding), 'Delete');
      });

      test('Esc for terminalCloseSearch', () {
        expect(
          formatShortcut(AppShortcut.terminalCloseSearch.defaultBinding),
          'Esc',
        );
      });

      test('Ctrl+\\ for splitRight — backslash renders as glyph', () {
        expect(
          formatShortcut(AppShortcut.splitRight.defaultBinding),
          r'Ctrl+\',
        );
      });

      test('Ctrl+, for openSettings — comma renders as glyph', () {
        expect(
          formatShortcut(AppShortcut.openSettings.defaultBinding),
          'Ctrl+,',
        );
      });

      test('registry.shortcutLabel matches formatShortcut of live binding', () {
        for (final s in AppShortcut.values) {
          expect(
            registry.shortcutLabel(s),
            formatShortcut(registry.binding(s)),
          );
        }
      });
    });

    // Regression: every shortcut used to hard-code `control: true`,
    // so macOS users got zero working Cmd shortcuts and Ctrl+C
    // inside the terminal hit SIGINT instead of copy. The registry
    // now rewrites `control: true` → `meta: true` on macOS so the
    // platform-native primary modifier reaches every binding.
    group('macOS Cmd rewrite', () {
      tearDown(() {
        plat.debugIsMacosOverride = null;
        plat.debugResetPlatformCache();
      });

      test('control:true binding becomes meta:true on macOS', () {
        plat.debugIsMacosOverride = true;
        final activator = AppShortcutRegistry.resolvePlatformBindingForTesting(
          AppShortcut.newSession,
        );
        expect(activator.control, isFalse);
        expect(activator.meta, isTrue);
        expect(activator.trigger, LogicalKeyboardKey.keyN);
      });

      test('shift modifier is preserved on macOS rewrite', () {
        plat.debugIsMacosOverride = true;
        final activator = AppShortcutRegistry.resolvePlatformBindingForTesting(
          AppShortcut.terminalCopy,
        );
        expect(activator.control, isFalse);
        expect(activator.meta, isTrue);
        expect(activator.shift, isTrue);
        expect(activator.trigger, LogicalKeyboardKey.keyC);
      });

      test('non-mac platforms leave the binding untouched', () {
        plat.debugIsMacosOverride = false;
        final activator = AppShortcutRegistry.resolvePlatformBindingForTesting(
          AppShortcut.newSession,
        );
        expect(activator.control, isTrue);
        expect(activator.meta, isFalse);
      });

      test('plain key bindings (no control) are unaffected on macOS', () {
        plat.debugIsMacosOverride = true;
        // fileDelete is a bare Delete key, no modifiers.
        final activator = AppShortcutRegistry.resolvePlatformBindingForTesting(
          AppShortcut.fileDelete,
        );
        expect(activator.control, isFalse);
        expect(activator.meta, isFalse);
        expect(activator.trigger, LogicalKeyboardKey.delete);
      });

      test('formatShortcut renders meta as "Cmd" on macOS', () {
        plat.debugIsMacosOverride = true;
        const activator = SingleActivator(LogicalKeyboardKey.keyN, meta: true);
        expect(formatShortcut(activator), 'Cmd+N');
      });

      test('formatShortcut renders meta as "Meta" off macOS', () {
        plat.debugIsMacosOverride = false;
        const activator = SingleActivator(LogicalKeyboardKey.keyN, meta: true);
        expect(formatShortcut(activator), 'Meta+N');
      });
    });

    test('shortcut groups cover all expected contexts', () {
      final globalShortcuts = [
        AppShortcut.newSession,
        AppShortcut.closeTab,
        AppShortcut.nextTab,
        AppShortcut.prevTab,
        AppShortcut.toggleSidebar,
        AppShortcut.openSettings,
      ];
      final terminalShortcuts = [
        AppShortcut.terminalCopy,
        AppShortcut.terminalPaste,
        AppShortcut.terminalSearch,
      ];
      final fileShortcuts = [
        AppShortcut.fileSelectAll,
        AppShortcut.fileCopy,
        AppShortcut.filePaste,
        AppShortcut.fileDelete,
        AppShortcut.fileRename,
        AppShortcut.fileRefresh,
      ];
      final sessionShortcuts = [
        AppShortcut.sessionUndo,
        AppShortcut.sessionRedo,
        AppShortcut.sessionDelete,
      ];

      // All shortcut groups are subsets of AppShortcut.values
      for (final s in [
        ...globalShortcuts,
        ...terminalShortcuts,
        ...fileShortcuts,
        ...sessionShortcuts,
      ]) {
        expect(AppShortcut.values, contains(s), reason: '${s.name} missing');
      }
    });
  });
}
