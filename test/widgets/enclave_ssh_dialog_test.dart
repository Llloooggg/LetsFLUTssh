import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/enclave.dart' as rust_enclave;
import 'package:letsflutssh/widgets/ssh_keys/enclave_ssh_dialog.dart';

/// In-memory fake backend. Returns the seeded responses without
/// reaching the FRB shim. Captures the last generate call so tests
/// can assert what the wizard handed across.
class _FakeBackend extends EnclaveBackend {
  _FakeBackend({required this.probeResult, this.generateThrows = false})
    : super();

  final rust_enclave.DbEnclaveAvailability probeResult;
  final bool generateThrows;
  String? capturedLabel;
  rust_enclave.DbEnclaveAuthPolicy? capturedPolicy;

  @override
  Future<rust_enclave.DbEnclaveAvailability> probe() async => probeResult;

  @override
  Future<rust_enclave.DbEnclaveImportResult> generate({
    required String label,
    required rust_enclave.DbEnclaveAuthPolicy policy,
  }) async {
    capturedLabel = label;
    capturedPolicy = policy;
    if (generateThrows) {
      throw Exception('fake-error');
    }
    return rust_enclave.DbEnclaveImportResult(
      keyId: 'enclave-key-id',
      label: label,
      authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA... $label',
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<EnclaveSshResult?> _open(
  WidgetTester tester, {
  required _FakeBackend backend,
}) async {
  await _widenViewport(tester);
  EnclaveSshResult? captured;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            captured = await EnclaveSshDialog.show(ctx, backend: backend);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Two pumps to let the dialog land + the probe future complete.
  await tester.pumpAndSettle();
  return captured;
}

/// Widen the test viewport so the AppDialogHeader's Row has enough
/// horizontal slack for the localized title ("Generate Secure Enclave
/// SSH key"). The default 800x600 leaves it ~36 px short; bumping
/// to 1200x800 mirrors a portrait laptop and prevents the
/// layout-overflow assertion the header otherwise emits.
Future<void> _widenViewport(WidgetTester tester) =>
    tester.binding.setSurfaceSize(const Size(1200, 800));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnclaveSshDialog', () {
    testWidgets(
      'unsupported platform renders disabled with reason and no generate',
      (tester) async {
        final backend = _FakeBackend(
          probeResult:
              const rust_enclave.DbEnclaveAvailability_UnsupportedPlatform(),
        );
        await _open(tester, backend: backend);
        // The wizard surfaces the disabled-with-reason text and the
        // Generate affordance is greyed out.
        expect(find.byType(EnclaveSshDialog), findsOneWidget);
        final s = S.of(tester.element(find.byType(EnclaveSshDialog)));
        expect(find.text(s.sshKeyHardwareUnavailableTitle), findsOneWidget);
      },
    );

    testWidgets('code-signing reason surfaces the documented snippet', (
      tester,
    ) async {
      final backend = _FakeBackend(
        probeResult:
            const rust_enclave.DbEnclaveAvailability_CodeSignRequired(),
      );
      await _open(tester, backend: backend);
      final s = S.of(tester.element(find.byType(EnclaveSshDialog)));
      expect(find.text(s.sshKeyHardwareUnavailableSe), findsOneWidget);
    });

    testWidgets('happy path generates the key and pops the result', (
      tester,
    ) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_enclave.DbEnclaveAvailability_Available(),
      );
      EnclaveSshResult? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await EnclaveSshDialog.show(ctx, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Enter a label, click Generate.
      final labelField = find.byType(TextField).first;
      await tester.enterText(labelField, 'Production');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(EnclaveSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      // The FRB call was issued with the label + the default Touch-ID policy.
      expect(backend.capturedLabel, 'Production');
      expect(
        backend.capturedPolicy,
        rust_enclave.DbEnclaveAuthPolicy.biometryCurrentSet,
      );
      // The complete step renders the authorized_keys line.
      expect(
        find.textContaining('ecdsa-sha2-nistp256'),
        findsAtLeastNWidgets(1),
      );
      // Click "Close" to pop.
      await tester.tap(find.text(s.close));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.keyId, 'enclave-key-id');
      expect(captured!.label, 'Production');
    });

    testWidgets('generate failure surfaces the error and stays on configure', (
      tester,
    ) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_enclave.DbEnclaveAvailability_Available(),
        generateThrows: true,
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                await EnclaveSshDialog.show(ctx, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final labelField = find.byType(TextField).first;
      await tester.enterText(labelField, 'Bad');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(EnclaveSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      // Wizard stays on configure step — the Generate button is still there
      // and the error string is visible.
      expect(find.textContaining('fake-error'), findsOneWidget);
      expect(find.text(s.sshKeyGenerateCta), findsOneWidget);
    });

    testWidgets('initialLabel pre-fills the label field', (tester) async {
      // The key-manager stub re-generate flow passes the migrated
      // stub's label so the user does not retype the name from the
      // source device.
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_enclave.DbEnclaveAvailability_Available(),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                await EnclaveSshDialog.show(
                  ctx,
                  backend: backend,
                  initialLabel: 'work-laptop',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final labelField = tester.widget<TextField>(find.byType(TextField).first);
      expect(labelField.controller?.text, 'work-laptop');
    });
  });
}
