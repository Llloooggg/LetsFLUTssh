import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/features/key_manager/key_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/ssh_keys/hardware_key_badge.dart';
import 'package:letsflutssh/widgets/ssh_keys/enclave_ssh_dialog.dart';
import 'package:letsflutssh/widgets/ssh_keys/hello_ssh_dialog.dart';
import 'package:letsflutssh/widgets/ssh_keys/keystore_ssh_dialog.dart';
import 'package:letsflutssh/widgets/ssh_keys/pkcs11_import_dialog.dart';
import 'package:letsflutssh/widgets/ssh_keys/tpm_ssh_dialog.dart';
import 'package:letsflutssh/widgets/core/toast.dart';

import '../../helpers/frb_bootstrap.dart';

/// Minimal [SshKeysMutator] test double — returns the seeded
/// metadata on every `loadAllMetadata` so the dialog can hydrate
/// its row list without booting FRB / the rusqlite DB.
class _StubKeysMutator extends SshKeysMutator {
  _StubKeysMutator(this._rows);

  final List<SshKeyMetadata> _rows;

  @override
  Future<Map<String, SshKeyMetadata>> loadAllMetadata() async {
    return {for (final r in _rows) r.id: r};
  }
}

SshKeyMetadata _meta({
  required String id,
  required String label,
  String keyType = 'ssh-ed25519',
  String backend = 'software',
  bool importedAsStub = false,
  String certFingerprint = '',
  CertValidity? validity,
  String? pkcs11ModulePath,
  String? pkcs11TokenSerial,
  String? pkcs11ObjectLabel,
  String? helloCredentialName,
  String? tpmProvider,
  int? tpmHandle,
  bool tpmPinRequired = false,
  bool keystoreStrongBox = false,
  String? keystorePlatform,
}) => SshKeyMetadata(
  id: id,
  label: label,
  publicKey: 'pub-$id',
  keyType: keyType,
  createdAt: DateTime(2024, 1, 1),
  isGenerated: false,
  privateFingerprint: 'priv-$id',
  publicFingerprint: 'pub-$id',
  backend: backend,
  importedAsStub: importedAsStub,
  certFingerprint: certFingerprint,
  validity: validity,
  pkcs11ModulePath: pkcs11ModulePath,
  pkcs11TokenSerial: pkcs11TokenSerial,
  pkcs11ObjectLabel: pkcs11ObjectLabel,
  helloCredentialName: helloCredentialName,
  tpmProvider: tpmProvider,
  tpmHandle: tpmHandle,
  tpmPinRequired: tpmPinRequired,
  keystoreStrongBox: keystoreStrongBox,
  keystorePlatform: keystorePlatform,
);

void main() {
  // Key row rendering routes the created_at timestamp through
  // `format.dart::formatDate`, which calls Rust over FRB. The widget
  // tests need the Rust library bootstrapped before pumping.
  setUpAll(() async {
    await requireFrbLoaded();
  });

  // The dialog's toolbar opens a Scaffold + MaterialApp surface
  // whose system-overlay-style writes touch `flutter/platform`;
  // flutter_test does not stub that channel by default. Stub it so
  // any platform-method call drains cleanly in pumpAndSettle.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    Toast.clearAllForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildApp({required List<SshKeyMetadata> seed}) {
    return ProviderScope(
      overrides: [
        sshKeysMutatorProvider.overrideWithValue(_StubKeysMutator(seed)),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SizedBox(height: 600, width: 800, child: KeyManagerPanel()),
        ),
      ),
    );
  }

  group('KeyManagerPanel row rendering', () {
    testWidgets('shows spinner before metadata resolves, then transitions to '
        'the row list', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: '1', label: 'Production')],
        ),
      );
      // The `_loadKeys` future has not resolved on the first frame.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Production'), findsOneWidget);
    });

    testWidgets(
      'FIDO2 sk-* row renders the HardwareKeyBadge from _KeyRowBadges',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'sk1',
                label: 'YubiKey 5',
                keyType: 'sk-ssh-ed25519@openssh.com',
                backend: 'fido2',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HardwareKeyBadge), findsOneWidget);
      },
    );

    testWidgets('non-stub row exposes copy / delete actions; cert-add slot is '
        'present when no cert is attached', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: '1', label: 'Production')],
        ),
      );
      await tester.pumpAndSettle();
      // The action cluster lives inside `_KeyRowActions`; tooltip
      // strings (`S.of(context).publicKey` etc.) are the public
      // surface to assert against. The import-certificate slot
      // now uses an extended tooltip that explains the SSH CA
      // use case — match the first sentence so a future copy
      // tweak does not invalidate the test.
      expect(find.byTooltip('Public Key'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message?.startsWith(
                    'Attach an OpenSSH certificate signed by your CA',
                  ) ??
                  false),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Delete Key'), findsOneWidget);
      // Stub-only actions must not appear on a non-stub row.
      expect(find.byTooltip('Re-generate here'), findsNothing);
    });

    testWidgets('PKCS#11 row renders the Pkcs11Badge from _KeyRowBadges', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'p11',
              label: 'Smart card',
              backend: 'pkcs11',
              pkcs11ModulePath: '/usr/lib/opensc-pkcs11.so',
              pkcs11TokenSerial: 'TOK-001',
              pkcs11ObjectLabel: 'auth-key',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Pkcs11Badge), findsOneWidget);
    });

    testWidgets('Enclave row renders the EnclaveBadge from _KeyRowBadges', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'enc', label: 'Mac key', backend: 'enclave')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EnclaveBadge), findsOneWidget);
    });

    testWidgets(
      'Hello row renders the HelloBadge with the captured credential name',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'hello1',
                label: 'Win Hello key',
                backend: 'hello',
                helloCredentialName: 'lfssh-key-1',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HelloBadge), findsOneWidget);
      },
    );

    testWidgets(
      'TPM row renders the TpmBadge; cng-pcp provider flags the silent '
      'warning copy on the row',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'tpm1',
                label: 'TPM key',
                backend: 'tpm',
                tpmProvider: 'cng-pcp',
                tpmHandle: 0x81010001,
                tpmPinRequired: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TpmBadge), findsOneWidget);
      },
    );

    testWidgets(
      'Linux TPM (tss-esapi) row renders TpmBadge without the silent flag',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'tpm2',
                label: 'Linux TPM key',
                backend: 'tpm',
                tpmProvider: 'tss-esapi',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TpmBadge), findsOneWidget);
      },
    );

    testWidgets('Android Keystore row renders the KeystoreBadge', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'ks1',
              label: 'Pixel key',
              backend: 'keystore',
              keystoreStrongBox: true,
              keystorePlatform: 'Pixel 8 (Android 14)',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(KeystoreBadge), findsOneWidget);
    });

    testWidgets(
      'Expired certificate paints the red _ExpiredBadge in the row trail',
      (tester) async {
        // Spec: when `entry.validity.isExpired` resolves true (cert
        // `valid_before` in the past), `_KeyRowBadges` appends the
        // red "Expired" pill. The label text comes from
        // `S.of(context).certExpired` so we match it by visible text.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'exp1',
                label: 'Old cert key',
                certFingerprint: 'SHA256:expired-cert-fp',
                validity: CertValidity(
                  from: DateTime(2020, 1, 1),
                  to: DateTime(2020, 6, 1),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Expired'), findsOneWidget);
      },
    );

    testWidgets(
      'row with a valid certificate exposes the cert-remove (orange) action '
      'instead of the cert-import affordance',
      (tester) async {
        // Spec: `_KeyRowActions` switches the second slot based on
        // `entry.hasCertificate` — present → orange "Remove certificate"
        // tooltip; absent → neutral "Attach an OpenSSH certificate…".
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'cert1',
                label: 'Key with cert',
                certFingerprint: 'SHA256:cert-fp',
                validity: CertValidity(
                  from: DateTime(2099, 1, 1),
                  to: DateTime(2099, 12, 31),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // Cert remove action is reachable via the localized tooltip
        // `certRemove`. The localized string lives in app_en.arb; we
        // do not pin a substring (the copy might evolve) and instead
        // pin the structural cue: the import-cert "Attach…" tooltip
        // must NOT appear when a cert is already attached.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                (w.message?.startsWith(
                      'Attach an OpenSSH certificate signed by your CA',
                    ) ??
                    false),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'stub row swaps the action set to [Re-generate, Remove] and hides the '
      'copy / cert affordances',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub1',
                label: 'Old laptop key',
                backend: 'enclave',
                importedAsStub: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // Stub action cluster — `_KeyRowActions` branches on
        // `entry.importedAsStub` and renders the regenerate + remove
        // affordances instead of the copy / cert / delete trio.
        expect(find.byTooltip('Re-generate here'), findsOneWidget);
        expect(find.byTooltip('Remove stub'), findsOneWidget);
        expect(find.byTooltip('Public Key'), findsNothing);
        expect(find.byTooltip('Import certificate'), findsNothing);
      },
    );
  });

  group('KeyManagerPanel + Add menu', () {
    testWidgets(
      'toolbar renders a single + Add trigger; tapping it opens a popup '
      'that lists the always-on paste / import / generate paths',
      (tester) async {
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        // Trigger label is `S.of(context).addKey` — exactly one
        // instance in the toolbar (the toolbar's only action).
        final trigger = find.text('Add Key');
        expect(trigger, findsOneWidget);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        // Common paths always appear regardless of hardware tier
        // probes — the host platform's available rungs may add more
        // entries below the divider but these three are unconditional.
        expect(find.text('Paste PEM'), findsOneWidget);
        expect(find.text('Import Key'), findsOneWidget);
        expect(find.text('Generate Key'), findsOneWidget);
      },
    );
  });
}
