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

  group('HostKeyDialog — new host', () {
    testWidgets('shows Unknown Host title', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'example.com',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'SHA256:abc123',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Unknown Host'), findsOneWidget);
    });

    testWidgets('shows host:port and key type', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'example.com',
            port: 2222,
            keyType: 'ssh-rsa',
            fingerprint: 'SHA256:xyz',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('example.com:2222'), findsOneWidget);
      expect(find.text('ssh-rsa'), findsOneWidget);
      expect(find.text('SHA256:xyz'), findsOneWidget);
    });

    testWidgets('Accept returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'fp',
          ).then((v) => result = v);
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('Reject returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'ssh-ed25519',
            fingerprint: 'fp',
          ).then((v) => result = v);
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('shows shield icon for new host', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showNewHost(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });
  });

  group('HostKeyDialog — key changed', () {
    testWidgets('shows Host Key Changed title', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'server.com',
            port: 22,
            keyType: 'ssh-rsa',
            fingerprint: 'SHA256:new-key',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Host Key Changed!'), findsOneWidget);
    });

    testWidgets('shows warning icon for changed key', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows MITM warning text', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('man-in-the-middle'), findsOneWidget);
    });

    testWidgets('Accept Anyway button present for changed key', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) {
          HostKeyDialog.showKeyChanged(
            ctx,
            host: 'h',
            port: 22,
            keyType: 'k',
            fingerprint: 'f',
          );
        },
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Accept Anyway'), findsOneWidget);
    });
  });
}
