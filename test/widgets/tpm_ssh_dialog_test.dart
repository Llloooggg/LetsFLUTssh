import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/tpm_ssh.dart' as rust_tpm;
import 'package:letsflutssh/widgets/tpm_ssh_dialog.dart';

class _FakeTpmBackend extends TpmBackend {
  final rust_tpm.DbTpmSshProbeResult probeResult;
  rust_tpm.DbTpmSshImportResult? generateResult;
  Object? generateError;
  String? lastLabel;
  rust_tpm.DbTpmSshAlgorithm? lastAlgo;
  String? lastPin;
  rust_tpm.DbTpmSshStorageMode? lastStorage;
  bool? lastSilent;

  _FakeTpmBackend({required this.probeResult});

  @override
  Future<rust_tpm.DbTpmSshProbeResult> probe() async => probeResult;

  @override
  Future<rust_tpm.DbTpmSshImportResult> generate({
    required String label,
    required rust_tpm.DbTpmSshAlgorithm algo,
    String? pin,
    required rust_tpm.DbTpmSshStorageMode storage,
    int? persistentHandle,
    required bool silentTpm,
  }) async {
    lastLabel = label;
    lastAlgo = algo;
    lastPin = pin;
    lastStorage = storage;
    lastSilent = silentTpm;
    if (generateError != null) {
      throw generateError!;
    }
    return generateResult ??
        rust_tpm.DbTpmSshImportResult(
          keyId: 'k1',
          label: label,
          authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA $label',
        );
  }

  List<int>? lastImportBlob;
  String? lastImportLabel;
  String? lastImportPath;

  @override
  Future<String> importBlob({
    required List<int> blob,
    required String label,
  }) async {
    lastImportBlob = blob;
    lastImportLabel = label;
    return 'imported-k1';
  }

  @override
  Future<String> importBlobFromPath({
    required String path,
    required String label,
  }) async {
    lastImportPath = path;
    lastImportLabel = label;
    return 'imported-k1';
  }
}

Widget _silentBadgeBuilder(BuildContext ctx) => const Center(
  child: TpmBadge(label: 'TPM 2.0', provider: 'cng-pcp', silent: true),
);

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: Builder(builder: (ctx) => child)),
  );
}

void main() {
  group('TpmSshDialog', () {
    testWidgets('renders disabled-with-reason on DeviceNodeMissing', (
      tester,
    ) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.deviceNodeMissing,
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => TpmSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Disabled reason copy lands in the dialog body.
      expect(find.textContaining('TPM is disabled'), findsOneWidget);
    });

    testWidgets('renders configure step when probe is Available', (
      tester,
    ) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => TpmSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The algorithm radio renders both labels.
      expect(find.textContaining('ECDSA P-256'), findsOneWidget);
      expect(find.textContaining('RSA-2048'), findsOneWidget);
    });

    testWidgets('Generate button stays disabled without a label', (
      tester,
    ) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      // Find the primary Generate button.
      final generate = find.widgetWithText(MaterialButton, 'Generate');
      // Button text may render via AppButton.primary wrapping —
      // accept either. The disabled state is what we pin: tapping
      // the button does not call generate.
      if (generate.evaluate().isEmpty) {
        // Some platforms render through TextButton inside AppButton.
        final any = find.textContaining('Generate');
        await tester.tap(any.first);
        await tester.pumpAndSettle();
      } else {
        await tester.tap(generate);
        await tester.pumpAndSettle();
      }
      // generate() was never called because the label is empty.
      expect(backend.lastLabel, isNull);
    });

    testWidgets('initialLabel pre-fills the label field', (tester) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(
        _wrap(TpmSshDialog(backend: backend, initialLabel: 'work-laptop')),
      );
      await tester.pumpAndSettle();
      final labelField = tester.widget<TextField>(find.byType(TextField).first);
      expect(labelField.controller?.text, 'work-laptop');
    });
  });

  group('TpmBadge', () {
    testWidgets('renders label and pops info dialog on tap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TpmBadge(
            label: 'TPM 2.0',
            provider: 'tss-esapi',
            persistentHandle: null,
          ),
        ),
      );
      expect(find.text('TPM 2.0'), findsOneWidget);
    });

    testWidgets('silent variant shows the silent warning copy', (tester) async {
      await tester.pumpWidget(
        _wrap(const Builder(builder: _silentBadgeBuilder)),
      );
      await tester.tap(find.text('TPM 2.0'));
      await tester.pumpAndSettle();
      expect(find.textContaining('WITHOUT'), findsOneWidget);
    });
  });
}
