import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/shortcut_registry.dart';

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
  });
}
