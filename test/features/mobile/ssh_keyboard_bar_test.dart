import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/ssh_keyboard_bar.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/theme/app_theme.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  // Suppress HapticFeedback calls in tests
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildApp({
    required void Function(rust_terminal.TerminalKey) onKey,
    GlobalKey<SshKeyboardBarState>? keyboardKey,
    VoidCallback? onPaste,
    VoidCallback? onSnippets,
    ValueChanged<bool>? onCopyModeChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SshKeyboardBar(
          key: keyboardKey,
          onKey: onKey,
          onPaste: onPaste,
          onSnippets: onSnippets,
          onCopyModeChanged: onCopyModeChanged,
        ),
      ),
    );
  }

  bool isChar(rust_terminal.TerminalKey k, String ch) {
    final name = k.name;
    return name is rust_terminal.TerminalKeyName_Char &&
        name.code == ch.runes.first;
  }

  group('SshKeyboardBar', () {
    testWidgets('renders main row buttons', (tester) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
      expect(find.text('Fn'), findsOneWidget);
      expect(find.text('|'), findsOneWidget);
      expect(find.text('~'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('renders arrow key icons', (tester) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('Esc emits an Escape key', (tester) async {
      rust_terminal.TerminalKey? sent;
      await tester.pumpWidget(buildApp(onKey: (k) => sent = k));
      await tester.tap(find.text('Esc'));
      await tester.pump();
      expect(sent!.name, isA<rust_terminal.TerminalKeyName_Escape>());
    });

    testWidgets('Tab emits a Tab key', (tester) async {
      rust_terminal.TerminalKey? sent;
      await tester.pumpWidget(buildApp(onKey: (k) => sent = k));
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(sent!.name, isA<rust_terminal.TerminalKeyName_Tab>());
    });

    testWidgets('pipe emits a | char key', (tester) async {
      rust_terminal.TerminalKey? sent;
      await tester.pumpWidget(buildApp(onKey: (k) => sent = k));
      await tester.tap(find.text('|'));
      await tester.pump();
      expect(isChar(sent!, '|'), isTrue);
    });

    testWidgets('arrow keys emit their named keys', (tester) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
      await tester.pump();
      expect(sent.last.name, isA<rust_terminal.TerminalKeyName_Left>());
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(sent.last.name, isA<rust_terminal.TerminalKeyName_Up>());
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(sent.last.name, isA<rust_terminal.TerminalKeyName_Down>());
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(sent.last.name, isA<rust_terminal.TerminalKeyName_Right>());
    });

    testWidgets('Fn toggles F-key row visibility', (tester) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.text('F1'), findsNothing);

      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('F12'), findsOneWidget);

      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsNothing);
    });

    testWidgets('F5 emits an F(5) key when Fn row is open', (tester) async {
      rust_terminal.TerminalKey? sent;
      await tester.pumpWidget(buildApp(onKey: (k) => sent = k));
      await tester.tap(find.text('Fn'));
      await tester.pump();
      await tester.tap(find.text('F5'));
      await tester.pump();
      final name = sent!.name;
      expect(name, isA<rust_terminal.TerminalKeyName_F>());
      expect((name as rust_terminal.TerminalKeyName_F).number, 5);
    });
  });

  group('SshKeyboardBar — sticky modifiers fold into the key', () {
    testWidgets('Ctrl one-shot folds into the next char key', (tester) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('|'));
      await tester.pump();

      expect(isChar(sent.last, '|'), isTrue);
      expect(sent.last.ctrl, isTrue);
    });

    testWidgets('Alt one-shot folds ESC-meta into the next char key', (
      tester,
    ) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));

      await tester.tap(find.text('Alt'));
      await tester.pump();
      await tester.tap(find.text('~'));
      await tester.pump();

      expect(isChar(sent.last, '~'), isTrue);
      expect(sent.last.alt, isTrue);
    });

    testWidgets('Ctrl one-shot is consumed after one key', (tester) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('/'));
      await tester.pump();
      await tester.tap(find.text('/'));
      await tester.pump();

      // Second key carries no Ctrl.
      expect(sent.last.ctrl, isFalse);
    });

    testWidgets('Ctrl double-tap locks, triple-tap unlocks', (tester) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));

      // once
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      // locked
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sent.last.ctrl, isTrue);
      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sent.last.ctrl, isTrue);

      // off
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sent.last.ctrl, isFalse);
    });

    testWidgets('both modifiers fold into one key', (tester) async {
      final sent = <rust_terminal.TerminalKey>[];
      await tester.pumpWidget(buildApp(onKey: sent.add));

      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      await tester.tap(find.text('Alt'));
      await tester.pump();
      await tester.tap(find.text('|'));
      await tester.pump();

      expect(sent.last.ctrl, isTrue);
      expect(sent.last.alt, isTrue);
    });

    testWidgets('ctrlActive / altActive expose the sticky state', (
      tester,
    ) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onKey: (_) {}, keyboardKey: key));

      expect(key.currentState!.ctrlActive, isFalse);
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(key.currentState!.ctrlActive, isTrue);

      // consumeOneShotModifiers clears a one-shot.
      key.currentState!.consumeOneShotModifiers();
      await tester.pump();
      expect(key.currentState!.ctrlActive, isFalse);
    });
  });

  group('SshKeyboardBar — layout', () {
    testWidgets('main row keys are inside a horizontal ListView', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      final listViews = find.byType(ListView);
      expect(listViews, findsOneWidget);
      final listView = tester.widget<ListView>(listViews.first);
      expect(listView.scrollDirection, Axis.horizontal);
    });

    testWidgets('F-keys row appears with its own ListView when Fn active', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.byType(ListView), findsOneWidget);
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.byType(ListView), findsNWidgets(2));
    });
  });

  group('Copy mode', () {
    testWidgets('renders copy button icon', (tester) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('tapping copy button toggles copy mode and fires callback', (
      tester,
    ) async {
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(onKey: (_) {}, onCopyModeChanged: modes.add),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(modes, [true]);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(modes, [true, false]);
    });

    testWidgets('copyMode getter reflects state', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      await tester.pumpWidget(buildApp(onKey: (_) {}, keyboardKey: key));

      expect(key.currentState!.copyMode, isFalse);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(key.currentState!.copyMode, isTrue);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(key.currentState!.copyMode, isFalse);
    });

    testWidgets('snippets button hidden when onSnippets is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.byIcon(Icons.code), findsNothing);
    });

    testWidgets('tapping snippets button fires onSnippets callback', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        buildApp(onKey: (_) {}, onSnippets: () => fired = true),
      );
      expect(find.byIcon(Icons.code), findsOneWidget);
      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('exitCopyMode resets state and fires callback', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(onKey: (_) {}, keyboardKey: key, onCopyModeChanged: modes.add),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(key.currentState!.copyMode, isTrue);

      key.currentState!.exitCopyMode();
      await tester.pump();
      expect(key.currentState!.copyMode, isFalse);
      expect(modes, [true, false]);
    });

    testWidgets('exitCopyMode is no-op when already off', (tester) async {
      final key = GlobalKey<SshKeyboardBarState>();
      final modes = <bool>[];
      await tester.pumpWidget(
        buildApp(onKey: (_) {}, keyboardKey: key, onCopyModeChanged: modes.add),
      );

      key.currentState!.exitCopyMode();
      await tester.pump();
      expect(modes, isEmpty);
    });
  });

  group('Paste button', () {
    testWidgets('renders paste icon in keyboard bar', (tester) async {
      await tester.pumpWidget(buildApp(onKey: (_) {}));
      expect(find.byIcon(Icons.paste), findsOneWidget);
    });

    testWidgets('tapping paste button fires onPaste callback', (tester) async {
      var pasteCalled = false;
      await tester.pumpWidget(
        buildApp(onKey: (_) {}, onPaste: () => pasteCalled = true),
      );

      await tester.tap(find.byIcon(Icons.paste));
      await tester.pump();
      expect(pasteCalled, isTrue);
    });
  });
}
