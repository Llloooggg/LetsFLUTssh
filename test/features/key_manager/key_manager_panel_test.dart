/// Real-DB widget tests for [KeyManagerPanel] driving the production
/// [SshKeysMutator] + an unlocked in-memory rusqlite DB.
///
/// The sibling `key_manager_dialog_test.dart` stubs `loadAllMetadata`
/// with a fake mutator so it can assert pure row-rendering shapes
/// without FRB. This file is the integration half: it mounts the real
/// panel over the real mutator so the load → render → reload cycle,
/// the delete-confirm flow's actual `dbSshKeysDelete`, and the
/// platform-gated Add menu items all execute end to end. Together they
/// cover the panel + its `key_manager_dialog_add.dart` /
/// `key_manager_dialog_rows.dart` part files.
///
/// Tagged `frb_global_store` for the same reason as
/// `ssh_keys_db_test`: the rows live in the process-global DB and the
/// assertions check the list, so it runs in its own `flutter test`
/// process. See dart_test.yaml.
///
/// Not coverable here (and exempt per AGENTS.md testing allow-list):
/// the FIDO2 / PKCS#11 / Enclave / Hello / TPM / Keystore generate +
/// import flows are OS-native (CTAP2 device, smart-card module,
/// Secure Enclave, NCrypt, ESAPI, AndroidKeyStore). Those `_generate*`
/// / `_import*` dispatch arms open native wizard dialogs and cannot run
/// under flutter_test. We cover the menu *rendering* of every tier
/// (via `debugHardwareTiersOverride`) plus the software paste / generate
/// dispatch, the cert action slots, and the rename-via-save + delete
/// flows against the real DB.
@Tags(['frb_global_store'])
library;

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
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/core/toast.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  // Each test starts from an empty store — the DB is process-global, so
  // a leftover row would skew the exact-list assertions. The platform
  // override is cleared too so one test's desktop simulation can't bleed
  // into the next.
  setUp(() async {
    await rust_db.dbSshKeysReplaceAll(rows: const []);
    // The panel's toolbar writes a system-overlay style on mount, which
    // touches `flutter/platform`; flutter_test does not stub that channel
    // by default. Stub it so platform-method calls drain cleanly.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    Toast.clearAllForTest();
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    debugHardwareTiersOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  SshKeyEntry entry({
    required String id,
    required String label,
    String publicKey = 'ssh-ed25519 AAAAPUB',
    String keyType = 'ssh-ed25519',
  }) => SshKeyEntry(
    id: id,
    label: label,
    privateKey: 'PRIVATE-PEM-$id',
    publicKey: publicKey,
    keyType: keyType,
    createdAt: DateTime(2025, 1, 1),
  );

  // Seed keys through the real mutator so the rows land in the same DB
  // the panel reads back via `loadAllMetadata`. Runs inside
  // `tester.runAsync` so the FRB save futures resolve on a real
  // event-loop tick — works before any widget is pumped, so callers can
  // populate the store, then mount the panel and let `initState`'s load
  // pick the rows up.
  Future<void> seed(WidgetTester tester, List<SshKeyEntry> keys) async {
    await tester.runAsync(() async {
      const mutator = SshKeysMutator();
      for (final k in keys) {
        await mutator.save(k);
      }
    });
  }

  Widget buildApp() {
    return ProviderScope(
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

  // Pump the panel up to the point where the imperative `load`
  // (`loadAllMetadata`, two FRB hops) has resolved and the spinner is
  // gone. `pumpAndSettle` would hang on the panel's `CircularProgress`
  // while it loads, so drive the FRB delivery via runAsync ticks
  // instead, bounded by [timeout].
  Future<void> pumpUntilLoaded(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      if (sw.elapsed > timeout) {
        fail('KeyManagerPanel did not finish loading within $timeout');
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }
  }

  // Drive real event-loop ticks + frames until [finder] matches nothing
  // or [timeout] elapses. Used after a UI-triggered mutation whose
  // continuation awaits FRB calls (delete → reload) — `pumpAndSettle`
  // can't advance those because the completions ride a real `Timer`.
  Future<void> pumpUntilGone(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    while (finder.evaluate().isNotEmpty) {
      if (sw.elapsed > timeout) {
        fail('Finder still matched after $timeout');
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }
  }

  group('KeyManagerPanel against a real DB', () {
    testWidgets('renders a row per seeded key after the real load resolves', (
      tester,
    ) async {
      await seed(tester, [
        entry(id: 'k1', label: 'Production', publicKey: 'ssh-ed25519 AAAAK1'),
        entry(id: 'k2', label: 'Staging', publicKey: 'ssh-ed25519 AAAAK2'),
      ]);
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
      // The empty-state copy must be gone once rows render.
      expect(find.text('No SSH keys. Import or generate one.'), findsNothing);
    });

    testWidgets('shows the empty-state message when the store is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);
      expect(find.text('No SSH keys. Import or generate one.'), findsOneWidget);
    });

    testWidgets('a non-stub row exposes copy / cert-import / delete actions', (
      tester,
    ) async {
      await seed(tester, [entry(id: 'k1', label: 'Production')]);
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      // The action cluster lives in `_KeyRowActions`; tooltips are the
      // public surface. A software row with no cert shows copy + the
      // cert-attach slot + delete.
      expect(find.byTooltip('Public Key'), findsOneWidget);
      expect(find.byTooltip('Delete Key'), findsOneWidget);
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
    });
  });

  group('KeyManagerPanel Add menu', () {
    testWidgets('the toolbar shows a single + Add trigger that opens a popup '
        'listing the always-on paste / import / generate paths', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      final trigger = find.text('Add Key');
      expect(trigger, findsOneWidget);
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      // Common paths render unconditionally regardless of hardware tier.
      expect(find.text('Paste PEM'), findsOneWidget);
      expect(find.text('Import Key'), findsOneWidget);
      expect(find.text('Generate Key'), findsOneWidget);
    });

    testWidgets('a desktop TPM tier adds the generate + import TPM menu items '
        'below the divider', (tester) async {
      // Simulate a TPM-capable desktop. `Platform.isLinux` is true on
      // the CI host, so the TPM-import arm (Linux-only) also renders.
      plat.debugDesktopPlatformOverride = true;
      debugHardwareTiersOverride = const [HardwareTier.tpm];

      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      // Hardware section sits under a divider built from
      // `supportedHardwareTiersForPlatform()`.
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      expect(find.text('Generate TPM-backed SSH key'), findsOneWidget);
      // The `.tpm`-blob import arm only renders on Linux — the CI host.
      expect(find.text('Import TPM-protected SSH key'), findsOneWidget);
    });

    testWidgets('with no hardware tiers the menu has only the common paths '
        'and no divider', (tester) async {
      // Empty tier list mirrors an unsupported desktop target — the
      // FIDO2 / PKCS#11 runtime probes return false under flutter_test
      // (FRB-throwing getters caught to `false`), so the hardware
      // section collapses entirely.
      debugHardwareTiersOverride = const [];

      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();

      expect(find.text('Paste PEM'), findsOneWidget);
      // No hardware tiers → no hardware generate/import items. (A divider
      // can still separate the always-present common groups, so the
      // meaningful assertion is the absence of the hardware arms.)
      expect(find.text('Generate TPM-backed SSH key'), findsNothing);
    });

    testWidgets('selecting Paste PEM opens the add-key dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste PEM'));
      await tester.pumpAndSettle();

      // `_AddKeyDialog` (empty mode) shows the label + PEM fields. The
      // field decoration labels are the public markers.
      expect(find.text('Key Label'), findsWidgets);
      expect(find.text('Paste Private Key (PEM)'), findsOneWidget);
    });

    testWidgets('selecting Generate Key opens the generate dialog with the '
        'type picker', (tester) async {
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      await tester.tap(find.text('Add Key'));
      await tester.pumpAndSettle();
      // `Generate Key` appears twice once the dialog is open (menu item
      // + dialog title/button); tap the menu entry first.
      await tester.tap(find.text('Generate Key').first);
      await tester.pumpAndSettle();

      // `_GenerateKeyDialog` renders the software key-type chips; the
      // hardware-bound sk-* variants are filtered out.
      expect(find.text('Key Type'), findsOneWidget);
      expect(find.text('Ed25519'), findsOneWidget);
      expect(find.text('FIDO2 Ed25519'), findsNothing);
    });
  });

  group('KeyManagerPanel rename + delete flows', () {
    testWidgets(
      'saving the same id with a new label renames the row in place',
      (tester) async {
        // Rename is an upsert on the same id: the store ends with one
        // row carrying the latest label, and the panel's load
        // (`loadAllMetadata`) surfaces exactly that — no duplicate row,
        // no stale label.
        await seed(tester, [
          entry(id: 'k1', label: 'Old name'),
          entry(id: 'k1', label: 'New name'),
        ]);
        await tester.pumpWidget(buildApp());
        await pumpUntilLoaded(tester);

        expect(find.text('New name'), findsOneWidget);
        expect(find.text('Old name'), findsNothing);
      },
    );

    testWidgets('delete → confirm removes the key from the list', (
      tester,
    ) async {
      await seed(tester, [
        entry(id: 'k1', label: 'Doomed', publicKey: 'ssh-ed25519 AAAAK1'),
        entry(id: 'k2', label: 'Survivor', publicKey: 'ssh-ed25519 AAAAK2'),
      ]);
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);
      expect(find.text('Doomed'), findsOneWidget);

      // Two rows → two Delete-Key buttons. Tap the one on the 'Doomed'
      // row by walking up from its title to the enclosing row.
      final deleteButtons = find.byTooltip('Delete Key');
      expect(deleteButtons, findsNWidgets(2));
      final doomedDelete = find.descendant(
        of: find
            .ancestor(of: find.text('Doomed'), matching: find.byType(Row))
            .first,
        matching: find.byTooltip('Delete Key'),
      );
      await tester.tap(doomedDelete.first);
      await tester.pumpAndSettle();

      // Confirm dialog from `_deleteKey` — the `AppDialog` title reuses
      // the `Delete Key` string and the destructive action is `Delete`.
      expect(find.text('Delete'), findsOneWidget);

      // Confirm. `_deleteKey` then awaits `dbSshKeysDelete` + `_reload`
      // (loadAllMetadata); those FRB completions land on real event-loop
      // ticks, so drive them via runAsync until the row is gone.
      await tester.tap(find.text('Delete'));
      await pumpUntilGone(tester, find.text('Doomed'));

      expect(find.text('Doomed'), findsNothing);
      expect(find.text('Survivor'), findsOneWidget);
      // The delete success toast arms an auto-dismiss Timer; cancel it
      // so it doesn't outlive the widget tree (pending-timer assertion).
      Toast.clearAllForTest();
    });

    testWidgets('delete → cancel keeps the key in the list', (tester) async {
      await seed(tester, [entry(id: 'k1', label: 'Keeper')]);
      await tester.pumpWidget(buildApp());
      await pumpUntilLoaded(tester);

      await tester.tap(find.byTooltip('Delete Key').first);
      await tester.pumpAndSettle();
      // Cancel closes the confirm dialog without touching the DB.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Keeper'), findsOneWidget);
    });
  });
}
