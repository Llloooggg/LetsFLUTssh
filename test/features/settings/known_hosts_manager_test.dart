import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/features/settings/known_hosts_manager.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  late Directory tempDir;
  late KnownHostsManager manager;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('khm_dialog_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = KnownHostsManager();
    // Pre-load so the dialog's initState gets a cached future immediately —
    // avoids transient spinner state where pumpAndSettle hangs forever on
    // the indeterminate CircularProgressIndicator animation.
    await manager.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget buildApp(KnownHostsManager mgr) {
    return ProviderScope(
      overrides: [knownHostsProvider.overrideWithValue(mgr)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => KnownHostsManagerDialog.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the dialog and waits past the loading spinner.
  ///
  /// We use `runAsync` so the real async [KnownHostsManager.load] microtask
  /// resolves, then `pump` to apply the resulting `setState(_loading=false)`.
  /// `pumpAndSettle` is unsafe here — the indeterminate
  /// `CircularProgressIndicator` animation never quiesces.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pump(); // start dialog route + initState
    // Let the await on _manager.load() resolve in a real microtask.
    await tester.runAsync(() => Future<void>.value());
    // Apply the setState that ran inside _loadHosts.
    await tester.pump();
  }

  group('KnownHostsManagerDialog', () {
    testWidgets('shows content (no spinner) after load', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      // Dialog title should be visible — confirms dialog mounted.
      expect(find.text('Known Hosts'), findsOneWidget);
      // After load completes, spinner should be gone.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows empty state when no hosts', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(
        find.text('No known hosts yet. Connect to a server to add one.'),
        findsOneWidget,
      );
    });

    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      expect(find.text('Known Hosts'), findsOneWidget);
    });

    testWidgets('search field is present in dialog', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      // Search field is present
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
    });

    testWidgets('clear all button is disabled when empty', (tester) async {
      await tester.pumpWidget(buildApp(manager));
      await openDialog(tester);

      final clearAllBtn = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.delete_sweep,
      );
      expect(clearAllBtn, findsOneWidget);
      final btn = tester.widget<IconButton>(clearAllBtn);
      expect(btn.onPressed, isNull);
    });
  });
}
