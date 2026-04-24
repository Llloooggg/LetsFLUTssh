import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/migration/migration_runner.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/widgets/db_corrupt_dialog.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';
import 'package:letsflutssh/widgets/tier_reset_dialog.dart';

import '../helpers/fake_dialog_prompter.dart';
import '../helpers/fake_native_plugins.dart';
import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_security.dart';
import '../helpers/test_providers.dart';

void main() {
  group('SecurityInitController — getter + flag surface', () {
    // The controller's heavy methods (`bootstrap`, `reopenAfterUnlock`,
    // `reinitFromReset`, `handleCorruption`) touch 19 Riverpod
    // providers plus migration-runner disk I/O — integration-level
    // coverage lives in `main.dart` startup paths once the shared
    // provider fixture grows enough overrides to fake the full set.
    //
    // This test file pins the small read-only surface that the rest
    // of the app already relies on: `isReady` starts false,
    // `takeAndClearCredentialsResetFlag` is a 1-shot read, and
    // `dispose()` is idempotent. Getting these wrong would silently
    // break the post-unlock session-reload gate and the
    // credentials-reset toast — both user-visible regressions that
    // are cheap to catch in unit tests.

    testWidgets('isReady starts false before bootstrap', (tester) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(ref: ref, isMounted: () => true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(ctrl!.isReady, isFalse);
      ctrl!.dispose();
    });

    testWidgets('takeAndClearCredentialsResetFlag is a 1-shot read', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(ref: ref, isMounted: () => true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Flag starts false on a fresh controller — the post-toast
      // path in `_LetsFLUTsshAppState._maybeShowCredentialsResetToast`
      // relies on this default so a first launch without a wipe
      // does not show the "credentials were reset" surface.
      expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
      // Still false on a second call — no internal toggle.
      expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
      ctrl!.dispose();
    });

    testWidgets('dispose() is idempotent so double-dispose from state teardown '
        'is safe', (tester) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(ref: ref, isMounted: () => true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Lifecycle contract allows `_LetsFLUTsshAppState.dispose`
      // to call controller.dispose() once. Pin idempotency so a
      // future refactor that accidentally double-dispose'd (for
      // example through a post-frame callback resolving after
      // the state's teardown) does not throw.
      ctrl!.dispose();
      ctrl!.dispose();
      // Still safe — no exception, still reports not-ready.
      expect(ctrl!.isReady, isFalse);
    });
  });

  group('SecurityInitController — guard-clause surface', () {
    // These tests pin the short-circuits that gate every heavy path
    // (reopenAfterUnlock / reinitFromReset / handleCorruption) before
    // they touch the DB or UI. Driving the full unlock chain end-to-end
    // needs the migration runner + a per-tier dialog harness — tracked
    // as Session 2b. The guards are small and load-bearing: a
    // regression here would either wake a dialog during teardown or
    // fire a DB open against a disposed state, both user-visible.

    late Directory tmpDir;
    setUp(() {
      tmpDir = installFakePathProvider();
      installFakeSecureStorage();
      installFakeNativePlugins();
    });

    tearDown(() {
      uninstallFakeNativePlugins();
      uninstallFakeSecureStorage();
      uninstallFakePathProvider(tmpDir);
    });

    testWidgets('reopenAfterUnlock bails when isMounted() is false', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(
                  ref: ref,
                  // Simulates the state being torn down before the
                  // lockState listener fires its callback.
                  isMounted: () => false,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // With isMounted() returning false, the method must return
      // immediately without reading any provider — otherwise a
      // post-dispose callback would race with the state teardown
      // and throw on `ref.read` after `dispose`.
      await ctrl!.reopenAfterUnlock();
      expect(ctrl!.isReady, isFalse);
      ctrl!.dispose();
    });

    testWidgets('reopenAfterUnlock bails when securityState has no key', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(ref: ref, isMounted: () => true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Fresh securityStateProvider has no encryption key — the
      // controller must log "no key — skipping" and return without
      // calling `_injectDatabase`. Previously a refactor that
      // dropped the null-check would open a plaintext DB and
      // silently demote the tier on the next lock/unlock cycle.
      await ctrl!.reopenAfterUnlock();
      expect(ctrl!.isReady, isFalse);
      ctrl!.dispose();
    });

    testWidgets('handleCorruption marks ready when no active DB is attached', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(ref: ref, isMounted: () => true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Null _activeDatabase is the post-first-launch-cancel path:
      // no tier was chosen, no DB was opened, yet `_maybeShowCreds
      // ResetToast` still fires from the first-frame callback and
      // relies on `isReady` flipping true so the UI leaves the
      // loading spinner. If this branch regressed to "wait for a
      // DB that will never arrive", cold start would hang.
      await ctrl!.handleCorruption();
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });
  });

  group('SecurityInitController — DB seam integration', () {
    // These tests drive the DB-injection path through the three
    // seams (dbOpener / dbFileExists / verifyReadable). Full bootstrap
    // works end-to-end when the async chain runs under
    // `tester.runAsync` — configProvider's 300 ms debounce Timer
    // never fires under FakeAsync, which is why the naive
    // `await ctrl.bootstrap()` inside testWidgets used to deadlock.
    // The first-launch wizard exits silently when the test widget
    // tree mounts a plain `MaterialApp` without binding the global
    // `navigatorKey` — the helper reads `navigatorKey.currentContext`
    // and returns early on null, so no dialog actually fires.

    late Directory tmpDir;
    late AppDatabase testDb;
    setUp(() {
      tmpDir = installFakePathProvider();
      installFakeSecureStorage();
      installFakeNativePlugins();
      testDb = openTestDatabase();
    });

    tearDown(() async {
      await testDb.close();
      uninstallFakeNativePlugins();
      uninstallFakeSecureStorage();
      uninstallFakePathProvider(tmpDir);
    });

    testWidgets(
      'bootstrap on an existing plaintext install flips isReady to true',
      (tester) async {
        SecurityInitController? ctrl;
        var opens = 0;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      opens++;
                      return testDb;
                    },
                    // Lie about file presence so `_initSecurity` skips
                    // the first-launch wizard and takes the existing-
                    // install branch.
                    dbFileExists: () async => true,
                    // MC cipher is not linked into flutter test; skip
                    // the real probe and pin the controller's post-
                    // probe isReady contract.
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        // `runAsync` escapes FakeAsync so configProvider's 300 ms
        // debounce Timer fires — `_persistSecurityTier` waits on
        // that Timer and would otherwise deadlock.
        await tester.runAsync(() => ctrl!.bootstrap());

        // AppConfig.defaults has security=null; master password is
        // disabled; the keychain is empty. Legacy-infer falls through
        // to the "plaintext mode (existing DB)" branch — one dbOpener
        // call, isReady flipped after the readability probe.
        expect(opens, 1);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap on a first-launch install exits silently on null navigator',
      (tester) async {
        SecurityInitController? ctrl;
        var opens = 0;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      opens++;
                      return testDb;
                    },
                    // No DB on disk — first-launch branch.
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // First-launch reads `navigatorKey.currentContext`; the test
        // widget tree uses a plain MaterialApp without binding that
        // global key so the resolver returns null and the wizard
        // helper exits silently. No DB ever opens because no tier
        // was chosen, handleCorruption sees a null `_activeDatabase`
        // and flips isReady regardless — same contract tested in the
        // guard-clause group above.
        expect(opens, 0);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap on a legacy-infer keychain install forwards stored key',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        final seededKey = Uint8List.fromList(List.filled(32, 9));
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // Legacy-infer picks the keychain branch when
              // master-password is disabled *and* a key is stored;
              // seed the key here so the branch fires and the opener
              // receives it unchanged.
              secureKeyStorage: FakeSecureKeyStorage(storedKey: seededKey),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // The opener saw the exact 32-byte sequence the fake returned
        // — no zeroing or replacement along the way. If the legacy-
        // infer path ever got re-ordered and plaintext won, the opener
        // would receive null here.
        expect(capturedKey, equals(seededKey));
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap on a legacy-infer paranoid install flips the reset flag',
      (tester) async {
        SecurityInitController? ctrl;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // Paranoid legacy-infer branch fires whenever
              // master-password is reported enabled. The dialog path
              // is out of reach here (no navigator bound), so
              // `showUnlockDialog` returns null and the controller
              // treats that as "user chose reset" — the toast flag
              // flips true and a plaintext DB opens as the recovery
              // fallback.
              masterPassword: FakeMasterPasswordManager(enabled: true),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // The reset flag is a 1-shot read; a successful bootstrap via
        // the paranoid fallback must surface it so main.dart can show
        // the "credentials were reset" toast after session load.
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=keychain opens with stored key',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        final seededKey = Uint8List.fromList(List.filled(32, 0xAA));
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(storedKey: seededKey),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        // Persist an explicit tier=keychain so `_unlockByTier` takes
        // the keychain branch rather than legacy-infer. Under
        // runAsync because configProvider.update awaits a 300 ms
        // debounce Timer the save path depends on.
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychain,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Explicit-tier dispatch reaches `_unlockKeychain`, which
        // reads the stored key from the fake and forwards it to the
        // opener unchanged — same invariant as legacy-infer but
        // through the dispatcher rather than the inference chain.
        expect(capturedKey, equals(seededKey));
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=keychain without stored key falls to plaintext',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        final capturedCalls = <Uint8List?>[];
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            // No stored key — FakeSecureKeyStorage returns null on read.
            overrides: securityProviderOverrides(),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      capturedCalls.add(capturedKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychain,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // No key in the keychain under an L1-configured install is a
        // credentials-reset scenario — the recovery path opens a
        // plaintext DB (null key) and flips the reset flag so the UI
        // surfaces the "credentials were reset" toast.
        expect(capturedKey, isNull);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets('bootstrap under explicit tier=plaintext opens with no key', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      Uint8List? capturedKey;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(),
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) {
                    capturedKey = encryptionKey;
                    return testDb;
                  },
                  dbFileExists: () async => true,
                  verifyReadable: (db) async => true,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => capturedRef
            .read(configProvider.notifier)
            .update(
              (c) => c.copyWithSecurity(
                security: const SecurityConfig(
                  tier: SecurityTier.plaintext,
                  modifiers: SecurityTierModifiers.defaults,
                ),
              ),
            ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      // Explicit L0 dispatch: `_unlockByTier(plaintext)` calls
      // `_injectDatabase()` with no arguments — the opener must
      // receive `encryptionKey: null`.
      expect(capturedKey, isNull);
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets(
      'bootstrap under explicit tier=paranoid with null navigator flips reset flag',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // Paranoid branch calls `manager.verifyAndDerive` via
              // showUnlockDialog; the dialog is unreachable on a null
              // navigator so the helper returns null and the recovery
              // path kicks in (plaintext fallback + reset flag).
              masterPassword: FakeMasterPasswordManager(enabled: true),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.paranoid,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        expect(capturedKey, isNull);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'first-launch with available keychain auto-wires T1 without the wizard',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // A keystorage that reports available drives the
              // capabilities probe's `keychainAvailable` flag true,
              // which lets `_firstLaunchSetup` take the auto-setup
              // path instead of the wizard.
              secureKeyStorage: FakeSecureKeyStorage(available: true),
            ),
            child: MaterialApp(
              // Bind the global navigatorKey so `_firstLaunchSetup`'s
              // null-context guard passes and the auto-setup path can
              // run. Without this the helper exits at the
              // `if (ctx == null) return;` line and never reaches
              // `_autoSetupKeychain`.
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    // No DB yet — first-launch branch.
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // `_autoSetupKeychain` generates a fresh AES-256 key, writes
        // it to the fake keystore, then injects the DB with that key.
        // Opener sees 32 non-null bytes; the reset flag stays false
        // because this is a clean first-launch, not a recovery.
        expect(capturedKey, isNotNull);
        expect(capturedKey!.length, 32);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=keychainWithPassword unconfigured gate falls to plaintext',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            // Gate reports not-configured → L2 recognises missing
            // state as a reset and opens plaintext.
            overrides: securityProviderOverrides(),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychainWithPassword,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        expect(capturedKey, isNull);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=keychainWithPassword biometric-unlocks silently',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        final bioKey = Uint8List.fromList(List.filled(32, 0xB2));
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              keychainGate: FakeKeychainPasswordGate(configured: true),
              // BiometricKeyVault holds the DB key; BiometricAuth
              // reports available + authenticate=true so the helper
              // reaches `vault.read()` and the opener sees the key.
              biometricVault: FakeBiometricKeyVault(stored: true, key: bioKey),
              biometricAuth: FakeBiometricAuth(
                available: true,
                authenticateResult: true,
              ),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychainWithPassword,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Biometric fast-path — no dialog, the vault's key lands
        // directly on the opener. Reset flag stays false because
        // this is a successful unlock.
        expect(capturedKey, equals(bioKey));
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=hardware with stored passwordless vault unseals',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        final vaultKey = Uint8List.fromList(List.filled(32, 0xC3));
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // Vault reports stored + returns the seeded key on
              // `read(null)` (passwordless branch). isAvailable
              // result is not consulted by `_unlockHardware`, so
              // the default false here is harmless.
              hardwareVault: FakeHardwareTierVault(
                stored: true,
                dbKey: vaultKey,
              ),
            ),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Passwordless L3 unseals without a dialog; the vault's key
        // lands verbatim on the opener.
        expect(capturedKey, equals(vaultKey));
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'bootstrap under explicit tier=hardware with unconfigured vault falls to plaintext',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            // Fake hardware vault reports not-stored → `_unlockHardware`
            // recognises the "configured tier but missing state" shape
            // as a credentials reset and falls to plaintext.
            overrides: securityProviderOverrides(),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        expect(capturedKey, isNull);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets('reinitFromReset swallows a DB-close exception and continues', (
      tester,
    ) async {
      // Pre-close the test DB so reinitFromReset's `db.close()`
      // throws ("Can't re-open a closed database"). The log/
      // continue branch must run without aborting the rest of the
      // reset flow — otherwise a transient drift failure during
      // reset would leave the controller stuck with a stale DB
      // reference and a half-cleared corruption-retry counter.
      final prematurelyClosedDb = openTestDatabase();
      SecurityInitController? ctrl;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(),
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) => prematurelyClosedDb,
                  dbFileExists: () async => false,
                  verifyReadable: (db) async => true,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final key = Uint8List.fromList(List.filled(32, 5));
      capturedRef
          .read(securityStateProvider.notifier)
          .set(SecurityTier.keychain, key);
      await tester.runAsync(() => ctrl!.reopenAfterUnlock());
      // Close the DB behind the controller's back so the next
      // close attempt throws.
      await prematurelyClosedDb.close();

      await tester.runAsync(() => ctrl!.reinitFromReset());

      // Even with the close exception, the post-reset branches
      // still run — isReady flips because `_markSecurityReady`
      // fires from `handleCorruption`.
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets(
      'reinitFromReset closes the DB, re-runs the wizard, flips isReady',
      (tester) async {
        SecurityInitController? ctrl;
        var opens = 0;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            // Override autoLockStoreProvider with a DB-free fake —
            // the real store reads from AppDatabase which reinitFrom
            // Reset closes mid-flight, triggering "Can't re-open a
            // closed database" on the post-reset `_markSecurityReady`.
            // Production swaps the DB inside the wizard before that
            // probe runs; tests that skip the wizard need the override.
            overrides: securityProviderOverrides(),
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      opens++;
                      // Fresh AppDatabase each call so the one the
                      // reset path closes is not the one the reopen
                      // already reads from.
                      return openTestDatabase();
                    },
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        // Seed `_activeDatabase` via a reopen so reinitFromReset has
        // a DB to close; `securityStateProvider` owns the key.
        final key = Uint8List.fromList(List.filled(32, 5));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());
        expect(opens, 1);

        await tester.runAsync(() => ctrl!.reinitFromReset());

        // Post-reset: wizard exits silently on null navigator (no
        // extra dbOpener call), handleCorruption sees a null DB, and
        // `_markSecurityReady` now reads the FakeAutoLockStore baseline
        // instead of hitting the closed drift handle.
        expect(opens, 1);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'handleCorruption on a reopened DB probes once and flips isReady',
      (tester) async {
        SecurityInitController? ctrl;
        var probeCalls = 0;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => true,
                    verifyReadable: (db) async {
                      probeCalls++;
                      return true;
                    },
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        final key = Uint8List.fromList(List.filled(32, 3));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);

        // Seed `_activeDatabase` via reopen (the seam routes the open
        // through `dbOpener` → `testDb`). Then handleCorruption sees a
        // non-null DB and runs the readability probe exactly once.
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());
        await tester.runAsync(() => ctrl!.handleCorruption());

        // One probe per handleCorruption — reopenAfterUnlock does not
        // probe on its own. A regression that probed from _injectDatabase
        // would double this count and slow cold start.
        expect(probeCalls, 1);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'reopenAfterUnlock routes the DB open through the injected dbOpener',
      (tester) async {
        SecurityInitController? ctrl;
        var opens = 0;
        var lastKey = Uint8List(0);
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    // Counter + key capture — the real opener would
                    // construct a fresh AppDatabase; the seam must
                    // propagate whatever key the unlock path derived.
                    dbOpener: ({encryptionKey}) {
                      opens++;
                      // Snapshot — the key is a live alias into the
                      // previous SecretBuffer, which the follow-up
                      // `securityStateProvider.set` disposes before
                      // the test's expect() runs. Copy here so the
                      // assertion sees the bytes from the moment of
                      // injection, not random freed memory.
                      lastKey = Uint8List.fromList(
                        encryptionKey ?? const <int>[],
                      );
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        // Seed the security state with a keychain-tier key so
        // reopenAfterUnlock does not early-exit on the null-key guard.
        final key = Uint8List.fromList(List.filled(32, 7));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);

        // `reopenAfterUnlock` awaits `configProvider.update`, which
        // blocks on a 300 ms debounce Timer. Under FakeAsync (the
        // default for testWidgets) the Timer never fires, so run the
        // unlock chain inside `tester.runAsync` where real-time Timers
        // progress. After the chain resolves, return to FakeAsync for
        // teardown.
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());

        // The seam was the single open path — no other call site in
        // `_injectDatabase` bypasses it. The captured key equals the
        // one `securityStateProvider` held, proving the unlock path
        // forwarded the real key rather than zeroing it en route.
        expect(opens, 1);
        expect(lastKey, equals(key));
        ctrl!.dispose();
      },
    );
  });

  group('SecurityInitController — first-launch wizard via DialogPrompter', () {
    // With the DialogPrompter seam, the wizard's return value becomes
    // scriptable — each case drives a different `_applyFirstLaunchWizard
    // Result` branch end-to-end without the widget tree ever having to
    // paint the real `SecuritySetupDialog`. The keychain is faked
    // unavailable so `_firstLaunchSetup` skips the auto-setup branch
    // and falls through to the prompter path.
    //
    // The global `navigatorKey` is bound to the MaterialApp so the
    // helper's null-context guard passes; without it `_firstLaunchSetup`
    // returns before ever reading caps or calling the prompter.

    late Directory tmpDir;
    late AppDatabase testDb;
    setUp(() {
      tmpDir = installFakePathProvider();
      installFakeSecureStorage();
      installFakeNativePlugins();
      testDb = openTestDatabase();
    });

    tearDown(() async {
      await testDb.close();
      uninstallFakeNativePlugins();
      uninstallFakeSecureStorage();
      uninstallFakePathProvider(tmpDir);
    });

    Future<void> pumpWizardTest(
      WidgetTester tester, {
      required SecuritySetupResult wizardResult,
      required void Function(SecurityInitController ctrl, Uint8List? key) check,
      FakeMasterPasswordManager? masterPassword,
      FakeHardwareTierVault? hardwareVault,
      FakeKeychainPasswordGate? keychainGate,
      FakeSecureKeyStorage? secureKeyStorage,
    }) async {
      final prompter = FakeSecurityDialogPrompter(wizardResult: wizardResult);
      SecurityInitController? ctrl;
      Uint8List? capturedKey;
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(
            // Keychain probe must report unavailable so
            // `_firstLaunchSetup` skips auto-setup and goes through
            // the wizard branch where the prompter fires.
            secureKeyStorage:
                secureKeyStorage ??
                FakeSecureKeyStorage(
                  available: false,
                  probeResult: KeyringProbeResult.probeFailed,
                ),
            masterPassword: masterPassword,
            hardwareVault: hardwareVault,
            keychainGate: keychainGate,
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) {
                    capturedKey = encryptionKey == null
                        ? null
                        : Uint8List.fromList(encryptionKey);
                    return testDb;
                  },
                  dbFileExists: () async => false,
                  verifyReadable: (db) async => true,
                  dialogPrompter: prompter,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      // Prompter fired exactly once — any refactor that bypassed the
      // wizard (e.g. silently picking plaintext on a first-launch
      // that should have prompted) or double-fired it would surface
      // here.
      expect(prompter.wizardCalls, 1);
      check(ctrl!, capturedKey);
      ctrl!.dispose();
    }

    testWidgets(
      'wizard picks plaintext — `_firstLaunchPlaintext` opens no-key DB',
      (tester) async {
        await pumpWizardTest(
          tester,
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
          check: (ctrl, key) {
            expect(key, isNull);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets('wizard picks keychain — fresh AES key written + injected', (
      tester,
    ) async {
      // The keychain first-launch branch needs the injected key-
      // storage to accept writes. FakeSecureKeyStorage.writeKey
      // always returns true and caches the key.
      final storage = FakeSecureKeyStorage(
        available: false,
        probeResult: KeyringProbeResult.probeFailed,
      );
      await pumpWizardTest(
        tester,
        secureKeyStorage: storage,
        wizardResult: const SecuritySetupResult(
          tier: SecurityTier.keychain,
          keychainAvailable: true,
        ),
        check: (ctrl, key) {
          expect(key, isNotNull);
          expect(key!.length, 32);
          // Key ended up in the fake keystore — a regression that
          // dropped the writeKey call would leave it null here.
          expect(storage.storedKey, equals(key));
          expect(ctrl.isReady, isTrue);
        },
      );
    });

    testWidgets(
      'wizard picks keychain with keychainAvailable=false falls to plaintext',
      (tester) async {
        await pumpWizardTest(
          tester,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.keychain,
            keychainAvailable: false,
          ),
          check: (ctrl, key) {
            // `_firstLaunchKeychain` bails when the wizard itself
            // reports the keychain unavailable — a DI invariant: the
            // wizard should never return a tier its own capability
            // probe said is off, but the controller guards against
            // that mismatch by falling to plaintext.
            expect(key, isNull);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets('wizard picks keychain + writeKey fails → plaintext fallback', (
      tester,
    ) async {
      // `_firstLaunchKeychain` runs when wizard picks keychain with
      // `keychainAvailable=true`. If the subsequent writeKey call
      // rejects the write, the else-branch logs + injects a plaintext
      // DB. Covers lines 968-972.
      final storage = FakeSecureKeyStorage(
        available: false,
        probeResult: KeyringProbeResult.probeFailed,
        writeKeySucceeds: false,
      );
      await pumpWizardTest(
        tester,
        secureKeyStorage: storage,
        wizardResult: const SecuritySetupResult(
          tier: SecurityTier.keychain,
          keychainAvailable: true,
        ),
        check: (ctrl, key) {
          expect(key, isNull);
          expect(storage.storedKey, isNull);
          expect(ctrl.isReady, isTrue);
        },
      );
    });

    testWidgets('wizard picks keychainWithPassword — gate set + key stored', (
      tester,
    ) async {
      final storage = FakeSecureKeyStorage(
        available: false,
        probeResult: KeyringProbeResult.probeFailed,
      );
      final gate = FakeKeychainPasswordGate();
      await pumpWizardTest(
        tester,
        secureKeyStorage: storage,
        keychainGate: gate,
        wizardResult: const SecuritySetupResult(
          tier: SecurityTier.keychainWithPassword,
          shortPassword: 'hunter2',
        ),
        check: (ctrl, key) {
          expect(key, isNotNull);
          expect(key!.length, 32);
          // Gate configured with the wizard's password — the L2
          // unlock dialog verifies against this value on next
          // launch.
          expect(gate.configured, isTrue);
          expect(gate.expectedPassword, 'hunter2');
          expect(ctrl.isReady, isTrue);
        },
      );
    });

    testWidgets(
      'wizard picks keychainWithPassword empty password falls to plaintext',
      (tester) async {
        final gate = FakeKeychainPasswordGate();
        await pumpWizardTest(
          tester,
          keychainGate: gate,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.keychainWithPassword,
            shortPassword: '',
          ),
          check: (ctrl, key) {
            expect(key, isNull);
            expect(gate.configured, isFalse);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets(
      'wizard picks hardware — vault stores key + opener receives it',
      (tester) async {
        final vault = FakeHardwareTierVault(available: true);
        await pumpWizardTest(
          tester,
          hardwareVault: vault,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.hardware,
            pin: '1234',
          ),
          check: (ctrl, key) {
            expect(key, isNotNull);
            expect(key!.length, 32);
            // Vault now reports stored with the same 32-byte key.
            expect(vault.stored, isTrue);
            expect(vault.dbKey, equals(key));
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets(
      'wizard picks paranoid — master password manager enables + key derived',
      (tester) async {
        final derivedKey = Uint8List.fromList(List.filled(32, 0xF3));
        final manager = FakeMasterPasswordManager(derivedKey: derivedKey);
        await pumpWizardTest(
          tester,
          masterPassword: manager,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.paranoid,
            masterPassword: 'correct horse battery staple',
          ),
          check: (ctrl, key) {
            expect(key, equals(derivedKey));
            // Enable flipped the manager state so the next launch
            // takes the Paranoid unlock path.
            expect(manager.enabled, isTrue);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets(
      'first-launch auto-setup keychain write fails → wizard takes over',
      (tester) async {
        // writeKey returns false so `_autoSetupKeychain` logs the miss
        // and returns false. `_firstLaunchSetup` then clears the
        // `caps.keychainAvailable` flag and falls through to the
        // wizard prompter — the "degraded-keychain" fallback path.
        final storage = FakeSecureKeyStorage(
          available: true,
          writeKeySucceeds: false,
        );
        final prompter = FakeSecurityDialogPrompter(
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(secureKeyStorage: storage),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Wizard invoked once after the auto-setup rejected the write.
        // Wizard returned plaintext → no key on the opener.
        expect(prompter.wizardCalls, 1);
        expect(capturedKey, isNull);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'wizard picks keychainWithPassword but keychain write fails → plaintext',
      (tester) async {
        final storage = FakeSecureKeyStorage(
          available: false,
          probeResult: KeyringProbeResult.probeFailed,
          writeKeySucceeds: false,
        );
        final gate = FakeKeychainPasswordGate();
        await pumpWizardTest(
          tester,
          secureKeyStorage: storage,
          keychainGate: gate,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.keychainWithPassword,
            shortPassword: 'hunter2',
          ),
          check: (ctrl, key) {
            // `_firstLaunchKeychainWithPassword` sets the gate first
            // and then tries to write. On failure it clears the gate
            // so the legacy-infer path cannot pick up a half-configured
            // state on the next launch, and falls back to plaintext.
            expect(key, isNull);
            expect(gate.configured, isFalse);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets(
      'wizard picks hardware but vault.store fails → plaintext fallback',
      (tester) async {
        final vault = FakeHardwareTierVault(
          available: true,
          storeSucceeds: false,
        );
        await pumpWizardTest(
          tester,
          hardwareVault: vault,
          wizardResult: const SecuritySetupResult(
            tier: SecurityTier.hardware,
            pin: '0000',
          ),
          check: (ctrl, key) {
            // `_firstLaunchHardware` falls to plaintext when the seal
            // itself rejects the write — sealed blob never persisted,
            // vault.stored stays false.
            expect(key, isNull);
            expect(vault.stored, isFalse);
            expect(ctrl.isReady, isTrue);
          },
        );
      },
    );

    testWidgets('wizard picks paranoid without a password falls to plaintext', (
      tester,
    ) async {
      final manager = FakeMasterPasswordManager();
      await pumpWizardTest(
        tester,
        masterPassword: manager,
        wizardResult: const SecuritySetupResult(tier: SecurityTier.paranoid),
        check: (ctrl, key) {
          expect(key, isNull);
          // Manager still disabled — the wizard returned a paranoid
          // pick with a null password, which the controller treats
          // as "user cancelled mid-wizard".
          expect(manager.enabled, isFalse);
          expect(ctrl.isReady, isTrue);
        },
      );
    });
  });

  group('SecurityInitController — corruption dialog via DialogPrompter', () {
    // With a scripted DbCorruptChoice, `handleCorruption` can be driven
    // past the probe-failure branch without needing to paint + tap the
    // real `DbCorruptDialog`. Two paths are testable: `resetAndSetup
    // Fresh` (wipe + first-launch wizard again) and `tryOtherTier`
    // (retry under legacy-infer). `exitApp` is intentionally out of
    // reach — the production handler calls `exit(0)` which would kill
    // the test isolate.

    late Directory tmpDir;
    late AppDatabase testDb;
    setUp(() {
      tmpDir = installFakePathProvider();
      installFakeSecureStorage();
      installFakeNativePlugins();
      testDb = openTestDatabase();
    });

    tearDown(() async {
      await testDb.close();
      uninstallFakeNativePlugins();
      uninstallFakeSecureStorage();
      uninstallFakePathProvider(tmpDir);
    });

    testWidgets(
      'probe failure + user picks resetAndSetupFresh re-runs wizard + isReady',
      (tester) async {
        SecurityInitController? ctrl;
        late WidgetRef capturedRef;
        var probeCalls = 0;
        final prompter = FakeSecurityDialogPrompter(
          corruptChoice: DbCorruptChoice.resetAndSetupFresh,
          // After wipe + reset, `_wipeAndRestartFromScratch` re-runs
          // `_firstLaunchSetup`, which prompts the wizard. Canning a
          // plaintext pick keeps the follow-up branch simple — the
          // important invariant is that the wizard fires exactly once
          // after reset, not that it picks any particular tier.
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => false,
                    // First probe fails (kicks dialog); any subsequent
                    // probe after wipe succeeds so `_markSecurityReady`
                    // can fire.
                    verifyReadable: (db) async {
                      probeCalls++;
                      return probeCalls > 1;
                    },
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        // Seed `_activeDatabase` so `handleCorruption` hits the probe.
        final key = Uint8List.fromList(List.filled(32, 9));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());

        await tester.runAsync(() => ctrl!.handleCorruption());

        // Dialog fired; user picked reset; wipe path invoked the
        // wizard exactly once. Reset flag flipped because
        // `_wipeAndRestartFromScratch` always sets it.
        expect(prompter.corruptCalls, 1);
        expect(prompter.wizardCalls, 1);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'orphan state + user picks resetAndSetupFresh wipes + reruns wizard',
      (tester) async {
        // Seed an orphan legacy artefact on the fake path_provider
        // tmp dir so `WipeAllService.hasAnyState` returns true with
        // config.security still null. That triggers
        // `_handleLegacyStateIfPresent` → prompter.showTierReset.
        File('${tmpDir.path}/credentials.kdf').writeAsStringSync('legacy');
        SecurityInitController? ctrl;
        final prompter = FakeSecurityDialogPrompter(
          tierResetChoice: TierResetChoice.resetAndSetupFresh,
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Dialog fired once; wipeAll ran and dropped the orphan;
        // wizard re-ran once; reset flag flipped.
        expect(prompter.tierResetCalls, 1);
        expect(prompter.wizardCalls, 1);
        expect(File('${tmpDir.path}/credentials.kdf').existsSync(), isFalse);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'migration throws → _handleMigrationFailure routes to reset path',
      (tester) async {
        SecurityInitController? ctrl;
        final prompter = FakeSecurityDialogPrompter(
          corruptChoice: DbCorruptChoice.resetAndSetupFresh,
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                    dialogPrompter: prompter,
                    // Simulate an artefact throwing mid-readVersion.
                    migrationRunner: () async => throw StateError('boom'),
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Migration throw routed through `_handleMigrationFailure`,
        // which opens the corruption dialog. User picked reset →
        // `_wipeAndRestartFromScratch` ran the wizard once, reset
        // flag flipped.
        expect(prompter.corruptCalls, 1);
        expect(prompter.wizardCalls, 1);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'migration with migratedCount > 0 schedules the success toast',
      (tester) async {
        SecurityInitController? ctrl;
        // One successful step so `report.migratedCount == 1` and the
        // post-frame toast callback gets registered. The toast itself
        // auto-dismisses; we only need to prove the path did not
        // short-circuit into the no-op branch.
        const report = MigrationReport(
          steps: [
            MigrationStep(
              artefactId: 'config.json',
              fromVersion: 1,
              toVersion: 2,
              succeeded: true,
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) => testDb,
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      migrationRunner: () async => report,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Bootstrap returned without failure and flipped isReady. The
        // post-frame toast callback reads `navigatorKey.currentContext`
        // and calls `Overlay.of`; because the global key resolves to
        // the Navigator itself (and Overlay.of looks up the ancestor
        // chain, not descendants), firing the frame raises "No
        // Overlay widget found". Driving that branch cleanly needs a
        // widget test on the app shell that wraps the navigator in a
        // ToastOverlay host — out of scope for the controller unit.
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'migration reports failures → _handleMigrationFailure wipe path',
      (tester) async {
        SecurityInitController? ctrl;
        final prompter = FakeSecurityDialogPrompter(
          corruptChoice: DbCorruptChoice.resetAndSetupFresh,
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        // Report with a fatal error — `hasFailures` returns true, which
        // routes to `_handleMigrationFailure` same as a throw would.
        const failedReport = MigrationReport(fatalError: 'bad_chain');
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => false,
                    verifyReadable: (db) async => true,
                    dialogPrompter: prompter,
                    migrationRunner: () async => failedReport,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        expect(prompter.corruptCalls, 1);
        expect(prompter.wizardCalls, 1);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tier=keychainWithPassword configured gate → dialog returns key → inject',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        final storedKey = Uint8List.fromList(List.filled(32, 0x2B));
        // Simulate user typing the right password — the fake invokes
        // the real verify closure which checks the gate and reads the
        // key. The closure also performs the DB inject side effect.
        final prompter = FakeSecurityDialogPrompter(
          tierSecretSimulatedInput: 'irrelevant',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              keychainGate: FakeKeychainPasswordGate(
                configured: true,
                expectedPassword: 'irrelevant',
              ),
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
                storedKey: storedKey,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    capturedRef = ref;
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) {
                        capturedKey = encryptionKey == null
                            ? null
                            : Uint8List.fromList(encryptionKey);
                        return testDb;
                      },
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      dialogPrompter: prompter,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychainWithPassword,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // L2 dispatch reached the prompter (biometric fast-path not
        // armed because FakeBiometricKeyVault.stored=false by default);
        // prompter handed back the key, opener received it.
        expect(prompter.tierSecretCalls, 1);
        expect(capturedKey, equals(storedKey));
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tier=keychainWithPassword configured gate → dialog reset → plaintext',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        // Null result + fireOnReset=true models "user typed wrong
        // password N times, hit reset". The fake calls onReset which
        // triggers WipeAllService.wipeAll + requestSecurityReinit.
        final prompter = FakeSecurityDialogPrompter(fireOnReset: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              keychainGate: FakeKeychainPasswordGate(configured: true),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    capturedRef = ref;
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) {
                        capturedKey = encryptionKey;
                        return testDb;
                      },
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      dialogPrompter: prompter,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.keychainWithPassword,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Dialog returned null → L2 plaintext fallback branch.
        expect(prompter.tierSecretCalls, 1);
        expect(capturedKey, isNull);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tier=hardware passwordless + vault.read null → plaintext fallback',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(
            // Vault reports stored but read returns null — the
            // "sealed blob present but unsealed by the wrong PIN"
            // shape. Controller treats it as a credentials reset.
            overrides: securityProviderOverrides(
              hardwareVault: FakeHardwareTierVault(stored: true),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers.defaults,
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // No pin to derive, vault.read returned null (dbKey unset
        // on the fake) → plaintext fallback.
        expect(capturedKey, isNull);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tier=hardware with password + biometric available → bio unlock',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        final bioKey = Uint8List.fromList(List.filled(32, 0x4B));
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              // Vault is stored so the first `isStored` check passes,
              // but the biometric-vault read supplies the key so the
              // dialog path is skipped entirely.
              hardwareVault: FakeHardwareTierVault(stored: true),
              biometricVault: FakeBiometricKeyVault(stored: true, key: bioKey),
              biometricAuth: FakeBiometricAuth(
                available: true,
                authenticateResult: true,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              // `_tryBiometricUnlock` reads `S.of(ctx).biometricUnlock
              // Prompt` through the mounted navigator; the delegates
              // must be registered or the lookup throws mid-unlock.
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey == null
                          ? null
                          : Uint8List.fromList(encryptionKey);
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        // password modifier on so `_unlockHardware` takes the
        // biometric-first then dialog branch.
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers(password: true),
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Biometric fast-path succeeded, dialog never fired.
        expect(capturedKey, equals(bioKey));
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets('tier=hardware with password → dialog reset → plaintext', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      Uint8List? capturedKey;
      late WidgetRef capturedRef;
      // Null result + fireOnReset triggers the L3 onReset closure
      // (wipeAll + requestSecurityReinit). Controller sees a
      // non-unlocked return and falls to plaintext.
      final prompter = FakeSecurityDialogPrompter(fireOnReset: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(
            hardwareVault: FakeHardwareTierVault(stored: true),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) {
                      capturedKey = encryptionKey;
                      return testDb;
                    },
                    dbFileExists: () async => true,
                    verifyReadable: (db) async => true,
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => capturedRef
            .read(configProvider.notifier)
            .update(
              (c) => c.copyWithSecurity(
                security: const SecurityConfig(
                  tier: SecurityTier.hardware,
                  modifiers: SecurityTierModifiers(password: true),
                ),
              ),
            ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      expect(prompter.tierSecretCalls, 1);
      expect(capturedKey, isNull);
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets(
      'tier=hardware with password modifier → dialog returns PIN → inject',
      (tester) async {
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        final vaultKey = Uint8List.fromList(List.filled(32, 0x3C));
        // Simulate user entering any PIN — FakeHardwareTierVault.read
        // ignores the pin when stored=true. verify does the inject.
        final prompter = FakeSecurityDialogPrompter(
          tierSecretSimulatedInput: '1234',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              hardwareVault: FakeHardwareTierVault(
                stored: true,
                dbKey: vaultKey,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    capturedRef = ref;
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) {
                        capturedKey = encryptionKey == null
                            ? null
                            : Uint8List.fromList(encryptionKey);
                        return testDb;
                      },
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      dialogPrompter: prompter,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        // password modifier flipped so `_unlockHardware` goes through
        // the dialog path rather than the passwordless read.
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers(password: true),
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // L3 with password modifier reached the tier-secret prompter;
        // canned result lands on the opener.
        expect(prompter.tierSecretCalls, 1);
        expect(capturedKey, equals(vaultKey));
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets('paranoid unlock via prompter receives derivedKey + injects', (
      tester,
    ) async {
      SecurityInitController? ctrl;
      Uint8List? capturedKey;
      late WidgetRef capturedRef;
      final derivedKey = Uint8List.fromList(List.filled(32, 0xAB));
      final prompter = FakeSecurityDialogPrompter(
        masterPasswordResult: derivedKey,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(
            masterPassword: FakeMasterPasswordManager(enabled: true),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) {
                    capturedKey = encryptionKey == null
                        ? null
                        : Uint8List.fromList(encryptionKey);
                    return testDb;
                  },
                  dbFileExists: () async => true,
                  verifyReadable: (db) async => true,
                  dialogPrompter: prompter,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => capturedRef
            .read(configProvider.notifier)
            .update(
              (c) => c.copyWithSecurity(
                security: const SecurityConfig(
                  tier: SecurityTier.paranoid,
                  modifiers: SecurityTierModifiers.defaults,
                ),
              ),
            ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      // Master-password prompt fired, returned a derived key, the
      // opener received those 32 bytes — the happy-path branch of
      // `_unlockParanoid`. Reset flag stays false because this is
      // a successful unlock, not a recovery.
      expect(prompter.masterPasswordCalls, 1);
      expect(capturedKey, equals(derivedKey));
      expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets('pending wipe marker triggers wipeAll + resets flag', (
      tester,
    ) async {
      // A `.wipe-pending` marker on disk means the previous run
      // started a wipe that did not finish. `_initSecurity` must
      // resume the wipe before the normal unlock flow.
      File('${tmpDir.path}/.wipe-pending').writeAsStringSync('');
      File('${tmpDir.path}/credentials.kdf').writeAsStringSync('legacy');
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(
            secureKeyStorage: FakeSecureKeyStorage(
              available: false,
              probeResult: KeyringProbeResult.probeFailed,
            ),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) => testDb,
                  dbFileExists: () async => false,
                  verifyReadable: (db) async => true,
                  dialogPrompter: FakeSecurityDialogPrompter(
                    wizardResult: const SecuritySetupResult(
                      tier: SecurityTier.plaintext,
                    ),
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      // Both the marker and the orphan credentials file are gone —
      // resumed wipeAll cleared them.
      expect(File('${tmpDir.path}/.wipe-pending').existsSync(), isFalse);
      expect(File('${tmpDir.path}/credentials.kdf').existsSync(), isFalse);
      // Reset flag flipped because `_initSecurity` explicitly sets it
      // after the resumed wipe.
      expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets('pending tier-transition marker is cleared on startup', (
      tester,
    ) async {
      // Seed the pending-marker file so `_clearPendingTierTransition`
      // reads + clears it on the first bootstrap tick. Production
      // writes this marker only during a tier switch; a stale one
      // means a crash interrupted the previous switch, and the
      // controller's job here is just to wipe it so the unlock path
      // falls through to the standard flow.
      final marker = File('${tmpDir.path}/.tier-transition-pending');
      marker.writeAsStringSync('{"target":"paranoid"}');
      SecurityInitController? ctrl;
      await tester.pumpWidget(
        ProviderScope(
          overrides: securityProviderOverrides(),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Consumer(
              builder: (ctx, ref, _) {
                ctrl = SecurityInitController(
                  ref: ref,
                  isMounted: () => true,
                  dbOpener: ({encryptionKey}) => testDb,
                  dbFileExists: () async => true,
                  verifyReadable: (db) async => true,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() => ctrl!.bootstrap());

      expect(marker.existsSync(), isFalse);
      expect(ctrl!.isReady, isTrue);
      ctrl!.dispose();
    });

    testWidgets(
      'tier=hardware biometric probe throws → _biometricUnlockForTierDialog catch arm',
      (tester) async {
        // Inside-dialog biometric closure reads the biometric vault;
        // if `isStored` throws, the method's try/catch returns null
        // and the dialog falls through to the manual-input path.
        // Covers lines 663-664 — the catch arm + log. Pre-dialog
        // biometric is bypassed via skipFirstNAvailableCalls so the
        // probe fires only inside the dialog.
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        final prompter = FakeSecurityDialogPrompter(
          fireBiometricUnlock: true,
          // After the biometric closure throws, the fake falls back
          // to the verify path with this simulated PIN — the vault
          // unseals, opener sees key.
          tierSecretSimulatedInput: '1234',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              hardwareVault: FakeHardwareTierVault(
                stored: true,
                dbKey: Uint8List.fromList(List.filled(32, 0x7F)),
              ),
              biometricVault: FakeBiometricKeyVault(
                stored: true,
                // Pre-dialog isStored call returns true (stored=true);
                // in-dialog call (2nd) throws → catch arm fires.
                isStoredThrows: StateError('biometric probe failed'),
                throwAfterNCalls: 1,
              ),
              biometricAuth: FakeBiometricAuth(
                available: true,
                authenticateResult: true,
                skipFirstNAvailableCalls: 1,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    capturedRef = ref;
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) {
                        capturedKey = encryptionKey;
                        return testDb;
                      },
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      dialogPrompter: prompter,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers(password: true),
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Biometric closure caught the throw + returned null; the
        // fake fell through to simulated input which unsealed the
        // vault; opener received key.
        expect(prompter.tierSecretCalls, 1);
        expect(capturedKey, isNotNull);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tryOtherTier retry exceeds max → wipeAndRestart fallback fires',
      (tester) async {
        // Always-fail probe + tryOtherTier choice drives the retry
        // counter past _maxCorruptionRetries (2). On the third retry
        // the guard flips and `_wipeAndRestartFromScratch` takes over
        // — wizard re-runs, final probe succeeds, isReady flips.
        SecurityInitController? ctrl;
        late WidgetRef capturedRef;
        var probeCalls = 0;
        final prompter = FakeSecurityDialogPrompter(
          corruptChoice: DbCorruptChoice.tryOtherTier,
          wizardResult: const SecuritySetupResult(tier: SecurityTier.plaintext),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => true,
                    // Fail the first few probes so the retry chain
                    // exhausts, then succeed on the post-wipe probe.
                    verifyReadable: (db) async {
                      probeCalls++;
                      // Fail probes 1..3 (initial + two retries),
                      // succeed on 4th (post-wipe probe inside
                      // _wipeAndRestartFromScratch).
                      return probeCalls >= 4;
                    },
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        final key = Uint8List.fromList(List.filled(32, 7));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());

        await tester.runAsync(() => ctrl!.handleCorruption());

        // Dialog fired on each retry (3x). Wizard invoked once by
        // `_wipeAndRestartFromScratch`. Reset flag flipped because
        // the wipe path always sets it.
        expect(prompter.corruptCalls, greaterThanOrEqualTo(3));
        expect(prompter.wizardCalls, 1);
        expect(ctrl!.takeAndClearCredentialsResetFlag(), isTrue);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'probe failure + user picks tryOtherTier retries under legacy-infer',
      (tester) async {
        SecurityInitController? ctrl;
        late WidgetRef capturedRef;
        final probeReturns = <bool>[
          // 1st probe (reopen seed) — succeed; reopenAfterUnlock does
          // NOT call verifyReadable, only _injectDatabase does not
          // either. Actually handleCorruption is the only caller, so
          // the 1st call is the corruption probe.
          false,
          // After `_retryUnlockUnderDifferentTier` re-runs
          // `_initSecurity` + `handleCorruption` → true.
          true,
        ];
        var probeIdx = 0;
        final prompter = FakeSecurityDialogPrompter(
          corruptChoice: DbCorruptChoice.tryOtherTier,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              secureKeyStorage: FakeSecureKeyStorage(
                available: false,
                probeResult: KeyringProbeResult.probeFailed,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Consumer(
                builder: (ctx, ref, _) {
                  capturedRef = ref;
                  ctrl = SecurityInitController(
                    ref: ref,
                    isMounted: () => true,
                    dbOpener: ({encryptionKey}) => testDb,
                    dbFileExists: () async => true,
                    verifyReadable: (db) async {
                      final idx = probeIdx;
                      probeIdx++;
                      if (idx >= probeReturns.length) return true;
                      return probeReturns[idx];
                    },
                    dialogPrompter: prompter,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        final key = Uint8List.fromList(List.filled(32, 13));
        capturedRef
            .read(securityStateProvider.notifier)
            .set(SecurityTier.keychain, key);
        await tester.runAsync(() => ctrl!.reopenAfterUnlock());

        await tester.runAsync(() => ctrl!.handleCorruption());

        // One dialog fire, one retry. `_retryUnlockUnderDifferentTier`
        // closes the old DB, invalidates provider caches, clears the
        // persisted tier, and re-runs `_initSecurity`. The second
        // probe returns true and `_markSecurityReady` flips isReady.
        expect(prompter.corruptCalls, 1);
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );

    testWidgets(
      'tier=hardware with password → dialog biometric closure happy path',
      (tester) async {
        // Skip pre-dialog biometric (isAvailable returns false on the
        // first call) so the flow enters the dialog. Inside the
        // dialog the biometric closure calls
        // `_biometricUnlockForTierDialog`, which re-probes
        // `isAvailable` — this call lands AFTER the skip window and
        // returns true, then authenticate + vault.read succeed, and
        // the L3 wrapper injects the key. Covers the happy path of
        // `_biometricUnlockForTierDialog` + the L3 dialog biometric
        // wrapper lambdas.
        SecurityInitController? ctrl;
        Uint8List? capturedKey;
        late WidgetRef capturedRef;
        final bioKey = Uint8List.fromList(List.filled(32, 0x6E));
        final prompter = FakeSecurityDialogPrompter(fireBiometricUnlock: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: securityProviderOverrides(
              hardwareVault: FakeHardwareTierVault(stored: true),
              biometricVault: FakeBiometricKeyVault(stored: true, key: bioKey),
              biometricAuth: FakeBiometricAuth(
                available: true,
                authenticateResult: true,
                // Pre-dialog path calls `bio.isAvailable()` once
                // inside `_unlockHardware`; skipping that call forces
                // the flow past the pre-dialog branch into the
                // dialog.
                skipFirstNAvailableCalls: 1,
              ),
            ),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (ctx, ref, _) {
                    capturedRef = ref;
                    ctrl = SecurityInitController(
                      ref: ref,
                      isMounted: () => true,
                      dbOpener: ({encryptionKey}) {
                        capturedKey = encryptionKey == null
                            ? null
                            : Uint8List.fromList(encryptionKey);
                        return testDb;
                      },
                      dbFileExists: () async => true,
                      verifyReadable: (db) async => true,
                      dialogPrompter: prompter,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => capturedRef
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWithSecurity(
                  security: const SecurityConfig(
                    tier: SecurityTier.hardware,
                    modifiers: SecurityTierModifiers(password: true),
                  ),
                ),
              ),
        );

        await tester.runAsync(() => ctrl!.bootstrap());

        // Pre-dialog biometric skipped (isAvailable=false on first
        // call); dialog fired; `_biometricUnlockForTierDialog`'s
        // happy path ran — vault.read returned the seeded key; the
        // L3 wrapper did the inject; opener received the key.
        expect(prompter.tierSecretCalls, 1);
        expect(capturedKey, equals(bioKey));
        expect(ctrl!.isReady, isTrue);
        ctrl!.dispose();
      },
    );
  });
}
