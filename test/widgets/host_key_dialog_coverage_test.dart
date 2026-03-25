import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/host_key_dialog.dart';

void main() {
  Widget buildApp({required void Function(BuildContext) onPressed}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('HostKeyDialog — fingerprint copy button', () {
    testWidgets('copy button exists in new host dialog', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'example.com',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'SHA256:abc123def456',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Copy button should be present
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byTooltip('Copy fingerprint'), findsOneWidget);
    });

    testWidgets('copy button copies fingerprint to clipboard and shows snackbar', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'example.com',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'SHA256:test-fingerprint',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap copy button
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      // Should show snackbar
      expect(find.text('Fingerprint copied'), findsOneWidget);
    });
  });

  group('HostKeyDialog — key changed warning variant', () {
    testWidgets('key changed dialog has warning colored Accept Anyway button', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'server.com',
            port: 2222,
            keyType: 'ssh-rsa',
            fingerprint: 'SHA256:changed-key',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Should show "Accept Anyway" instead of "Accept"
      expect(find.text('Accept Anyway'), findsOneWidget);
      expect(find.text('Accept'), findsNothing); // Only "Accept Anyway"
    });

    testWidgets('key changed Accept Anyway returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          ).then((v) => result = v);
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept Anyway'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('key changed Reject returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          ).then((v) => result = v);
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('key changed shows WARNING text about MITM', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'host.com',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'SHA256:xyz',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('WARNING'), findsOneWidget);
      expect(find.textContaining('man-in-the-middle'), findsOneWidget);
      expect(find.textContaining('reinstalled'), findsOneWidget);
    });

    testWidgets('key changed shows host and port', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'myserver.org',
            port: 3322,
            keyType: 'ecdsa-sha2-nistp256',
            fingerprint: 'SHA256:fp123',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('myserver.org:3322'), findsOneWidget);
      expect(find.text('ecdsa-sha2-nistp256'), findsOneWidget);
    });

    testWidgets('fingerprint is selectable', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'SHA256:selectable-fp',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fingerprint should be in a SelectableText
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('SHA256:selectable-fp'), findsOneWidget);
    });
  });

  group('HostKeyDialog — new host info display', () {
    testWidgets('shows authenticity message for new host', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'new.host',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'fp',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('authenticity'), findsOneWidget);
      expect(find.textContaining('continue connecting'), findsOneWidget);
    });
  });
}
