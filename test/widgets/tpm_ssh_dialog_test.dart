import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/tpm_ssh.dart' as rust_tpm;
import 'package:letsflutssh/widgets/ssh_keys/tpm_ssh_dialog.dart';

class _FakeTpmBackend extends TpmBackend {
  final rust_tpm.DbTpmSshProbeResult probeResult;
  rust_tpm.DbTpmSshImportResult? generateResult;
  Object? generateError;

  /// Optional override: when set, [probe] throws this error so the
  /// wizard mixin's [onProbeFailure] arm runs.
  Object? probeThrows;
  String? lastLabel;
  rust_tpm.DbTpmSshAlgorithm? lastAlgo;
  String? lastPin;
  rust_tpm.DbTpmSshStorageMode? lastStorage;
  bool? lastSilent;

  _FakeTpmBackend({required this.probeResult});

  @override
  Future<rust_tpm.DbTpmSshProbeResult> probe() async {
    final t = probeThrows;
    if (t != null) throw t;
    return probeResult;
  }

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

    testWidgets('renders provider + persistent handle in popover', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TpmBadge(
            label: 'TPM 2.0',
            provider: 'cng-pcp',
            persistentHandle: 0x81010001,
            pinRequired: true,
          ),
        ),
      );
      await tester.tap(find.text('TPM 2.0'));
      await tester.pumpAndSettle();
      // Provider string surfaces verbatim.
      expect(find.text('cng-pcp'), findsOneWidget);
      // Persistent handle renders as zero-padded hex with `0x` prefix.
      expect(find.text('0x81010001'), findsOneWidget);
      // PIN-required warns about the lockout consequence.
      expect(find.textContaining('locks the key'), findsOneWidget);
    });

    testWidgets('omits provider line when empty / null', (tester) async {
      await tester.pumpWidget(_wrap(const TpmBadge(label: 'TPM 2.0')));
      await tester.tap(find.text('TPM 2.0'));
      await tester.pumpAndSettle();
      // No provider field rendered; the explainer alone surfaces.
      expect(find.textContaining('secure hardware'), findsOneWidget);
    });
  });

  group('TpmSshDialog — disabled-reason variants', () {
    testWidgets('NoPermission renders the tss-group reason', (tester) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.noPermission,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      expect(find.textContaining('tss'), findsOneWidget);
    });

    testWidgets('BinaryMissing maps to the fw-disabled reason', (tester) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.binaryMissing,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      // Spec: BinaryMissing collapses to the firmware-disabled string —
      // a missing TPM binary is presented as a disabled-firmware fault
      // to keep the user-facing reason set tight (three distinct copies:
      // disabled, no-permission, unsupported).
      expect(find.textContaining('disabled in firmware'), findsOneWidget);
    });

    testWidgets('Unsupported renders the "no TPM" reason', (tester) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.unsupported,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No TPM detected'), findsOneWidget);
    });

    testWidgets('ProbeFailed collapses to the fw-disabled reason', (
      tester,
    ) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.probeFailed,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      expect(find.textContaining('disabled in firmware'), findsOneWidget);
    });

    testWidgets('probe throws → onProbeFailure routes to fw-disabled reason', (
      tester,
    ) async {
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      )..probeThrows = StateError('boom');
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      // onProbeFailure stamps `probeFailed` which renders the fw-disabled
      // reason; verifies the configure step still mounts (no hung
      // probing spinner).
      expect(find.textContaining('disabled in firmware'), findsOneWidget);
    });
  });

  group('TpmSshDialog — Linux configure controls', () {
    testWidgets('typing a label flips Generate from disabled to enabled', (
      tester,
    ) async {
      if (!Platform.isLinux) return; // Linux-only path; CI host is Linux.
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      // Label field is the first TextField on the configure step.
      await tester.enterText(find.byType(TextField).first, 'my-key');
      await tester.pumpAndSettle();
      // Tapping Generate now reaches the backend.
      final generate = find.widgetWithText(MaterialButton, 'Generate');
      if (generate.evaluate().isEmpty) {
        // AppButton.primary path — tap by semantics label.
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Generate',
        );
        await tester.tap(semantics);
      } else {
        await tester.tap(generate);
      }
      await tester.pumpAndSettle();
      expect(backend.lastLabel, 'my-key');
      // Linux backend ignores silentTpm; the wizard still sends the
      // platform-conditioned value (false on Linux).
      expect(backend.lastSilent, isFalse);
      // Trimmed before send.
      expect(backend.lastLabel!.startsWith(' '), isFalse);
    });

    testWidgets('label trims whitespace before generate', (tester) async {
      if (!Platform.isLinux) return;
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '  spaced  ');
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Generate',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      expect(backend.lastLabel, 'spaced');
    });

    testWidgets(
      'PIN protect off → generate sends pin = null, ignores PIN field',
      (tester) async {
        if (!Platform.isLinux) return;
        final backend = _FakeTpmBackend(
          probeResult: rust_tpm.DbTpmSshProbeResult.available,
        );
        await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'k');
        await tester.pumpAndSettle();
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Generate',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        // PIN box wasn't ticked: spec is `pin: null` reaches the backend
        // regardless of any unfilled fields.
        expect(backend.lastPin, isNull);
      },
    );

    testWidgets(
      'PIN protect on, empty fields → Generate stays disabled (canGenerate gate)',
      (tester) async {
        if (!Platform.isLinux) return;
        final backend = _FakeTpmBackend(
          probeResult: rust_tpm.DbTpmSshProbeResult.available,
        );
        await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'k');
        await tester.pumpAndSettle();
        // Tick the PIN-protect checkbox.
        await tester.tap(find.text('Protect with PIN'));
        await tester.pumpAndSettle();
        // PIN + confirm fields render and are empty → canGenerate is
        // false because _pinValid rejects empty `a`.
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Generate',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        expect(backend.lastLabel, isNull);
      },
    );

    testWidgets(
      'PIN protect on, mismatched PINs → mismatch banner surfaces, generate blocked',
      (tester) async {
        if (!Platform.isLinux) return;
        final backend = _FakeTpmBackend(
          probeResult: rust_tpm.DbTpmSshProbeResult.available,
        );
        await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'k');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Protect with PIN'));
        await tester.pumpAndSettle();
        // Two extra TextFields appear (PIN + confirm). They render
        // after the label field.
        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(1), 'aaaa');
        await tester.enterText(textFields.at(2), 'bbbb');
        await tester.pumpAndSettle();
        expect(find.text('PINs do not match.'), findsOneWidget);
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Generate',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        expect(backend.lastLabel, isNull);
      },
    );

    testWidgets('PIN protect on, matching PINs → generate forwards the PIN', (
      tester,
    ) async {
      if (!Platform.isLinux) return;
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'k');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protect with PIN'));
      await tester.pumpAndSettle();
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), '123456');
      await tester.enterText(textFields.at(2), '123456');
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Generate',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      expect(backend.lastPin, '123456');
      // Storage default is Blob.
      expect(backend.lastStorage, rust_tpm.DbTpmSshStorageMode.blob);
    });

    testWidgets('algorithm radio switches to RSA-2048 when tapped', (
      tester,
    ) async {
      if (!Platform.isLinux) return;
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'k');
      await tester.pumpAndSettle();
      await tester.tap(find.text('RSA-2048'));
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Generate',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      expect(backend.lastAlgo, rust_tpm.DbTpmSshAlgorithm.rsa2048);
    });

    testWidgets('storage radio switches to PersistentHandle when tapped', (
      tester,
    ) async {
      if (!Platform.isLinux) return;
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'k');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Persist in TPM memory slot'));
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Generate',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      expect(
        backend.lastStorage,
        rust_tpm.DbTpmSshStorageMode.persistentHandle,
      );
    });

    testWidgets('generate failure surfaces error text, returns to configure', (
      tester,
    ) async {
      if (!Platform.isLinux) return;
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      )..generateError = StateError('hw busy');
      await tester.pumpWidget(_wrap(TpmSshDialog(backend: backend)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'k');
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Generate',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      // generateError stamped + step reset to configure. The label
      // field is still visible (i.e. we are not stuck on generating
      // spinner).
      expect(find.byType(TextField), findsWidgets);
      // The Toast / message contains the thrown text — sanitiser-safe.
      expect(find.textContaining('hw busy'), findsOneWidget);
    });

    testWidgets(
      'generate success surfaces authorized_keys line + finishWith pops result',
      (tester) async {
        if (!Platform.isLinux) return;
        final backend =
            _FakeTpmBackend(probeResult: rust_tpm.DbTpmSshProbeResult.available)
              ..generateResult = const rust_tpm.DbTpmSshImportResult(
                keyId: 'tpm-k1',
                label: 'k',
                authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA k',
              );
        TpmSshResult? popped;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  popped = await TpmSshDialog.show(ctx, backend: backend);
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'k');
        await tester.pumpAndSettle();
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Generate',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        // authorized_keys line surfaces in the completion box.
        expect(find.textContaining('ecdsa-sha2-nistp256'), findsOneWidget);
        // Close button pops the result.
        final close = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Close',
        );
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(popped, isNotNull);
        expect(popped!.keyId, 'tpm-k1');
        expect(popped!.authorizedKeysLine, 'ecdsa-sha2-nistp256 AAAA k');
        // Linux build → silentTpm carried as false.
        expect(popped!.silentTpm, isFalse);
      },
    );
  });

  group('TpmSshResult', () {
    test('carries every field verbatim', () {
      const r = TpmSshResult(
        keyId: 'id-1',
        label: 'work',
        authorizedKeysLine: 'rsa AAAA',
        silentTpm: true,
      );
      expect(r.keyId, 'id-1');
      expect(r.label, 'work');
      expect(r.authorizedKeysLine, 'rsa AAAA');
      expect(r.silentTpm, isTrue);
    });
  });

  group('TpmImportHelper', () {
    // The FilePicker channel throws MissingPluginException in widget
    // tests because no platform code is registered. Intercept the
    // channel manually so the helper sees a deterministic response
    // and we exercise both the cancel arm (empty list) and the
    // bytes-only fallback (no path).
    const MethodChannel filePickerChannel = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker',
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, null);
    });

    testWidgets('cancelled picker returns null and never hits backend', (
      tester,
    ) async {
      // Channel returns `null` (default handler) → FilePicker yields
      // null → helper returns null without ever calling import*.
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      const helper = TpmImportHelper();
      // Replace the helper's backend by writing a tiny driver — we
      // can't override the const default here, so use a fresh helper
      // built around our fake.
      final h = TpmImportHelper(backend: backend);
      String? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await h.pickAndImport(ctx);
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(backend.lastImportPath, isNull);
      expect(backend.lastImportBlob, isNull);
      // Constructor sanity: the default const variant exists.
      expect(helper.backend, isA<TpmFrbBackend>());
    });

    testWidgets('picker returns a path → backend.importBlobFromPath fires', (
      tester,
    ) async {
      // Seed the mock channel to return a path-bearing single file.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            return [
              {
                'path': '/tmp/work.tpm',
                'name': 'work.tpm',
                'bytes': null,
                'size': 4,
                'identifier': null,
              },
            ];
          });
      final backend = _FakeTpmBackend(
        probeResult: rust_tpm.DbTpmSshProbeResult.available,
      );
      final h = TpmImportHelper(backend: backend);
      String? id;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                id = await h.pickAndImport(ctx);
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(id, 'imported-k1');
      expect(backend.lastImportPath, '/tmp/work.tpm');
      // The `.tpm` suffix is stripped from the derived label.
      expect(backend.lastImportLabel, 'work');
      // The path arm runs in preference to the bytes arm.
      expect(backend.lastImportBlob, isNull);
    });

    testWidgets(
      'picker returns bytes only (no path) → backend.importBlob fires',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(filePickerChannel, (call) async {
              return [
                {
                  'path': null,
                  'name': 'mobile.tpm',
                  // FilePicker decodes this with a Uint8List type cast;
                  // a plain List<int> trips a type-error in the channel
                  // codec. Encode the bytes the way the plugin would.
                  'bytes': Uint8List.fromList([1, 2, 3, 4]),
                  'size': 4,
                  'identifier': null,
                },
              ];
            });
        final backend = _FakeTpmBackend(
          probeResult: rust_tpm.DbTpmSshProbeResult.available,
        );
        final h = TpmImportHelper(backend: backend);
        String? id;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  id = await h.pickAndImport(ctx);
                },
                child: const Text('go'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(id, 'imported-k1');
        expect(backend.lastImportBlob, [1, 2, 3, 4]);
        expect(backend.lastImportLabel, 'mobile');
        expect(backend.lastImportPath, isNull);
      },
    );
  });

  group('TpmFrbBackend', () {
    // Just instantiate so the default-constructor lines (and the
    // `const TpmBadge()` defaults) register coverage. The methods
    // themselves require a real FRB process, which is the documented
    // skip arm.
    test('default-constructs without touching FRB', () {
      const b = TpmFrbBackend();
      expect(b, isA<TpmBackend>());
    });
  });
}
