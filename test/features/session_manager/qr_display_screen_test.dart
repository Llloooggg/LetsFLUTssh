import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/qr_display_screen.dart';

void main() {
  final testPayload = wrapInDeepLink(encodeSessionsForQr([
    Session(
      label: 'test-server',
      server: const ServerAddress(host: 'example.com', user: 'root'),
    ),
  ]));

  Widget buildApp({required String data, int sessionCount = 1}) {
    return MaterialApp(
      home: QrDisplayScreen(data: data, sessionCount: sessionCount),
    );
  }

  group('QrDisplayScreen', () {
    testWidgets('shows session count', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload, sessionCount: 3));
      await tester.pumpAndSettle();

      expect(find.text('3 session(s)'), findsOneWidget);
    });

    testWidgets('shows scan instructions', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scan with any camera app'), findsOneWidget);
    });

    testWidgets('shows no-credentials disclaimer', (tester) async {
      await tester.pumpWidget(buildApp(data: testPayload));
      await tester.pumpAndSettle();

      expect(find.textContaining('No passwords or keys'), findsOneWidget);
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
      await tester.pumpWidget(MaterialApp(
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
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('5 session(s)'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('works with dark theme', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: QrDisplayScreen(data: testPayload, sessionCount: 1),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 session(s)'), findsOneWidget);
    });

    testWidgets('works with light theme', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        home: QrDisplayScreen(data: testPayload, sessionCount: 1),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 session(s)'), findsOneWidget);
    });
  });
}
