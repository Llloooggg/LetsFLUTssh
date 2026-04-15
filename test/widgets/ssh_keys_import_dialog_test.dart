import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/ssh_dir_key_scanner.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/ssh_keys_import_dialog.dart';

void main() {
  ScannedKey scan(String path) => ScannedKey(
    path: path,
    pem: 'PRIVATE KEY',
    suggestedLabel: _baseName(path),
  );

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('SshKeysImportDialog', () {
    testWidgets('renders empty state and disables primary button', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SshKeysImportDialog(candidates: [])));
      await tester.pump();
      expect(find.text('No private keys found in ~/.ssh.'), findsOneWidget);
    });

    testWidgets('lists every candidate', (tester) async {
      final keys = [
        scan('/home/u/.ssh/id_ed25519'),
        scan('/home/u/.ssh/work_rsa'),
      ];
      await tester.pumpWidget(wrap(SshKeysImportDialog(candidates: keys)));
      await tester.pump();
      expect(find.text('id_ed25519'), findsOneWidget);
      expect(find.text('work_rsa'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets('marks already-imported keys and unchecks them by default', (
      tester,
    ) async {
      final keys = [
        scan('/home/u/.ssh/new_key'),
        const ScannedKey(
          path: '/home/u/.ssh/old_key',
          pem: 'PRIVATE KEY existing',
          suggestedLabel: 'old_key',
        ),
      ];
      final existingFps = {
        KeyStore.privateKeyFingerprint('PRIVATE KEY existing'),
      };

      List<ScannedKey>? captured;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await SshKeysImportDialog.show(
                    context,
                    candidates: keys,
                    existingFingerprints: existingFps,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Existing key shows the badge.
      expect(find.text('already in store'), findsOneWidget);

      // Submit without changing selections — only the new key should come back.
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.map((k) => k.suggestedLabel), ['new_key']);
    });

    testWidgets('returns only checked candidates on submit', (tester) async {
      final keys = [
        scan('/home/u/.ssh/id_ed25519'),
        scan('/home/u/.ssh/work_rsa'),
      ];
      List<ScannedKey>? captured;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await SshKeysImportDialog.show(
                    context,
                    candidates: keys,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Uncheck the second row by tapping its Checkbox.
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pump();

      // Tap the primary Import button.
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.map((k) => k.suggestedLabel), ['id_ed25519']);
    });
  });
}

String _baseName(String path) {
  final idx = path.lastIndexOf('/');
  return idx < 0 ? path : path.substring(idx + 1);
}
