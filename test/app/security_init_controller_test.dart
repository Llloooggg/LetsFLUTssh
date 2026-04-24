import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/providers/security_provider.dart';

import '../helpers/fake_native_plugins.dart';
import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';

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
    // seams (dbOpener / dbFileExists / verifyReadable) without going
    // through `bootstrap()`. The full migration + first-launch chain
    // has a dialog-harness dependency tracked separately; the path
    // we can pin today is `reopenAfterUnlock` — it walks
    // `_injectDatabase` exactly once with a key from
    // `securityStateProvider`, so it exercises the same store-fanout
    // + probe hooks that bootstrap would.

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
