import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/keystore_ssh.dart' as rust_ks;
import 'package:letsflutssh/widgets/keystore_ssh_dialog.dart';

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
  });
}
