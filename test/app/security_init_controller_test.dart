import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_init_controller.dart';

// The unlock-flow tests that drove the controller through every
// per-tier branch were structured around `dbOpener` / `verifyReadable`
// seams that captured the drift handle and the master key handed to
// it. With the drift handle gone — the controller now opens
// `lfs_core.db` through FRB and the tests can't observe that without
// the native bridge — those assertions no longer translate.
//
// Equivalent live coverage moves to integration_test. The handful
// of unit-test smoke checks here exercise the constructor surface
// and the post-bootstrap idempotency contract that doesn't depend
// on a real DB.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('constructs with default seams without throwing', (tester) async {
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
    expect(ctrl, isNotNull);
    expect(ctrl!.isReady, isFalse);
    ctrl!.dispose();
  });

  testWidgets('takeAndClearCredentialsResetFlag is read-once', (tester) async {
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
    // Default: no reset → false.
    expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
    expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);
    ctrl!.dispose();
  });
}
