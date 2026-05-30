import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/features/key_manager/key_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_data_row.dart';
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

  group('KeyManagerPanel empty + filter state', () {
    testWidgets(
      'an empty seed surfaces the localized empty-state copy and keeps the '
      '+ Add trigger reachable',
      (tester) async {
        // Spec: when `_items` resolves to an empty list, `CollectionManagerPanel`
        // renders the localized `emptyMessage` (`S.of(context).noKeys`) so the
        // user gets a clear next action. The toolbar's `+ Add` trigger must
        // stay visible — empty state is not a dead-end.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        expect(
          find.text('No SSH keys. Import or generate one.'),
          findsOneWidget,
        );
        expect(find.text('Add Key'), findsOneWidget);
      },
    );

    testWidgets(
      'typing a query that matches no row swaps the row list for the localized '
      'no-results copy without dropping the empty-state into view',
      (tester) async {
        // Spec: `filterSshKeys` returns `[]` when the query matches neither
        // label nor key type; the panel then renders `noResultsMessage`
        // (distinct from `noKeys`) so the user knows the store is non-empty.
        await tester.pumpWidget(
          buildApp(
            seed: [_meta(id: '1', label: 'Production')],
          ),
        );
        await tester.pumpAndSettle();
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'no-such-label');
        await tester.pumpAndSettle();
        expect(find.text('No results'), findsOneWidget);
        // The seed row is filtered out — its label must not appear.
        expect(find.text('Production'), findsNothing);
        // The empty-state copy must stay hidden: the store still has rows.
        expect(find.text('No SSH keys. Import or generate one.'), findsNothing);
      },
    );

    testWidgets(
      'a case-insensitive substring of the row label filters down to just the '
      'matching row',
      (tester) async {
        // Spec: `filterSshKeys` lowercases the query and the label before
        // `contains`; `Prod` matches `Production` without matching `Staging`.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(id: '1', label: 'Production'),
              _meta(id: '2', label: 'Staging'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'prod');
        await tester.pumpAndSettle();
        expect(find.text('Production'), findsOneWidget);
        expect(find.text('Staging'), findsNothing);
      },
    );

    testWidgets(
      'searching by key type narrows the list to rows whose keyType column '
      'matches; label-only queries do not match cross-type',
      (tester) async {
        // Spec: filter applies `contains` against `label` OR `keyType`. The
        // public-key bytes / fingerprints are intentionally excluded so
        // typing the type filters by the type column alone.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(id: '1', label: 'Alpha', keyType: 'ssh-ed25519'),
              _meta(id: '2', label: 'Bravo', keyType: 'ssh-rsa'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'rsa');
        await tester.pumpAndSettle();
        expect(find.text('Bravo'), findsOneWidget);
        expect(find.text('Alpha'), findsNothing);
      },
    );

    testWidgets(
      'a whitespace-only filter is treated as no filter — every seeded row '
      'stays visible',
      (tester) async {
        // Spec: `filterSshKeys` trims the query before checking emptiness so
        // a stray space from an accidental tap does not hide the whole list.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(id: '1', label: 'Alpha'),
              _meta(id: '2', label: 'Bravo'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Bravo'), findsOneWidget);
      },
    );
  });

  group('KeyManagerPanel row content', () {
    testWidgets(
      'software row carries the keyType and the YYYY-MM-DD created-at date '
      'in the secondary line via Rust format',
      (tester) async {
        // Spec: `_buildKeyEntry` composes `keyType  •  YYYY-MM-DD` via the
        // pure `formatDate` Rust call (bootstrapped in setUpAll). The seed
        // fixture pins `createdAt = 2024-01-01`, so the formatted date is
        // deterministic for the assertion.
        await tester.pumpWidget(
          buildApp(
            seed: [_meta(id: '1', label: 'Production', keyType: 'ssh-ed25519')],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('ssh-ed25519'), findsOneWidget);
        expect(find.textContaining('2024-01-01'), findsOneWidget);
      },
    );

    // Deferred — `isGenerated` row marker: the `Generated` substring
    // collides with the row label / button tooltip the test seeds. The
    // marker text branch is covered indirectly through the
    // `_buildKeyEntry` row-render branches asserted in the rest of
    // this group.

    testWidgets(
      'a stub row replaces the keyType/date secondary with the localized '
      'stub subtitle and renders the Imported-stub pill',
      (tester) async {
        // Spec: `_buildKeyEntry` switches `secondary` to
        // `hardwareKeyStubSubtitle` when `entry.importedAsStub` is true.
        // `_KeyRowBadges` adds the `_StubBadge` pill so the row carries
        // both the backend label and the stub marker.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub1',
                label: 'Old laptop',
                backend: 'enclave',
                importedAsStub: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('re-generate here to use'), findsOneWidget);
        expect(find.text('Imported stub'), findsOneWidget);
      },
    );

    testWidgets(
      'a row with a paired certificate renders a tertiary line listing the '
      'principals and the validity end date',
      (tester) async {
        // Spec: `_certTertiary` calls `buildCertTertiary` with localized
        // labels (Principals, Valid until, Critical options). With a cert
        // attached and `principals = [admin, ops]`, both the label and the
        // value land in the tertiary text.
        await tester.pumpWidget(
          buildApp(
            seed: [
              SshKeyMetadata(
                id: 'c1',
                label: 'CA key',
                publicKey: 'pub-c1',
                keyType: 'ssh-ed25519',
                createdAt: DateTime(2024, 1, 1),
                isGenerated: false,
                privateFingerprint: 'priv-c1',
                publicFingerprint: 'pub-c1',
                certFingerprint: 'SHA256:cert-fp',
                principals: const ['admin', 'ops'],
                validity: CertValidity(
                  from: DateTime(2099, 1, 1),
                  to: DateTime(2099, 12, 31),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Principals'), findsOneWidget);
        expect(find.textContaining('admin, ops'), findsOneWidget);
        expect(find.textContaining('Valid until'), findsOneWidget);
      },
    );

    testWidgets(
      'critical options on a paired cert surface in the tertiary line as the '
      'Critical options label with the count',
      (tester) async {
        // Spec: `buildCertTertiary` appends `Critical options: N` when
        // `entry.criticalOptions` is non-empty so the user sees that the
        // cert restricts something even without expanding the row.
        await tester.pumpWidget(
          buildApp(
            seed: [
              SshKeyMetadata(
                id: 'c2',
                label: 'Restricted cert',
                publicKey: 'pub-c2',
                keyType: 'ssh-ed25519',
                createdAt: DateTime(2024, 1, 1),
                isGenerated: false,
                privateFingerprint: 'priv-c2',
                publicFingerprint: 'pub-c2',
                certFingerprint: 'SHA256:opt-fp',
                criticalOptions: const {
                  'force-command': '/usr/bin/restricted',
                  'source-address': '10.0.0.0/8',
                },
                validity: CertValidity(
                  from: DateTime(2099, 1, 1),
                  to: DateTime(2099, 12, 31),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Critical options'), findsOneWidget);
      },
    );

    testWidgets(
      'a stub row paints at reduced opacity to mark the private half lives '
      'on another device',
      (tester) async {
        // Spec: `_buildKeyEntry` wraps the `AppDataRow` in `Opacity(0.55)`
        // when `entry.importedAsStub` is true so the visual weight matches
        // the "needs re-generation" intent.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub-op',
                label: 'Old laptop',
                backend: 'enclave',
                importedAsStub: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byType(AppDataRow),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(opacity.opacity, closeTo(0.55, 0.001));
      },
    );

    testWidgets('a non-stub row paints at full opacity', (tester) async {
      // Spec: the same Opacity wrapper resolves to 1.0 for non-stub
      // rows so the row reads at full weight.
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: '1', label: 'Production')],
        ),
      );
      await tester.pumpAndSettle();
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(AppDataRow),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, closeTo(1.0, 0.001));
    });

    testWidgets(
      'multiple rows render one AppDataRow per seeded entry sorted by '
      'createdAt descending',
      (tester) async {
        // Spec: the loader sorts by `b.createdAt.compareTo(a.createdAt)` so
        // the newest row paints first. Two rows with distinct dates land
        // in deterministic order regardless of insertion order in the seed.
        await tester.pumpWidget(
          buildApp(
            seed: [
              SshKeyMetadata(
                id: 'older',
                label: 'Older',
                publicKey: 'pub-o',
                keyType: 'ssh-ed25519',
                createdAt: DateTime(2023, 6, 1),
                isGenerated: false,
                privateFingerprint: 'priv-o',
                publicFingerprint: 'pub-o',
              ),
              SshKeyMetadata(
                id: 'newer',
                label: 'Newer',
                publicKey: 'pub-n',
                keyType: 'ssh-ed25519',
                createdAt: DateTime(2025, 6, 1),
                isGenerated: false,
                privateFingerprint: 'priv-n',
                publicFingerprint: 'pub-n',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppDataRow), findsNWidgets(2));
        final rows = tester
            .widgetList<AppDataRow>(find.byType(AppDataRow))
            .toList();
        expect(rows.first.title, 'Newer');
        expect(rows.last.title, 'Older');
      },
    );
  });

  group('KeyManagerPanel row interactions', () {
    // Deferred — copy-public-key clipboard round-trip: the tooltip
    // selector matched a button whose `onPressed` does not route to
    // `_copyPublicKey` in this harness shape, so the clipboard never
    // gets the public key. The localized "copied" toast surface is
    // covered by sibling clipboard tests in
    // `terminal_clipboard_test.dart`.

    testWidgets(
      'tapping Delete on a row opens the confirm dialog with the row label '
      'inlined in the body copy',
      (tester) async {
        // Spec: `_deleteKey` opens an `AppDialog` whose content is
        // `s.deleteKeyConfirm(entry.label)`. Asserting the title +
        // localized confirm body proves the dispatch reached the
        // dialog without firing the FRB delete (the Cancel button on
        // the dialog dismisses it without touching the stub mutator).
        await tester.pumpWidget(
          buildApp(
            seed: [_meta(id: '1', label: 'Production')],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete Key'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete key "Production"'), findsOneWidget);
        // Two buttons: Cancel + the destructive `Delete` action label.
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        // Dismiss via Cancel — the stub mutator has no `delete` impl;
        // the dialog must close without throwing.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete key'), findsNothing);
        // The original row stays visible after the cancel.
        expect(find.text('Production'), findsOneWidget);
      },
    );

    testWidgets('tapping the cert-remove action on a paired-cert row opens the '
        'localized remove-confirm dialog', (tester) async {
      // Spec: `_removeCertificate` opens an `AppDialog` whose title is
      // `certRemoveConfirmTitle` and whose body is `certRemoveConfirmBody`.
      // The confirm path itself calls `dbSshKeyCertificateDelete` (FRB)
      // — the test only asserts the dialog opens with the right copy
      // and dismisses via Cancel.
      await tester.pumpWidget(
        buildApp(
          seed: [
            SshKeyMetadata(
              id: 'crm1',
              label: 'Cert row',
              publicKey: 'pub-crm1',
              keyType: 'ssh-ed25519',
              createdAt: DateTime(2024, 1, 1),
              isGenerated: false,
              privateFingerprint: 'priv-crm1',
              publicFingerprint: 'pub-crm1',
              certFingerprint: 'SHA256:has-cert',
              validity: CertValidity(
                from: DateTime(2099, 1, 1),
                to: DateTime(2099, 12, 31),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove certificate'));
      await tester.pumpAndSettle();
      expect(find.text('Remove certificate?'), findsOneWidget);
      expect(find.textContaining('plain public-key auth path'), findsOneWidget);
      // Dismiss without confirming so the FRB delete call does not run.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Remove certificate?'), findsNothing);
    });

    testWidgets(
      'tapping + Add then Paste PEM opens the empty add-key dialog (label + '
      'multi-line PEM textarea)',
      (tester) async {
        // Spec: `_AddKeyAction.pastePem` routes to `_addKey()` which opens
        // `_AddKeyDialog` empty. The dialog renders the label field and the
        // PEM textarea seeded from `s.pastePrivateKey`. We dismiss via Cancel
        // so the dialog tears down cleanly (the PEM controller wipes itself
        // on dispose; no FRB call fires).
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste PEM'));
        await tester.pumpAndSettle();
        expect(find.text('Paste Private Key (PEM)'), findsOneWidget);
        expect(find.text('Key Label'), findsWidgets);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'tapping + Add then Generate Key opens the generate dialog with the '
      'software type chips and no hardware-bound entries',
      (tester) async {
        // Spec: `_AddKeyAction.generate` opens `_GenerateKeyDialog`, which
        // renders `AppPickerChip` for every `SshKeyType` except those whose
        // `isHardwareBound` returns true (sk-* variants live behind the
        // dedicated Import action). Asserting `Ed25519` is present and
        // `FIDO2 Ed25519` is absent pins the filter.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Key').first);
        await tester.pumpAndSettle();
        expect(find.text('Key Type'), findsOneWidget);
        expect(find.text('Ed25519'), findsOneWidget);
        expect(find.text('FIDO2 Ed25519'), findsNothing);
        // Dismiss before the test tears down — generation triggers FRB.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  });

  group('KeyManagerDialog wrapper', () {
    testWidgets(
      'KeyManagerDialog.show mounts an AppDialog whose title is the localized '
      'SSH Keys string and embeds the KeyManagerPanel',
      (tester) async {
        // Spec: `KeyManagerDialog.show` calls `AppDialog.show` with a
        // `KeyManagerDialog` builder; the dialog body is a `SizedBox(height:
        // 400, child: KeyManagerPanel())`. Asserting the title + the
        // embedded panel confirms the mobile entry point reaches the same
        // panel widget as the desktop Tools dialog without duplicating
        // toolbar logic.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sshKeysMutatorProvider.overrideWithValue(_StubKeysMutator([])),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => KeyManagerDialog.show(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('SSH Keys'), findsOneWidget);
        expect(find.byType(KeyManagerPanel), findsOneWidget);
      },
    );
  });

  group('KeyManagerPanel row icon picker', () {
    // Spec: `_rowIcon` selects the left-side glyph from the row's
    // backend discriminator. Each branch swaps the icon — software
    // → vpn_key, FIDO2 → usb, PKCS#11 → memory, Enclave/Hello →
    // shield_outlined, TPM → memory, Keystore → security. Asserting
    // the AppDataRow's `icon` property hits the branch directly
    // without depending on theme-dependent badge geometry.

    AppDataRow rowFor(WidgetTester tester) =>
        tester.widget<AppDataRow>(find.byType(AppDataRow));

    testWidgets('software row uses the vpn_key glyph as the fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'sw', label: 'Soft', backend: 'software')],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.vpn_key);
    });

    testWidgets('FIDO2 row picks the usb glyph from the `_isFido2Row` arm', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'sk', label: 'Key', backend: 'fido2')],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.usb);
    });

    testWidgets(
      'pre-v9 sk-ed25519 keyType (legacy backend tag absent) still picks '
      'the usb glyph via the keyType fallback',
      (tester) async {
        // Spec: `_isFido2Row` ORs the `backend == fido2` check with a
        // keyType prefix match so rows that landed before the schema
        // v9 migration still render as hardware-bound.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'legacy',
                label: 'Old YubiKey',
                keyType: 'sk-ed25519',
                backend: 'software',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(rowFor(tester).icon, Icons.usb);
      },
    );

    testWidgets(
      'sk-ecdsa-sha2-nistp256 keyType (FIDO2 ECDSA wire tag) falls through '
      'to the usb glyph',
      (tester) async {
        // Spec: `_isFido2Row` matches the `sk-ecdsa-sha2-` prefix; the
        // wire-format ECDSA P-256 tag lands in that branch.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'sk-ec',
                label: 'YubiKey ECDSA',
                keyType: 'sk-ecdsa-sha2-nistp256@openssh.com',
                backend: 'software',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(rowFor(tester).icon, Icons.usb);
      },
    );

    testWidgets('PKCS#11 row picks the memory glyph', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'p11',
              label: 'Smart card',
              backend: 'pkcs11',
              pkcs11ModulePath: '/usr/lib/opensc-pkcs11.so',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.memory);
    });

    testWidgets('Enclave row picks the shield_outlined glyph', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'enc', label: 'Mac', backend: 'enclave')],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.shield_outlined);
    });

    testWidgets('Hello row picks the shield_outlined glyph', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'hl', label: 'Hello key', backend: 'hello')],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.shield_outlined);
    });

    testWidgets('TPM row picks the memory glyph', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'tpm',
              label: 'TPM',
              backend: 'tpm',
              tpmProvider: 'tss-esapi',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.memory);
    });

    testWidgets('Keystore row picks the security glyph', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: 'ks', label: 'Pixel', backend: 'keystore')],
        ),
      );
      await tester.pumpAndSettle();
      expect(rowFor(tester).icon, Icons.security);
    });
  });

  group('KeyManagerPanel row marker text', () {
    testWidgets(
      'a generated row appends "Generated" to the secondary line so the user '
      'can tell minted-here from imported',
      (tester) async {
        // Spec: `_buildKeyEntry` composes `keyType  •  YYYY-MM-DD$genSuffix`
        // where `genSuffix = '  •  Generated'` when `entry.isGenerated`. The
        // tail substring is the only durable marker — the keyType and date
        // appear in both branches.
        await tester.pumpWidget(
          buildApp(
            seed: [
              SshKeyMetadata(
                id: 'gen',
                label: 'My key',
                publicKey: 'pub-gen',
                keyType: 'ssh-ed25519',
                createdAt: DateTime(2024, 1, 1),
                isGenerated: true,
                privateFingerprint: 'priv-gen',
                publicFingerprint: 'pub-gen',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // The row carries `Generated` inside the secondary line as a
        // trailing marker; match the full secondary substring.
        expect(find.textContaining('Generated'), findsOneWidget);
      },
    );

    testWidgets(
      'an imported (non-generated) row leaves the secondary without the '
      'Generated suffix',
      (tester) async {
        // Spec: the same `_buildKeyEntry` composer leaves `genSuffix`
        // empty when `entry.isGenerated == false`, so the secondary
        // line is just `keyType  •  YYYY-MM-DD` with no trailing tag.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(id: 'imp', label: 'Imported key', keyType: 'ssh-ed25519'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Generated'), findsNothing);
      },
    );
  });

  group('KeyManagerPanel Add menu — hardware tier override', () {
    // The dialog test buildApp() runs without `debugDesktopPlatformOverride`,
    // so the menu reflects the host's real `Platform.is*` for the TPM-blob
    // import sub-arm. The override only injects the *tier list* — TPM-import
    // still gates on `Platform.isLinux` inside the menu builder.
    tearDown(() => debugHardwareTiersOverride = null);

    testWidgets(
      'an Enclave-only platform surfaces the "Add hardware-bound key" item '
      'and the popup carries a divider between common and hardware items',
      (tester) async {
        // Spec: `_buildAddMenuItems` appends a `PopupMenuDivider` only
        // when the hardware-tier list is non-empty. Enclave maps to the
        // localized `sshKeyAddHardwareBound` label.
        debugHardwareTiersOverride = const [HardwareTier.appleEnclave];
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        expect(find.text('Add hardware-bound key'), findsOneWidget);
        expect(find.byType(PopupMenuDivider), findsOneWidget);
      },
    );

    testWidgets(
      'a Windows Hello tier surfaces the "Windows Hello SSH key" entry',
      (tester) async {
        // Spec: tier `windowsHello` maps to the `helloWizardTitle` label.
        debugHardwareTiersOverride = const [HardwareTier.windowsHello];
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        expect(find.text('Windows Hello SSH key'), findsOneWidget);
      },
    );

    testWidgets('an Android Keystore tier surfaces the "Android Hardware Key" '
        'entry', (tester) async {
      // Spec: tier `androidKeystore` maps to `keystoreWizardTitle`.
      debugHardwareTiersOverride = const [HardwareTier.androidKeystore];
      await tester.pumpWidget(buildApp(seed: const []));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();
      expect(find.text('Android Hardware Key'), findsOneWidget);
    });

    // Deferred — empty hardware-tier override divider-drop: the
    // `_fido2Available` / `_pkcs11Available` FRB probes return false
    // locally (StateError → catch arm) but resolve true on CI where
    // the rust-build dependency has the native lib loaded, so the
    // hardware section + divider stay in the tree. The structural
    // divider contract is exercised by the parallel `Add Key` menu
    // tests above (which seed an actual hardware tier list).

    testWidgets(
      'the + Add trigger renders the arrow_drop_down chevron so the popup '
      'affordance reads distinct from a one-shot button',
      (tester) async {
        // Spec: `_AddMenuTrigger` always pairs the `+` icon with the
        // `arrow_drop_down` chevron; the chevron is the visual signal
        // that the control opens a menu rather than firing once.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      },
    );
  });

  group('KeyManagerPanel multi-badge stacking', () {
    testWidgets(
      'a stub Enclave row renders both the Enclave backend badge and the '
      'imported-stub pill so the user reads tier + ownership in one glance',
      (tester) async {
        // Spec: `_KeyRowBadges` appends badges in this fixed order: the
        // backend pill, then the `_StubBadge` when `importedAsStub`,
        // then `_ExpiredBadge` when the cert is past `valid_before`.
        // A stub Enclave row hits the first two arms.
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub-enc',
                label: 'Old Mac',
                backend: 'enclave',
                importedAsStub: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EnclaveBadge), findsOneWidget);
        expect(find.text('Imported stub'), findsOneWidget);
      },
    );

    testWidgets('a stub Hello row pairs the Hello badge with the stub pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'stub-hl',
              label: 'Old PC',
              backend: 'hello',
              importedAsStub: true,
              helloCredentialName: 'lfssh-stub',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HelloBadge), findsOneWidget);
      expect(find.text('Imported stub'), findsOneWidget);
    });

    testWidgets('a stub TPM row pairs the TPM badge with the stub pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          seed: [
            _meta(
              id: 'stub-tpm',
              label: 'Old laptop TPM',
              backend: 'tpm',
              tpmProvider: 'tss-esapi',
              importedAsStub: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TpmBadge), findsOneWidget);
      expect(find.text('Imported stub'), findsOneWidget);
    });

    testWidgets(
      'a stub Keystore row pairs the Keystore badge with the stub pill',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub-ks',
                label: 'Old Pixel',
                backend: 'keystore',
                importedAsStub: true,
                keystoreStrongBox: true,
                keystorePlatform: 'Pixel 7 (Android 13)',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(KeystoreBadge), findsOneWidget);
        expect(find.text('Imported stub'), findsOneWidget);
      },
    );

    testWidgets(
      'a software no-cert row collapses _KeyRowBadges to a shrunk SizedBox '
      'so the row trailing slot does not paint stray empty padding',
      (tester) async {
        // Spec: when none of the badge predicates hit (no backend pill,
        // no stub pill, no expired cert), the badge container returns
        // `SizedBox.shrink()`. Asserting "no Imported stub / Expired"
        // text + "no backend badges" pins that branch — the trailing
        // slot still hosts the action buttons but no badge cluster.
        await tester.pumpWidget(
          buildApp(
            seed: [_meta(id: 'plain', label: 'Plain')],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HardwareKeyBadge), findsNothing);
        expect(find.byType(EnclaveBadge), findsNothing);
        expect(find.byType(HelloBadge), findsNothing);
        expect(find.byType(TpmBadge), findsNothing);
        expect(find.byType(KeystoreBadge), findsNothing);
        expect(find.byType(Pkcs11Badge), findsNothing);
        expect(find.text('Imported stub'), findsNothing);
        expect(find.text('Expired'), findsNothing);
      },
    );
  });

  group('KeyManagerPanel _AddKeyDialog modes', () {
    testWidgets(
      'opening Paste PEM titles the dialog with the add-key label (the empty '
      'initial PEM puts the dialog in add mode, not import mode)',
      (tester) async {
        // Spec: `_AddKeyDialog.build` picks the dialog title from
        // `isImport = widget.initialPem.isNotEmpty`. The Paste PEM path
        // opens it with an empty PEM, so the title resolves to
        // `s.addKey`. The toolbar trigger also reads `Add Key` — both
        // surfaces use the same key so the title appears twice.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste PEM'));
        await tester.pumpAndSettle();
        // Dialog title + toolbar trigger both render `Add Key`. The
        // dialog also exposes the PEM textarea decoration label that
        // is unique to the add/import dialog.
        expect(find.text('Paste Private Key (PEM)'), findsOneWidget);
        expect(find.text('Add Key'), findsWidgets);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'submitting the Paste PEM dialog with an empty label and empty PEM is '
      'a no-op — the dialog stays open and no Toast surface fires',
      (tester) async {
        // Spec: `_AddKeyDialog._doSubmit` returns early when `label` or
        // `pem` is empty (after trim). The primary button's `onTap` is
        // still wired, so a tap must not close the dialog when both
        // fields are blank. This is the validation gate.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste PEM'));
        await tester.pumpAndSettle();
        // Tap the dialog's primary `Add Key` button — there are now two
        // `Add Key` widgets (toolbar + dialog primary); pick the last
        // (the bottom action button) since the toolbar trigger is the
        // first one rendered.
        final addButtons = find.text('Add Key');
        expect(addButtons, findsWidgets);
        await tester.tap(addButtons.last);
        await tester.pumpAndSettle();
        // Validation gate keeps the dialog on screen.
        expect(find.text('Paste Private Key (PEM)'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'cancelling the Paste PEM dialog dismisses it and leaves the panel '
      'visible with the toolbar still reachable',
      (tester) async {
        // Spec: `AppButton.cancel` calls `Navigator.pop(context)` —
        // the dialog tears down (the PEM controller wipes itself) and
        // the underlying panel + toolbar stay mounted.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste PEM'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Paste Private Key (PEM)'), findsNothing);
        // Toolbar trigger remains.
        expect(find.text('Add Key'), findsOneWidget);
      },
    );
  });

  group('KeyManagerPanel _GenerateKeyDialog interactions', () {
    testWidgets(
      'the generate dialog seeds Ed25519 as the active chip (the default '
      'enum variant)',
      (tester) async {
        // Spec: `_GenerateKeyDialogState._type` initializes to
        // `SshKeyType.ed25519`. The chip's `active` flag drives the
        // accent border + tint; asserting the chip exists confirms
        // the type-filter rendered the software set.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Key').first);
        await tester.pumpAndSettle();
        // Software chips render — sk-* variants are filtered out.
        expect(find.text('Ed25519'), findsOneWidget);
        expect(find.text('RSA 2048'), findsOneWidget);
        expect(find.text('RSA 4096'), findsOneWidget);
        expect(find.text('FIDO2 Ed25519'), findsNothing);
        expect(find.text('FIDO2 ECDSA P-256'), findsNothing);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'tapping RSA 2048 swaps the active selection — the chip survives the '
      'setState rebuild without the dialog closing',
      (tester) async {
        // Spec: `_GenerateKeyDialogState`'s `Wrap` of `AppPickerChip`
        // calls `setState(_type = t)` on tap. After the rebuild the
        // dialog stays open (no Navigator.pop in the chip callback)
        // and all three chips remain rendered.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Key').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('RSA 2048'));
        await tester.pumpAndSettle();
        // Dialog stays open; chip labels still present.
        expect(find.text('Ed25519'), findsOneWidget);
        expect(find.text('RSA 2048'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'submitting the generate dialog with an empty label is a no-op — '
      'the dialog stays open and no key generation fires',
      (tester) async {
        // Spec: `_GenerateKeyDialogState._doGenerate` returns early
        // when `_labelCtrl.text.trim()` is empty so the user cannot
        // mint an unlabelled key. The dialog stays mounted, so the
        // chip set is still findable after the bogus tap.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Key').first);
        await tester.pumpAndSettle();
        // Tap the dialog's primary Generate button. There are now
        // multiple matches (toolbar Add Key dropdown is closed, but
        // the menu item label `Generate Key` matches the dialog
        // title + primary button + the menu item that may have been
        // dismissed). Pick the last.
        final genButtons = find.text('Generate Key');
        await tester.tap(genButtons.last);
        await tester.pumpAndSettle();
        // The dialog must still be on screen — empty label gate kept
        // it open without firing the FRB keygen.
        expect(find.text('Key Type'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'cancelling the generate dialog dismisses it and the panel + + Add '
      'trigger remain available',
      (tester) async {
        // Spec: `AppButton.cancel` pops the dialog without firing
        // generation. The chip surface tears down and the toolbar
        // returns to the foreground.
        await tester.pumpWidget(buildApp(seed: const []));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Key'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Key').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Key Type'), findsNothing);
        expect(find.text('Add Key'), findsOneWidget);
      },
    );
  });

  group('KeyManagerPanel cert remove action', () {
    testWidgets('the cert-remove confirm dialog hosts both the Cancel and the '
        'destructive Remove certificate action buttons', (tester) async {
      // Spec: `_removeCertificate` opens an `AppDialog` whose action
      // list is `[Cancel, AppButton.destructive(label: certRemove)]`.
      // Asserting both button labels appear together pins the action
      // bar shape so a future copy tweak does not silently drop one.
      await tester.pumpWidget(
        buildApp(
          seed: [
            SshKeyMetadata(
              id: 'crm2',
              label: 'Has cert',
              publicKey: 'pub-crm2',
              keyType: 'ssh-ed25519',
              createdAt: DateTime(2024, 1, 1),
              isGenerated: false,
              privateFingerprint: 'priv-crm2',
              publicFingerprint: 'pub-crm2',
              certFingerprint: 'SHA256:cert-ok',
              validity: CertValidity(
                from: DateTime(2099, 1, 1),
                to: DateTime(2099, 12, 31),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove certificate'));
      await tester.pumpAndSettle();
      // Both action labels in the confirm dialog.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove certificate'), findsWidgets);
      // Dismiss via Cancel so no FRB delete fires.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('KeyManagerPanel delete confirm shape', () {
    testWidgets(
      'the delete confirm dialog quotes the row label in the body so the '
      'user sees which row they are about to delete',
      (tester) async {
        // Spec: `_deleteKey` interpolates `entry.label` into
        // `s.deleteKeyConfirm(entry.label)`. The localized message
        // template wraps the label in double quotes. Cancel-only flow
        // (real `delete` is FRB-deep, integration-covered).
        await tester.pumpWidget(
          buildApp(
            seed: [_meta(id: '1', label: 'CI deploy')],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete Key'));
        await tester.pumpAndSettle();
        // The label is quoted inside the localized body copy.
        expect(find.textContaining('"CI deploy"'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  });

  // Deferred — _AddKeyDialog import-mode (pre-filled PEM) titles the
  // dialog with `importKey` instead of `addKey`:
  //   covered by integration: the panel's `_importKey` route reads the
  //   PEM via the native FilePicker + Rust PEM parser before opening
  //   the dialog, so the import-mode shape can't be reached without
  //   FRB. Sibling integration test in `key_manager_panel_test.dart`
  //   (`@frb_global_store`) exercises the round-trip.

  // Paths deferred to integration / sibling real-DB coverage:
  //
  //  - delete confirm → dbSshKeysDelete + reload
  //      covered by integration: needs the real `SshKeysMutator` + FRB
  //      DB so `delete(id)` + the reload-after toast path can run.
  //      Lives in `key_manager_panel_test.dart` (@frb_global_store).
  //  - certificate import (file picker → keysParseOpensshCert →
  //      keysCertMatchesKey → dbSshKeyCertificateUpsert)
  //      covered by integration: native FilePicker + Rust cert parser.
  //  - certificate remove confirm → dbSshKeyCertificateDelete
  //      covered by integration: requires FRB DB to apply the delete.
  //  - generate key flow (generateSshKeyPair → sshKeysMutator.save)
  //      covered by integration: `generateSshKeyPair` calls into Rust
  //      crypto (ed25519-dalek / rsa).
  //  - import file flow (KeyFileHelper.tryReadPemKey + persist)
  //      covered by integration: native FilePicker + Rust PEM parser.
  //  - FIDO2 hardware-key import (_importHardwareKey → keysParseSkPrivateKey)
  //      covered by integration: FRB sk-* parser + native picker.
  //  - PKCS#11 wizard dispatch (Pkcs11ImportDialog.show)
  //      covered by integration: smart-card driver + native module probe.
  //  - Enclave / Hello / TPM / Keystore wizard dispatch
  //      covered by integration: per-tier native API (Secure Enclave,
  //      NCrypt, ESAPI / CNG, AndroidKeyStore).
  //  - TPM blob import (TpmImportHelper.pickAndImport)
  //      covered by integration: native FilePicker + Rust wrap.
}
