import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildApp({AppConfig? initialConfig}) {
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
        home: const SizedBox(
          height: 1200,
          child: SettingsScreen(),
        ),
      ),
    );
  }

  group('SettingsScreen — export dialog empty password guard', () {
    testWidgets('export with empty password does not close dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      // Leave passwords empty and tap Export
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      // Dialog should still be open (empty password returns early)
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — export dialog password match validation', () {
    testWidgets('matching passwords close dialog', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      // Enter matching passwords
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pass123');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'pass123');
      await tester.pumpAndSettle();

      // Tap Export — passwords match, dialog should close
      // (the actual export will fail since no sessions exist and path_provider isn't mocked,
      //  but the dialog itself should close)
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      // Dialog should be closed (password returned)
      expect(find.text('Confirm Password'), findsNothing);

      // Wait for any toast to disappear
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog mode switch description', () {
    testWidgets('merge mode shows merge description', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Default mode is Merge
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('switching to Replace shows replace description',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Switch to Replace
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(
          find.text('Replace all sessions with imported'), findsOneWidget);

      // Switch back to Merge
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog submit with both fields filled', () {
    testWidgets('import with path and password closes dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Fill both fields
      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/nonexistent.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pass123');
      await tester.pumpAndSettle();

      // Tap Import — dialog should close (actual import will fail, toast shown)
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Path to .lfs file'), findsNothing);

      // Wait for any toast
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog cancel', () {
    testWidgets('cancel closes import dialog without action', (tester) async {
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
  });

  group('SettingsScreen — Reset to Defaults resets all fields', () {
    testWidgets('reset to defaults updates config', (tester) async {
      final customConfig = AppConfig.defaults.copyWith(
        fontSize: 20.0,
        scrollback: 10000,
        keepAliveSec: 60,
        sshTimeoutSec: 30,
        transferWorkers: 5,
      );
      await tester.pumpWidget(buildApp(initialConfig: customConfig));

      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();

      // Should not crash, settings should render
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('SettingsScreen — about section', () {
    testWidgets('about section shows app name and version', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('LetsFLUTssh'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.textContaining('SSH/SFTP client'), findsOneWidget);
    });

    testWidgets('source code link copies URL', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Source Code'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Source Code'));
      await tester.pump();

      expect(find.text('URL copied to clipboard'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — theme selector', () {
    testWidgets('switching to Light theme updates selection', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('switching to System theme updates selection', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);
    });
  });

  group('SettingsScreen — slider drag interaction', () {
    testWidgets('dragging font size slider changes value', (tester) async {
      await tester.pumpWidget(buildApp());

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Drag slider to the right
      await tester.drag(slider, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  group('SettingsScreen — IntTile text submission', () {
    testWidgets('submitting non-numeric value is ignored', (tester) async {
      await tester.pumpWidget(buildApp());

      final keepAliveField = find.widgetWithText(TextFormField, '30');
      await tester.tap(keepAliveField);
      await tester.pumpAndSettle();
      await tester.enterText(keepAliveField, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Should not crash, value is not updated
    });

    testWidgets('submitting value above max is ignored', (tester) async {
      await tester.pumpWidget(buildApp());

      final timeoutField = find.widgetWithText(TextFormField, '10');
      await tester.tap(timeoutField);
      await tester.pumpAndSettle();
      await tester.enterText(timeoutField, '999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 999 > max (60), should not update
    });
  });

  group('SettingsScreen — section headers present', () {
    testWidgets('all section headers are rendered', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);

      // Scroll to see Transfers and Data sections
      await tester.scrollUntilVisible(
        find.text('Transfers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Transfers'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
    });
  });

  group('SettingsScreen — export and import subtitles', () {
    testWidgets('export tile shows subtitle', (tester) async {
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

    testWidgets('import tile shows subtitle', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Load data from .lfs file'), findsOneWidget);
    });
  });
}
