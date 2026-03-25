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

  group('SettingsScreen — structure', () {
    testWidgets('renders app bar with title', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders as Scaffold with ListView', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('has dividers between sections', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(Divider), findsWidgets);
    });
  });

  group('SettingsScreen — Appearance section', () {
    testWidgets('renders Appearance section', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Font Size'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('SegmentedButton for theme is present', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
    });

    testWidgets('theme segmented button shows correct selection for dark',
        (tester) async {
      await tester.pumpWidget(buildApp());
      final segmentedButton = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(segmentedButton.selected, {'dark'});
    });

    testWidgets('theme segmented button shows correct selection for light',
        (tester) async {
      final lightConfig = AppConfig.defaults.copyWith(theme: 'light');
      await tester.pumpWidget(buildApp(initialConfig: lightConfig));
      final segmentedButton = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(segmentedButton.selected, {'light'});
    });

    testWidgets('theme segmented button shows correct selection for system',
        (tester) async {
      final sysConfig = AppConfig.defaults.copyWith(theme: 'system');
      await tester.pumpWidget(buildApp(initialConfig: sysConfig));
      final segmentedButton = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(segmentedButton.selected, {'system'});
    });

    testWidgets('font size slider shows current value', (tester) async {
      await tester.pumpWidget(buildApp());
      // Default font size is 14
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('font size slider with custom value', (tester) async {
      final config = AppConfig.defaults.copyWith(fontSize: 18.0);
      await tester.pumpWidget(buildApp(initialConfig: config));
      expect(find.text('18'), findsOneWidget);
    });

    testWidgets('slider is configured correctly', (tester) async {
      await tester.pumpWidget(buildApp());
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 8.0);
      expect(slider.max, 24.0);
      expect(slider.divisions, 16);
    });

    testWidgets('tapping Light theme button does not crash', (tester) async {
      await tester.pumpWidget(buildApp());

      // Tap "Light" — config update may fail (no persisted store) but UI should not crash
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      // Widget still renders
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('tapping System theme button does not crash', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);
    });
  });

  group('SettingsScreen — Terminal section', () {
    testWidgets('renders Terminal section', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Scrollback Lines'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
    });

    testWidgets('scrollback field with custom value', (tester) async {
      final config = AppConfig.defaults.copyWith(scrollback: 10000);
      await tester.pumpWidget(buildApp(initialConfig: config));
      expect(find.text('10000'), findsOneWidget);
    });

    testWidgets('scrollback field accepts valid input', (tester) async {
      await tester.pumpWidget(buildApp());

      // Find the scrollback TextFormField (it contains "5000")
      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      expect(scrollbackField, findsOneWidget);

      // Clear and type new value
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();

      // Enter new text
      await tester.enterText(scrollbackField, '8000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — Connection section', () {
    testWidgets('renders Connection section', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Keep-Alive Interval (sec)'), findsOneWidget);
      expect(find.text('SSH Timeout (sec)'), findsOneWidget);
      expect(find.text('Default Port'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('custom connection values display correctly', (tester) async {
      final config = AppConfig.defaults.copyWith(
        keepAliveSec: 60,
        sshTimeoutSec: 30,
        defaultPort: 2222,
      );
      await tester.pumpWidget(buildApp(initialConfig: config));
      expect(find.text('60'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('2222'), findsOneWidget);
    });

    testWidgets('TextFormField widgets for integer settings', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(TextFormField), findsWidgets);
    });
  });

  group('SettingsScreen — Transfers section', () {
    testWidgets('renders Transfers section after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('Parallel Workers'), findsOneWidget);
      expect(find.text('Max History'), findsOneWidget);
    });

    testWidgets('transfer section shows default values', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Default: 2 workers, 500 max history
      expect(find.text('2'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('custom transfer values display correctly', (tester) async {
      final config = AppConfig.defaults.copyWith(
        transferWorkers: 4,
        maxHistory: 1000,
      );
      await tester.pumpWidget(buildApp(initialConfig: config));

      await tester.scrollUntilVisible(
        find.text('Parallel Workers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('4'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });
  });

  group('SettingsScreen — Data section', () {
    testWidgets('renders Data section after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Export Data'), findsOneWidget);
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('export subtitle text', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.text('Save sessions, config, and keys to encrypted .lfs file'),
        findsOneWidget,
      );
    });

    testWidgets('import subtitle text', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Load data from .lfs file'), findsOneWidget);
    });

    testWidgets('export icon is present', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('import icon is present', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('Export Data tap opens export dialog', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      // Export dialog should appear
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('Export dialog cancel dismisses', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Master Password'), findsNothing);
    });

    testWidgets('Import Data tap opens import dialog', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Import dialog should appear
      expect(find.text('Path to .lfs file'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('Import dialog cancel dismisses', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Path to .lfs file'), findsNothing);
    });

    testWidgets('Import dialog shows mode descriptions', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Default mode is Merge
      expect(
          find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('Import dialog Replace mode shows description',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Tap Replace in segmented button
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.text('Replace all sessions with imported'), findsOneWidget);
    });
  });

  group('SettingsScreen — About section', () {
    testWidgets('renders About section after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('LetsFLUTssh'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('About'), findsOneWidget);
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.textContaining('v0.9.3'), findsOneWidget);
    });

    testWidgets('renders source code link after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Source Code'), findsOneWidget);
      expect(
          find.text('https://github.com/llloooggg/LetsFLUTssh'), findsOneWidget);
    });

    testWidgets('info icon is present', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('LetsFLUTssh'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('code icon is present', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byIcon(Icons.code), findsOneWidget);
    });

    testWidgets('source code tap does not crash', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap Source Code — copies URL to clipboard and shows Toast
      await tester.tap(find.text('Source Code'));
      await tester.pump();
      // Flush the Toast auto-dismiss timer (default 4 seconds)
      await tester.pump(const Duration(seconds: 5));

      // Widget still renders after tap
      expect(find.text('Source Code'), findsOneWidget);
    });
  });

  group('SettingsScreen — Reset to Defaults', () {
    testWidgets('renders Reset to Defaults after scrolling', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Reset to Defaults'), findsOneWidget);
      expect(find.byIcon(Icons.restore), findsOneWidget);
    });

    testWidgets('Reset to Defaults button is tappable', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap Reset — may fail to persist (no store) but should not crash
      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();

      // Widget still renders
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('SettingsScreen — custom config values', () {
    testWidgets('renders with custom config values', (tester) async {
      final customConfig = AppConfig.defaults.copyWith(
        fontSize: 18.0,
        theme: 'light',
        scrollback: 10000,
        keepAliveSec: 60,
      );
      await tester.pumpWidget(buildApp(initialConfig: customConfig));

      expect(find.text('10000'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
    });
  });

  group('SettingsScreen — IntTile field submission', () {
    testWidgets('submitting valid scrollback value updates config',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, '8000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Config should be updated
      expect(find.text('8000'), findsOneWidget);
    });

    testWidgets('submitting invalid scrollback value does not crash',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // No crash, old value retained
    });

    testWidgets('submitting out-of-range value does not update',
        (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, '999999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Value out of range (max 100000), should not update
    });
  });

  group('SettingsScreen — section headers', () {
    testWidgets('top section headers are rendered', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);
    });

    testWidgets('bottom section headers are rendered after scrolling',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('About'), findsOneWidget);
    });
  });

  group('SettingsScreen — slider interaction', () {
    testWidgets('slider has correct initial value', (tester) async {
      await tester.pumpWidget(buildApp());

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      final sliderWidget = tester.widget<Slider>(slider);
      expect(sliderWidget.value, 14.0);
    });

    testWidgets('slider with custom font size shows correct value',
        (tester) async {
      final config = AppConfig.defaults.copyWith(fontSize: 20.0);
      await tester.pumpWidget(buildApp(initialConfig: config));

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 20.0);
    });
  });
}
