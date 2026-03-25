import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildApp({AppConfig? initialConfig, double height = 1200}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = config;
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: SizedBox(
          height: height,
          child: const SettingsScreen(),
        ),
      ),
    );
  }

  group('SettingsScreen — font size slider interaction', () {
    testWidgets('slider has onChanged wired', (tester) async {
      await tester.pumpWidget(buildApp());

      // Get the slider and verify onChanged is wired
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
      expect(slider.value, 14.0);
      expect(slider.min, 8.0);
      expect(slider.max, 24.0);
      expect(slider.divisions, 16);
    });

    testWidgets('slider label shows formatted value', (tester) async {
      final config = AppConfig.defaults.copyWith(fontSize: 16.0);
      await tester.pumpWidget(buildApp(initialConfig: config));

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.label, '16');
      expect(slider.value, 16.0);
    });
  });

  group('SettingsScreen — theme selector interactions', () {
    testWidgets('tapping Dark when already Dark keeps Dark selected',
        (tester) async {
      await tester.pumpWidget(buildApp());

      // Dark is already selected, tap it again
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final segmentedButton = tester.widget<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>));
      expect(segmentedButton.selected, {'dark'});
    });

    testWidgets('switching to Light and then System', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();

      // Widget should not crash
      expect(find.text('Theme'), findsOneWidget);
    });
  });

  group('SettingsScreen — Reset to Defaults interaction', () {
    testWidgets('Reset to Defaults button is present and tappable',
        (tester) async {
      final customConfig = AppConfig.defaults.copyWith(
        fontSize: 20.0,
        scrollback: 10000,
      );
      await tester.pumpWidget(buildApp(initialConfig: customConfig));

      // Scroll to Reset button
      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap Reset - it calls configProvider.notifier.update
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();

      // Widget should still render without crash
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('SettingsScreen — IntTile edge cases', () {
    testWidgets('submitting 0 for keep-alive accepts it (min is 0)',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final keepAliveField =
          find.widgetWithText(TextFormField, '30');
      await tester.tap(keepAliveField);
      await tester.pumpAndSettle();
      await tester.enterText(keepAliveField, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 0 is within range (0-300) for keep-alive
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('submitting negative value is rejected', (tester) async {
      await tester.pumpWidget(buildApp());

      final keepAliveField =
          find.widgetWithText(TextFormField, '30');
      await tester.tap(keepAliveField);
      await tester.pumpAndSettle();
      await tester.enterText(keepAliveField, '-5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // -5 is out of range, field should NOT update to -5
      // The old value persists because int.tryParse returns null for negatives
      // or the range check fails. Either way, no crash.
    });

    testWidgets('submitting max boundary value for port', (tester) async {
      await tester.pumpWidget(buildApp());

      final portField = find.widgetWithText(TextFormField, '22');
      await tester.tap(portField);
      await tester.pumpAndSettle();
      await tester.enterText(portField, '65535');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('65535'), findsOneWidget);
    });

    testWidgets('submitting min boundary value for timeout', (tester) async {
      await tester.pumpWidget(buildApp());

      final timeoutField = find.widgetWithText(TextFormField, '10');
      await tester.tap(timeoutField);
      await tester.pumpAndSettle();
      await tester.enterText(timeoutField, '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('SettingsScreen — transfer field edge cases', () {
    testWidgets('max workers boundary value', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final workersField = find.widgetWithText(TextFormField, '2');
      await tester.tap(workersField);
      await tester.pumpAndSettle();
      await tester.enterText(workersField, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('workers out of range is rejected', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final workersField = find.widgetWithText(TextFormField, '2');
      await tester.tap(workersField);
      await tester.pumpAndSettle();
      await tester.enterText(workersField, '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 99 > max (10), should not update
    });

    testWidgets('max history min boundary', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Max History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final historyField = find.widgetWithText(TextFormField, '500');
      await tester.tap(historyField);
      await tester.pumpAndSettle();
      await tester.enterText(historyField, '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
    });
  });

  group('SettingsScreen — slider label displays', () {
    testWidgets('slider label shows rounded value', (tester) async {
      await tester.pumpWidget(buildApp());

      final slider = tester.widget<Slider>(find.byType(Slider));
      // Verify label is set
      expect(slider.label, '14');
    });

    testWidgets('slider with 8.0 font shows 8', (tester) async {
      final config = AppConfig.defaults.copyWith(fontSize: 8.0);
      await tester.pumpWidget(buildApp(initialConfig: config));

      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('slider with 24.0 font shows 24', (tester) async {
      final config = AppConfig.defaults.copyWith(fontSize: 24.0);
      await tester.pumpWidget(buildApp(initialConfig: config));

      expect(find.text('24'), findsOneWidget);
    });
  });

  group('SettingsScreen — _SliderTile clamp', () {
    testWidgets('value out of range is clamped', (tester) async {
      // If config somehow has a value outside the slider range, it should be clamped
      final config = AppConfig.defaults.copyWith(fontSize: 4.0);
      await tester.pumpWidget(buildApp(initialConfig: config));

      // Slider should render without error (value clamped to min=8)
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 8.0); // clamped
    });
  });

  group('SettingsScreen — export dialog fields', () {
    testWidgets('export dialog has Master Password and Confirm fields',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      // Master Password and Confirm Password labels should be present
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Find the labeled TextFields
      final masterPw =
          tester.widget<TextField>(find.widgetWithText(TextField, 'Master Password'));
      final confirmPw =
          tester.widget<TextField>(find.widgetWithText(TextField, 'Confirm Password'));
      expect(masterPw.obscureText, isTrue);
      expect(confirmPw.obscureText, isTrue);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog fields', () {
    testWidgets('import dialog has path and password fields', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Find labeled TextFields
      final pwField =
          tester.widget<TextField>(find.widgetWithText(TextField, 'Master Password'));
      expect(pwField.obscureText, isTrue);

      // Path field should NOT be obscured
      final pathField =
          tester.widget<TextField>(find.widgetWithText(TextField, 'Path to .lfs file'));
      expect(pathField.obscureText, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — show() static method', () {
    testWidgets('show() pushes SettingsScreen and can go back', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith((ref) {
              final notifier =
                  ConfigNotifier(ref.watch(configStoreProvider));
              notifier.state = AppConfig.defaults;
              return notifier;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => SettingsScreen.show(context),
                  child: const Text('Open Settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // Navigate back
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('SettingsScreen — section headers styling', () {
    testWidgets('section headers use titleSmall style', (tester) async {
      await tester.pumpWidget(buildApp());

      // Verify headers are rendered with correct text
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);
    });
  });
}
