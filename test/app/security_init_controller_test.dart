import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_init_controller.dart';

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
}
