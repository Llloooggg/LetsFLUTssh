import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/paste_import_link_dialog.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  String buildSamplePayload() {
    final session = Session(
      id: 'sess-paste',
      label: 'paste-host',
      folder: '',
      server: const ServerAddress(host: 'h', port: 22, user: 'u'),
      auth: const SessionAuth(authType: AuthType.password),
    );
    return encodeExportPayload(
      [session],
      input: const ExportPayloadInput(
        options: ExportOptions(includeSessions: true, includeConfig: false),
      ),
    );
  }

  group('PasteImportLinkDialog', () {
    testWidgets('decodes a letsflutssh:// URL and pops the payload', (
      tester,
    ) async {
      final payload = buildSamplePayload();
      final url = wrapInDeepLink(payload);

      ExportPayloadData? received;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                received = await PasteImportLinkDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), url);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.sessions, hasLength(1));
      expect(received!.sessions.first.label, 'paste-host');
    });

    testWidgets('also decodes the raw payload without the URL wrapper', (
      tester,
    ) async {
      final payload = buildSamplePayload();

      ExportPayloadData? received;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                received = await PasteImportLinkDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), payload);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.sessions, hasLength(1));
    });

    testWidgets('invalid input surfaces an error and keeps the dialog open', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PasteImportLinkDialog.show(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'not a payload');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Dialog still shown, error rendered.
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Link does not contain a valid LetsFLUTssh payload'),
        findsOneWidget,
      );
    });

    testWidgets('paste-from-clipboard button copies text into the field', (
      tester,
    ) async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'hello-clipboard'};
          }
          return null;
        },
      );
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PasteImportLinkDialog.show(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste from clipboard'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'hello-clipboard');
    });
  });

  // Silence "unused" complaint from AppConfig-less imports.
  AppConfig.defaults.toJson;
}
