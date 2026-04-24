import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/import_flow.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = installFakePathProvider();
    installFakeSecureStorage();
  });

  tearDown(() {
    uninstallFakeSecureStorage();
    uninstallFakePathProvider(tmp);
  });

  testWidgets('showLfsImportDialog on a non-LFS file surfaces the rejection '
      'toast and exits without opening the password prompt', (tester) async {
    // `probeArchive` reads the first 4 bytes to classify. A file
    // shorter than 4 bytes short-circuits straight to
    // `LfsArchiveKind.notLfs` — the only branch that gets
    // `showLfsImportDialog` to surface the rejection toast and
    // skip the password prompt. (Anything 4+ bytes without the
    // ZIP magic is assumed to be an encrypted .lfs and would open
    // the password dialog instead.)
    final junk = File('${tmp.path}/empty.lfs')..writeAsBytesSync([0x00]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Consumer(
            builder: (ctx, ref, _) {
              return Scaffold(
                body: Builder(
                  builder: (innerCtx) => ElevatedButton(
                    onPressed: () =>
                        showLfsImportDialog(innerCtx, ref, junk.path),
                    child: const Text('trigger'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump();

    // The LfsImportDialog widget must NOT appear — probe caught
    // the file as notLfs before the password prompt could open.
    // Finding it at all would mean a regression that pushed
    // non-LFS bytes into the password-entry path.
    expect(find.text('Unlock'), findsNothing);
    expect(find.text('Import'), findsNothing);

    // Let the Toast's auto-dismiss timer fire so the widget tree
    // tears down with zero pending timers — the test framework
    // fails the test otherwise.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'handleQrImport returns silently when navigatorKey is unmounted',
    (tester) async {
      // Deep link pump can fire before the MaterialApp finishes
      // mounting — the handler resolves `navigatorKey.currentContext`
      // synchronously and must bail without throwing when it is
      // null. Pin that contract: construct an empty payload + call
      // the function without pumping any widget. No Provider
      // container required because the early-return happens before
      // any `ref.read` fires.
      const payload = ExportPayloadData(sessions: [], emptyFolders: {});

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The MaterialApp is NOT mounted, so navigatorKey.currentContext
      // is null. Call should complete without throw.
      await expectLater(handleQrImport(capturedRef, payload), completes);
    },
  );
}
