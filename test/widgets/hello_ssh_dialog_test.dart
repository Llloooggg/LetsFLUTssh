import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/hello.dart' as rust_hello;
import 'package:letsflutssh/widgets/ssh_keys/hello_ssh_dialog.dart';

/// In-memory fake backend. Returns the seeded probe result without
/// reaching FRB; captures the last generate call so tests can pin
/// what the wizard handed across the boundary.
class _FakeBackend extends HelloBackend {
  _FakeBackend({required this.probeResult, this.generateThrows = false})
    : super();

  final rust_hello.DbHelloProbeResult probeResult;
  final bool generateThrows;
  String? capturedLabel;
  rust_hello.DbHelloAlgo? capturedAlgo;

  @override
  Future<rust_hello.DbHelloProbeResult> probe() async => probeResult;

  @override
  Future<rust_hello.DbHelloImportResult> generate({
    required String label,
    required rust_hello.DbHelloAlgo algo,
  }) async {
    capturedLabel = label;
    capturedAlgo = algo;
    if (generateThrows) {
      throw Exception('fake-hello-error');
    }
    return rust_hello.DbHelloImportResult(
      keyId: 'hello-key-id',
      label: label,
      authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA... $label',
      tier: rust_hello.DbHelloTpmTier.hardware,
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _widenViewport(WidgetTester tester) =>
    tester.binding.setSurfaceSize(const Size(1200, 800));

Future<HelloSshResult?> _open(
  WidgetTester tester, {
  required _FakeBackend backend,
}) async {
  await _widenViewport(tester);
  HelloSshResult? captured;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            captured = await HelloSshDialog.show(ctx, backend: backend);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HelloSshDialog', () {
    testWidgets(
      'unsupported platform renders disabled with reason and no generate',
      (tester) async {
        final backend = _FakeBackend(
          probeResult: const rust_hello.DbHelloProbeResult_Unsupported(),
        );
        await _open(tester, backend: backend);
        expect(find.byType(HelloSshDialog), findsOneWidget);
        final s = S.of(tester.element(find.byType(HelloSshDialog)));
        expect(find.text(s.sshKeyHardwareUnavailableTitle), findsOneWidget);
      },
    );

    testWidgets('hello-not-configured surfaces the configure-first reason', (
      tester,
    ) async {
      final backend = _FakeBackend(
        probeResult: const rust_hello.DbHelloProbeResult_HelloNotConfigured(),
      );
      await _open(tester, backend: backend);
      final s = S.of(tester.element(find.byType(HelloSshDialog)));
      expect(find.text(s.helloConfigureFirst), findsOneWidget);
    });

    testWidgets('software-KSP tier surfaces the honest-label warning', (
      tester,
    ) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_hello.DbHelloProbeResult_Available(
          tier: rust_hello.DbHelloTpmTier.softwareKsp,
        ),
      );
      await _open(tester, backend: backend);
      final s = S.of(tester.element(find.byType(HelloSshDialog)));
      // The wizard renders the localized "Software-gated" pill so the
      // user knows the key is not TPM-backed.
      expect(
        find.textContaining(s.sshKeyHardwareUnavailableTier),
        findsOneWidget,
      );
    });

    testWidgets('happy path generates with default ECDSA P-256 and pops', (
      tester,
    ) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_hello.DbHelloProbeResult_Available(
          tier: rust_hello.DbHelloTpmTier.hardware,
        ),
      );
      HelloSshResult? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await HelloSshDialog.show(ctx, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final labelField = find.byType(TextField).first;
      await tester.enterText(labelField, 'work-laptop');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(HelloSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      expect(backend.capturedLabel, 'work-laptop');
      expect(backend.capturedAlgo, rust_hello.DbHelloAlgo.ecdsaP256);
      expect(
        find.textContaining('ecdsa-sha2-nistp256'),
        findsAtLeastNWidgets(1),
      );
      await tester.tap(find.text(s.close));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.keyId, 'hello-key-id');
      expect(captured!.label, 'work-laptop');
      expect(captured!.tier, rust_hello.DbHelloTpmTier.hardware);
    });

    testWidgets('generate failure surfaces the error and stays on configure', (
      tester,
    ) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_hello.DbHelloProbeResult_Available(
          tier: rust_hello.DbHelloTpmTier.hardware,
        ),
        generateThrows: true,
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                await HelloSshDialog.show(ctx, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final labelField = find.byType(TextField).first;
      await tester.enterText(labelField, 'broken');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(HelloSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      expect(find.textContaining('fake-hello-error'), findsOneWidget);
      expect(find.text(s.sshKeyGenerateCta), findsOneWidget);
    });

    testWidgets('initialLabel pre-fills the label field', (tester) async {
      await _widenViewport(tester);
      final backend = _FakeBackend(
        probeResult: const rust_hello.DbHelloProbeResult_Available(
          tier: rust_hello.DbHelloTpmTier.hardware,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                await HelloSshDialog.show(
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

  group('HelloBadge', () {
    testWidgets('renders pill with the localized label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HelloBadge(
            label: 'Windows Hello',
            credentialName: 'letsflutssh-ssh-abc-1234',
          ),
        ),
      );
      expect(find.text('Windows Hello'), findsOneWidget);
    });
  });
}
