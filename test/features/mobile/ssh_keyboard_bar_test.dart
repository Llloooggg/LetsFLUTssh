import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/ssh_keyboard_bar.dart';
import 'package:letsflutssh/features/mobile/ssh_key_sequences.dart';
import 'package:letsflutssh/theme/app_theme.dart';

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

  Widget buildApp({required void Function(String) onInput}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SshKeyboardBar(onInput: onInput),
      ),
    );
  }

  group('SshKeyboardBar', () {
    testWidgets('renders main row buttons', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
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
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('Esc sends escape sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('Esc'));
      await tester.pump();
      expect(sent, SshKeySequences.escape);
    });

    testWidgets('Tab sends tab sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(sent, SshKeySequences.tab);
    });

    testWidgets('pipe sends | character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('|'));
      await tester.pump();
      expect(sent, '|');
    });

    testWidgets('tilde sends ~ character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('~'));
      await tester.pump();
      expect(sent, '~');
    });

    testWidgets('slash sends / character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sent, '/');
    });

    testWidgets('dash sends - character', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.text('-'));
      await tester.pump();
      expect(sent, '-');
    });

    testWidgets('arrow left sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
      await tester.pump();
      expect(sent, SshKeySequences.arrowLeft);
    });

    testWidgets('arrow up sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(sent, SshKeySequences.arrowUp);
    });

    testWidgets('arrow down sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(sent, SshKeySequences.arrowDown);
    });

    testWidgets('arrow right sends correct sequence', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(sent, SshKeySequences.arrowRight);
    });

    testWidgets('Fn toggles F-key row visibility', (tester) async {
      await tester.pumpWidget(buildApp(onInput: (_) {}));
      // Initially no F-keys visible
      expect(find.text('F1'), findsNothing);

      // Tap Fn to show
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('F12'), findsOneWidget);

      // Tap Fn again to hide
      await tester.tap(find.text('Fn'));
      await tester.pump();
      expect(find.text('F1'), findsNothing);
    });

    testWidgets('F1 sends correct sequence when Fn row is open', (tester) async {
      String? sent;
      await tester.pumpWidget(buildApp(onInput: (s) => sent = s));
      // Open Fn row
      await tester.tap(find.text('Fn'));
      await tester.pump();
      // Tap F1
      await tester.tap(find.text('F1'));
      await tester.pump();
      expect(sent, SshKeySequences.f1);
    });

    testWidgets('Ctrl modifier applies to next key (one-shot)', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Tap Ctrl (one-shot)
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Tap a special char (|) — Ctrl applies to single char
      await tester.tap(find.text('|'));
      await tester.pump();

      // Ctrl+| should send ctrlKey('|')
      expect(sentData.last, SshKeySequences.ctrlKey('|'));
    });

    testWidgets('Alt modifier applies ESC prefix (one-shot)', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Tap Alt (one-shot)
      await tester.tap(find.text('Alt'));
      await tester.pump();

      // Tap '~'
      await tester.tap(find.text('~'));
      await tester.pump();

      // Alt+~ should send ESC prefix
      expect(sentData.last, SshKeySequences.altKey('~'));
    });

    testWidgets('Ctrl deactivates after one-shot use', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // Activate Ctrl
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // First key with Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();

      // Second key without Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();

      // Second should be raw '/'
      expect(sentData.last, '/');
    });

    testWidgets('Ctrl double-tap locks, triple-tap unlocks', (tester) async {
      final sentData = <String>[];
      await tester.pumpWidget(buildApp(onInput: (s) => sentData.add(s)));

      // First tap = once
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Second tap = locked
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      // Send two keys — both should have Ctrl
      await tester.tap(find.text('/'));
      await tester.pump();
      final firstWithCtrl = sentData.last;

      await tester.tap(find.text('/'));
      await tester.pump();
      final secondWithCtrl = sentData.last;

      expect(firstWithCtrl, SshKeySequences.ctrlKey('/'));
      expect(secondWithCtrl, SshKeySequences.ctrlKey('/'));

      // Third tap on Ctrl = off
      await tester.tap(find.text('Ctrl'));
      await tester.pump();

      await tester.tap(find.text('/'));
      await tester.pump();
      expect(sentData.last, '/');
    });
  });
}
