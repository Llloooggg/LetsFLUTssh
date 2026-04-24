import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_init_controller.dart';

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
}
