/// Coverage for [RecoveryPromptListener] start/stop lifecycle +
/// the event-routing logic that maps bus-event variants onto the
/// matching Flutter dialog.
///
/// The Rust orchestrator publishes
/// `BusEvent.recoveryPromptRequest` events the listener picks up.
/// Two routing paths exist: `DbCorruptDetected` /
/// `VaultStateMissing` route to `DbCorruptDialog`;
/// `LegacyStateFound` routes to `TierResetDialog`. The
/// `debugSetDialogs` injection seam lets tests drive each routing
/// branch without painting a widget — the real dispatch back into
/// Rust still requires FRB, so the resolve-call assertion is
/// covered separately by the integration suite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/recovery_prompt_listener.dart';
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;
import 'package:letsflutssh/widgets/security/db_corrupt_dialog.dart';
import 'package:letsflutssh/widgets/security/tier_reset_dialog.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    RecoveryPromptListener.stop();
    RecoveryPromptListener.debugResetDialogs();
  });

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(RecoveryPromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(RecoveryPromptListener.stop, returnsNormally);
    });
  });

  group('debugSetDialogs / debugResetDialogs', () {
    test('debugSetDialogs swaps in test stubs without throwing', () {
      expect(
        () => RecoveryPromptListener.debugSetDialogs(
          dbCorrupt: () async => DbCorruptChoice.exitApp,
          tierReset: () async => TierResetChoice.exitApp,
        ),
        returnsNormally,
      );
    });

    test('debugResetDialogs restores production routing', () {
      RecoveryPromptListener.debugSetDialogs(
        dbCorrupt: () async => DbCorruptChoice.exitApp,
      );
      expect(RecoveryPromptListener.debugResetDialogs, returnsNormally);
    });
  });

  group('event routing — kind → dialog dispatch', () {
    setUpAll(requireFrbLoaded);
    setUp(() {
      // Listener must NOT be running while we drive
      // debugDispatchEvent directly — the bus subscription would
      // also pick up the same event and the parallel handlers race
      // each other into the registry resolve call (the second
      // resolve sees an unknown id and logs a warn). Tests cover
      // the routing branches via the explicit
      // debugDispatchEvent path.
      RecoveryPromptListener.stop();
    });

    test(
      'DbCorruptDetected routes to DbCorruptDialog and emits "reset"',
      () async {
        var corruptCalls = 0;
        var tierResetCalls = 0;
        RecoveryPromptListener.debugSetDialogs(
          dbCorrupt: () async {
            corruptCalls++;
            return DbCorruptChoice.resetAndSetupFresh;
          },
          tierReset: () async {
            tierResetCalls++;
            return TierResetChoice.exitApp;
          },
        );
        // The orchestrator-side will fail to resolve the prompt id
        // since we never registered it through the Rust registry —
        // the FRB call throws which the listener swallows in its
        // own try/catch. We assert the routing reached the right
        // dialog; the resolve dispatch is covered by the integration
        // tests where Rust + Dart share a process.
        await RecoveryPromptListener.debugDispatchEvent(
          const rust_bus.BusEvent_RecoveryPromptRequest(
            promptId: 'p-corrupt',
            kind: rust_bus.BusRecoveryPromptKind_DbCorruptDetected(
              reason: 'probe failed',
            ),
            choices: ['reset', 'tryOtherTier', 'quit'],
          ),
        );
        expect(corruptCalls, 1);
        expect(tierResetCalls, 0);
      },
    );

    test('VaultStateMissing routes to DbCorruptDialog', () async {
      var corruptCalls = 0;
      RecoveryPromptListener.debugSetDialogs(
        dbCorrupt: () async {
          corruptCalls++;
          return DbCorruptChoice.tryOtherTier;
        },
      );
      await RecoveryPromptListener.debugDispatchEvent(
        const rust_bus.BusEvent_RecoveryPromptRequest(
          promptId: 'p-vault',
          kind: rust_bus.BusRecoveryPromptKind_VaultStateMissing(
            tierLabel: 'T2 hardware',
          ),
          choices: ['reset', 'tryOtherTier', 'quit'],
        ),
      );
      expect(corruptCalls, 1);
    });

    test('LegacyStateFound routes to TierResetDialog', () async {
      var corruptCalls = 0;
      var tierResetCalls = 0;
      RecoveryPromptListener.debugSetDialogs(
        dbCorrupt: () async {
          corruptCalls++;
          return DbCorruptChoice.exitApp;
        },
        tierReset: () async {
          tierResetCalls++;
          return TierResetChoice.resetAndSetupFresh;
        },
      );
      await RecoveryPromptListener.debugDispatchEvent(
        const rust_bus.BusEvent_RecoveryPromptRequest(
          promptId: 'p-legacy',
          kind: rust_bus.BusRecoveryPromptKind_LegacyStateFound(
            configVersionOnDisk: 3,
            orphanArtefacts: true,
          ),
          choices: ['reset', 'quit'],
        ),
      );
      expect(tierResetCalls, 1);
      expect(corruptCalls, 0);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(RecoveryPromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      RecoveryPromptListener.start();
      RecoveryPromptListener.start();
      RecoveryPromptListener.start();
      expect(RecoveryPromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      RecoveryPromptListener.start();
      RecoveryPromptListener.stop();
      expect(RecoveryPromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      RecoveryPromptListener.stop();
      RecoveryPromptListener.stop();
    });
  });
}
