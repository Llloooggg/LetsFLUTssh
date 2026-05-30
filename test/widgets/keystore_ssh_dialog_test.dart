import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/keystore_ssh.dart' as rust_ks;
import 'package:letsflutssh/widgets/ssh_keys/keystore_ssh_dialog.dart';

class _FakeKeystoreBackend extends KeystoreBackend {
  final rust_ks.DbKeystoreProbeResult probeResult;

  /// Outcomes the wizard will receive on successive `generate` calls.
  /// The wizard's StrongBox-fallback flow makes two calls: the first
  /// with `strongbox: true` (the user's toggle), the second with
  /// `strongbox: false` after the user accepts the TEE fallback.
  final List<rust_ks.DbKeystoreGenerateOutcome> outcomes;
  Object? generateError;
  final List<_GenerateCall> calls = [];

  _FakeKeystoreBackend({required this.probeResult, this.outcomes = const []});

  @override
  Future<rust_ks.DbKeystoreProbeResult> probe() async => probeResult;

  @override
  Future<rust_ks.DbKeystoreGenerateOutcome> generate({
    required String label,
    required rust_ks.DbKeystoreAlgo algo,
    required bool strongbox,
  }) async {
    calls.add(_GenerateCall(label: label, algo: algo, strongbox: strongbox));
    if (generateError != null) {
      throw generateError!;
    }
    if (calls.length <= outcomes.length) {
      return outcomes[calls.length - 1];
    }
    return rust_ks.DbKeystoreGenerateOutcome.generated(
      rust_ks.DbKeystoreImportResult(
        keyId: 'kid-${calls.length}',
        label: label,
        authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA $label',
        strongbox: strongbox,
        platform: 'Pixel 8 (Android 14)',
      ),
    );
  }
}

class _GenerateCall {
  final String label;
  final rust_ks.DbKeystoreAlgo algo;
  final bool strongbox;
  _GenerateCall({
    required this.label,
    required this.algo,
    required this.strongbox,
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(body: Builder(builder: (ctx) => child)),
  );
}

void main() {
  group('KeystoreSshDialog', () {
    testWidgets('renders disabled-with-reason when biometric is not enrolled', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.biometricNotEnrolled(),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enrol biometric'), findsOneWidget);
    });

    testWidgets('renders configure step when probe is Available', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ECDSA P-256'), findsOneWidget);
      expect(find.textContaining('Ed25519'), findsOneWidget);
      expect(find.textContaining('RSA-2048'), findsOneWidget);
    });

    testWidgets(
      'switching to Ed25519 surfaces StrongBox-unavailable subtitle',
      (tester) async {
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.available(
            strongboxAvailable: true,
          ),
        );
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // Tap the Ed25519 radio label.
        await tester.tap(find.textContaining('Ed25519'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('StrongBox HSM not available'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Generate calls the backend with the chosen algorithm', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'work-laptop');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      expect(backend.calls, hasLength(1));
      expect(backend.calls.first.label, 'work-laptop');
      expect(backend.calls.first.algo, rust_ks.DbKeystoreAlgo.ecdsaP256);
      // StrongBox toggle defaults on; backend receives `true` because
      // the probe reported the feature.
      expect(backend.calls.first.strongbox, isTrue);
    });

    testWidgets('StrongBox-unavailable surfaces the confirmation dialog', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
        outcomes: const [
          rust_ks.DbKeystoreGenerateOutcome.strongBoxUnavailable(),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'work-laptop');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      expect(find.text(s.keystoreStrongBoxFallbackTitle), findsOneWidget);
      expect(find.text(s.keystoreStrongBoxFallbackBody), findsOneWidget);
      expect(find.text(s.keystoreStrongBoxFallbackConfirm), findsOneWidget);
      // Two Cancel buttons share the same localized string — the
      // wizard's own Cancel + the fallback dialog's Cancel. Scoping
      // by the fallback-dialog title's ancestor disambiguates.
      final fallbackCancel = find.descendant(
        of: find.ancestor(
          of: find.text(s.keystoreStrongBoxFallbackTitle),
          matching: find.byType(Dialog),
        ),
        matching: find.text(s.keystoreStrongBoxFallbackCancel),
      );
      expect(fallbackCancel, findsOneWidget);
    });

    testWidgets('Tapping Use TEE re-invokes generate with strongbox = false', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
        outcomes: const [
          rust_ks.DbKeystoreGenerateOutcome.strongBoxUnavailable(),
          rust_ks.DbKeystoreGenerateOutcome.generated(
            rust_ks.DbKeystoreImportResult(
              keyId: 'kid-tee',
              label: 'work-laptop',
              authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA work-laptop',
              strongbox: false,
              platform: 'Pixel 8 (Android 14)',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'work-laptop');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      // Confirm the fallback.
      await tester.tap(find.text(s.keystoreStrongBoxFallbackConfirm));
      await tester.pumpAndSettle();
      expect(backend.calls, hasLength(2));
      expect(backend.calls[0].strongbox, isTrue);
      expect(backend.calls[1].strongbox, isFalse);
      expect(backend.calls[1].label, 'work-laptop');
    });

    testWidgets('Tapping Cancel returns to the wizard without creating a key', (
      tester,
    ) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
        outcomes: const [
          rust_ks.DbKeystoreGenerateOutcome.strongBoxUnavailable(),
        ],
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'work-laptop');
      await tester.pumpAndSettle();
      final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
      await tester.tap(find.text(s.sshKeyGenerateCta));
      await tester.pumpAndSettle();
      // Scope the Cancel tap to the fallback dialog — the wizard's
      // own Cancel button shares the same localized string.
      final fallbackCancel = find.descendant(
        of: find.ancestor(
          of: find.text(s.keystoreStrongBoxFallbackTitle),
          matching: find.byType(Dialog),
        ),
        matching: find.text(s.keystoreStrongBoxFallbackCancel),
      );
      await tester.tap(fallbackCancel);
      await tester.pumpAndSettle();
      // Only the first call landed; the wizard returns to the
      // configure step without a second generate.
      expect(backend.calls, hasLength(1));
      // Wizard is still open + the configure step is visible.
      expect(find.byType(KeystoreSshDialog), findsOneWidget);
      expect(find.textContaining('ECDSA P-256'), findsOneWidget);
    });

    testWidgets('initialLabel pre-fills the label field', (tester) async {
      final backend = _FakeKeystoreBackend(
        probeResult: const rust_ks.DbKeystoreProbeResult.available(
          strongboxAvailable: true,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => KeystoreSshDialog.show(
                ctx,
                backend: backend,
                initialLabel: 'work-laptop',
              ),
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

  group('KeystoreBadge', () {
    testWidgets('StrongBox row renders the badge label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Center(
            child: KeystoreBadge(
              label: 'Android Keystore',
              strongbox: true,
              platform: 'Pixel 8 (Android 14)',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Android Keystore'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'TEE variant (strongbox = false, platform = null) renders the label '
      'without crashing on the optional platform line',
      (tester) async {
        // Spec: `KeystoreBadge` accepts a nullable `platform`; the
        // popover line is conditional on `plat != null && plat.isNotEmpty`.
        // Passing strongbox = false with a null platform pins the
        // TEE branch + missing-platform conditional — both arms exercise
        // the pill build without the StrongBox-specific lines.
        await tester.pumpWidget(
          _wrap(const Center(child: KeystoreBadge(label: 'Android Keystore'))),
        );
        await tester.pumpAndSettle();
        expect(find.text('Android Keystore'), findsAtLeastNWidgets(1));
      },
    );
  });

  group('KeystoreSshDialog — deepening', () {
    testWidgets(
      'Unsupported probe surfaces the Android-label fallback reason and the '
      'Generate CTA is disabled (canGenerate is false on non-Available probe)',
      (tester) async {
        // Spec: `_availabilityReason` falls back to
        // `keystoreKeyAndroidLabel` when the probe variant is
        // Unsupported (non-Android build / lower-than-min SDK). The
        // configure step renders the red disabled-with-reason container
        // and `canGenerate` short-circuits on `!_isAvailable` so the
        // primary CTA stays disabled even after the label is typed.
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.unsupported(),
        );
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // `canGenerate` short-circuits on `!_isAvailable`; the primary
        // CTA renders with `onTap: null` so the tap is a no-op. The
        // backend never sees a generate call.
        final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
        await tester.tap(find.text(s.sshKeyGenerateCta));
        await tester.pumpAndSettle();
        expect(backend.calls, isEmpty);
      },
    );

    testWidgets(
      'Other-variant probe surfaces the carrier string as the localized reason',
      (tester) async {
        // Spec: the Other-variant probe routes its `field0` payload
        // straight into the disabled-with-reason text — this lets the
        // FRB layer ship a localized error string from the Rust side
        // without the dialog needing to know the cause. Pins the
        // pass-through branch of `_availabilityReason`.
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.other(
            'AndroidKeyStore JNI not available in this process',
          ),
        );
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('AndroidKeyStore JNI not available'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'StrongBox toggle is disabled when the probe reports the feature is '
      'unavailable, even on a StrongBox-eligible algorithm',
      (tester) async {
        // Spec: `_strongBoxToggleEnabled` AND's
        // `_strongBoxFeature && _algoStrongBoxEligible`. With
        // `strongboxAvailable: false`, the toggle must render the
        // unavailable subtitle copy regardless of the chosen algorithm
        // (ECDSA P-256 default is StrongBox-eligible per algorithm).
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.available(
            strongboxAvailable: false,
          ),
        );
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // The "not available" subtitle copy renders under the toggle.
        expect(
          find.textContaining('StrongBox HSM not available'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a generate that throws keeps the wizard on configure and surfaces the '
      'error tail in the localized red text',
      (tester) async {
        // Spec: `runGenerateFlow` (in the shared mixin) catches the
        // throw, assigns the message to `generateError`, and re-renders
        // the configure step. The red error line appears below the
        // algorithm radio. Pins the throwing arm — distinct from the
        // StrongBox-fallback (typed) outcome arm covered above.
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.available(
            strongboxAvailable: true,
          ),
        )..generateError = Exception('fake-keystore-error');
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'fail-label');
        await tester.pumpAndSettle();
        final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
        await tester.tap(find.text(s.sshKeyGenerateCta));
        await tester.pumpAndSettle();
        // The Exception's toString tail is surfaced verbatim. The
        // dialog is still on the configure step (Generate CTA visible).
        expect(find.textContaining('fake-keystore-error'), findsOneWidget);
        expect(find.text(s.sshKeyGenerateCta), findsOneWidget);
      },
    );

    testWidgets(
      'completion of a TEE-tier generate (strongbox: false) renders the TEE '
      'label in the complete step',
      (tester) async {
        // Spec: `buildComplete` chooses between the StrongBox label
        // and the TEE label off `_result.strongbox`. The seeded
        // outcome here is StrongBoxUnavailable then the user accepts
        // the fallback — generate succeeds with `strongbox: false`.
        // Pins the TEE-label arm of the complete step.
        final backend = _FakeKeystoreBackend(
          probeResult: const rust_ks.DbKeystoreProbeResult.available(
            strongboxAvailable: true,
          ),
          outcomes: const [
            rust_ks.DbKeystoreGenerateOutcome.strongBoxUnavailable(),
            rust_ks.DbKeystoreGenerateOutcome.generated(
              rust_ks.DbKeystoreImportResult(
                keyId: 'kid-tee-2',
                label: 'tee-only',
                authorizedKeysLine: 'ecdsa-sha2-nistp256 AAAA tee-only',
                strongbox: false,
                platform: 'Pixel 4a (Android 13)',
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => KeystoreSshDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'tee-only');
        await tester.pumpAndSettle();
        final s = S.of(tester.element(find.byType(KeystoreSshDialog)));
        await tester.tap(find.text(s.sshKeyGenerateCta));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.keystoreStrongBoxFallbackConfirm));
        await tester.pumpAndSettle();
        // The complete step renders the TEE label; the StrongBox
        // label belongs to the strongbox = true arm.
        expect(find.text(s.keystoreKeyTeeLabel), findsOneWidget);
      },
    );
  });
}
