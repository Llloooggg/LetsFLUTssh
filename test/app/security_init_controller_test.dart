import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';

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
}
