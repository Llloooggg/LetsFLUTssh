import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/session_manager/qr_display_screen.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  // The display screen renders whatever string it is handed — the actual
  // encoded payload bytes are irrelevant to the dialog under test, so we
  // hand it a fixed deeplink-shaped string instead of round-tripping
  // through the encoder. The encoder itself lives Rust-side now and is
  // covered by `lfs_core::archive` unit tests.
  const testPayload = 'letsflutssh://import?d=test-payload-stub';

  Widget buildApp({required String data, int sessionCount = 1}) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: QrDisplayScreen(data: data, sessionCount: sessionCount),
    );
  }

  group('QrDisplayScreen', () {
    testWidgets('shows session count', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload, sessionCount: 3));
      await tester.pumpAndSettle();

      expect(find.text('3 sessions'), findsOneWidget);
    });

    testWidgets('shows scan instructions', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scan with any camera app'), findsOneWidget);
    });

    testWidgets('shows no-credentials disclaimer by default', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      // Defaulting `containsCredentials` to false keeps the neutral info
      // message — the earlier "lie" about "No passwords in QR" is only
      // shown when the payload really has none.
      expect(find.textContaining('No passwords or keys'), findsOneWidget);
      expect(find.textContaining('contains session credentials'), findsNothing);
    });

    testWidgets('swaps to orange warning when containsCredentials=true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: QrDisplayScreen(
            data: testPayload,
            sessionCount: 1,
            containsCredentials: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('contains session credentials'),
        findsOneWidget,
      );
      expect(find.textContaining('No passwords or keys'), findsNothing);
      // Warning icon lives inside the badge.
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('renders QR image widget', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      // QrImageView renders within the white container
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('static show method navigates to screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => QrDisplayScreen.show(
                  context,
                  data: testPayload,
                  sessionCount: 5,
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('5 sessions'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('works with dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: ThemeData.dark(),
          home: const QrDisplayScreen(data: testPayload, sessionCount: 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 session'), findsOneWidget);
    });

    testWidgets('works with light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: ThemeData.light(),
          home: const QrDisplayScreen(data: testPayload, sessionCount: 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 session'), findsOneWidget);
    });

    testWidgets('shows Copy Link button', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      // The copy action lives in the dialog's action bar as an
      // AppButton.primary (label-only) — no icon any more.
      expect(find.text('Copy Link'), findsOneWidget);
    });

    testWidgets('Copy Link button copies data to clipboard', (tester) async {
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardContent = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy Link'));
      // Let the Toast animation + auto-dismiss timer fully complete.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(clipboardContent, testPayload);
    });
  });
}
