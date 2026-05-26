import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/security_tier_switcher.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The tier-transition marker read/write helpers route through
  // `lfs_core::security::tier_transition_marker` for the 0600-hardened
  // atomic write, operating on the support dir pinned at
  // `configStoreInit`. Bootstrap FRB + pin a temp dir so the switcher
  // exercises the canonical Rust path.
  late Directory tempDir;

  setUpAll(() async {
    await requireFrbLoaded();
    tempDir = Directory.systemTemp.createTempSync('tier_switcher_test_');
    rust_config.configStoreInit(supportDir: tempDir.path);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  late SecurityTierSwitcher switcher;

  setUp(() async {
    // Stub the rekey — the FRB-backed default would call into the
    // native bridge, which the unit-test runner does not load. The
    // switcher's contract (write marker → rekey → apply wrapper …) is
    // the unit under test. The pinned dir is shared across the file,
    // so drop any marker a prior test left behind.
    switcher = SecurityTierSwitcher(rekeyFromSecret: (_) async {});
    await switcher.clearMarker();
  });

  group('SecurityTierSwitcher.switchTierFromSecret', () {
    test(
      'walks every step in order and clears the marker at the end',
      () async {
        final order = <String>[];
        await switcher.switchTierFromSecret(
          secretId: 'tier-switch.dbkey.test',
          targetMarkerPayload: '{"tier":"keychain"}',
          applyWrapperFromSecret: (_) async => order.add('applyWrapper'),
          persistConfigFromSecret: (_) async => order.add('persistConfig'),
          clearPrevious: () async => order.add('clearPrevious'),
        );
        expect(order, ['applyWrapper', 'persistConfig', 'clearPrevious']);
        expect(await switcher.readPendingMarker(), isNull);
      },
    );

    test('marker is written before rekey and cleared after success', () async {
      String? observedMarker;
      await switcher.switchTierFromSecret(
        secretId: 'tier-switch.dbkey.test',
        targetMarkerPayload: '{"tier":"paranoid"}',
        applyWrapperFromSecret: (_) async {
          // By the time the wrapper runs, the marker has been written
          // and rekey has succeeded. Read it back to confirm.
          observedMarker = await switcher.readPendingMarker();
        },
        persistConfigFromSecret: (_) async {},
        clearPrevious: () async {},
      );
      expect(observedMarker, '{"tier":"paranoid"}');
      expect(await switcher.readPendingMarker(), isNull);
    });

    test(
      'applyWrapper failure leaves marker in place for crash recovery',
      () async {
        await expectLater(
          switcher.switchTierFromSecret(
            secretId: 'tier-switch.dbkey.test',
            targetMarkerPayload: '{"tier":"hardware"}',
            applyWrapperFromSecret: (_) async =>
                throw StateError('vault write failed'),
            persistConfigFromSecret: (_) async {},
            clearPrevious: () async {},
          ),
          throwsA(isA<StateError>()),
        );
        // Marker survives — next startup can complete or roll back.
        expect(await switcher.readPendingMarker(), '{"tier":"hardware"}');
      },
    );

    test('clearMarker is idempotent on a clean dir', () async {
      await switcher.clearMarker();
      expect(await switcher.readPendingMarker(), isNull);
    });

    test('every switch runs rekey exactly once', () async {
      var rekeyCalls = 0;
      final invariantSwitcher = SecurityTierSwitcher(
        rekeyFromSecret: (_) async => rekeyCalls++,
      );
      await invariantSwitcher.switchTierFromSecret(
        secretId: 'tier-switch.dbkey.test',
        targetMarkerPayload: '{"tier":"keychain"}',
        applyWrapperFromSecret: (_) async {},
        persistConfigFromSecret: (_) async {},
        clearPrevious: () async {},
      );
      expect(rekeyCalls, 1);
    });

    test('rekey failure leaves the marker behind for crash recovery', () async {
      // Mirror of the "applyWrapper failure" test above, but with the
      // failure injected in step 3 (the rekey itself). The marker
      // policy is identical: it must survive so startup can see the
      // pending transition and recover.
      final failSwitcher = SecurityTierSwitcher(
        rekeyFromSecret: (_) async => throw StateError('PRAGMA rekey failed'),
      );
      var wrapCalls = 0;
      await expectLater(
        failSwitcher.switchTierFromSecret(
          secretId: 'tier-switch.dbkey.test',
          targetMarkerPayload: '{"tier":"rekey-victim"}',
          applyWrapperFromSecret: (_) async => wrapCalls++,
          persistConfigFromSecret: (_) async {},
          clearPrevious: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(wrapCalls, 0, reason: 'wrapper must not run after rekey fails');
      expect(
        await failSwitcher.readPendingMarker(),
        '{"tier":"rekey-victim"}',
        reason: 'marker survives a rekey failure for later recovery',
      );
    });

    test(
      'clearPrevious failure leaves the marker behind — startup recovers',
      () async {
        // Pin the contract for step 6: if the old-tier teardown throws,
        // the marker must survive so the next startup sees the pending
        // transition and can finish or roll back. Step 7 (clearMarker)
        // is gated on step 6 completing, so a thrown clearPrevious
        // naturally preserves the marker.
        final clearFailSwitcher = SecurityTierSwitcher(
          rekeyFromSecret: (_) async {},
        );
        await expectLater(
          clearFailSwitcher.switchTierFromSecret(
            secretId: 'tier-switch.dbkey.test',
            targetMarkerPayload: '{"tier":"keychain"}',
            applyWrapperFromSecret: (_) async {},
            persistConfigFromSecret: (_) async {},
            clearPrevious: () async =>
                throw StateError('previous slot teardown failed'),
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          await clearFailSwitcher.readPendingMarker(),
          '{"tier":"keychain"}',
          reason:
              'a thrown clearPrevious must leave the marker so recovery '
              'can finish on next launch',
        );
      },
    );

    test(
      'each (src, dst) tier pair runs marker + rekey + callbacks once',
      () async {
        // Enumerate the tier-label cross product and exercise the
        // switcher for every pair. `src` is informational — the
        // switcher does not branch on it; the invariant being asserted
        // is "regardless of the starting tier, the same orchestration
        // runs for the same target". Each successful switch clears the
        // marker, so iterations share the pinned dir cleanly.
        const tiers = ['plaintext', 'keychain', 'hardware', 'paranoid'];
        for (final src in tiers) {
          for (final dst in tiers) {
            var rekey = 0;
            var wrap = 0;
            var persist = 0;
            var clear = 0;
            final pairSwitcher = SecurityTierSwitcher(
              rekeyFromSecret: (_) async => rekey++,
            );
            await pairSwitcher.switchTierFromSecret(
              secretId: 'tier-switch.dbkey.$src-$dst',
              targetMarkerPayload: '{"src":"$src","dst":"$dst"}',
              applyWrapperFromSecret: (_) async => wrap++,
              persistConfigFromSecret: (_) async => persist++,
              clearPrevious: () async => clear++,
            );
            expect(rekey, 1, reason: '$src → $dst rekey count');
            expect(wrap, 1, reason: '$src → $dst wrap count');
            expect(persist, 1, reason: '$src → $dst persist count');
            expect(clear, 1, reason: '$src → $dst clear count');
            expect(
              await pairSwitcher.readPendingMarker(),
              isNull,
              reason: '$src → $dst marker cleared',
            );
          }
        }
      },
    );

    test('rekeyFromSecret receives the caller-supplied secretId', () async {
      // Pin the contract: the switcher does not mutate or replace the
      // secret id between accept and forward — every consumer gets
      // exactly the bytes the caller staged.
      String? observedRekeyId;
      final pinSwitcher = SecurityTierSwitcher(
        rekeyFromSecret: (id) async => observedRekeyId = id,
      );
      String? observedWrapId;
      String? observedPersistId;
      const id = 'tier-switch.dbkey.deadbeef';
      await pinSwitcher.switchTierFromSecret(
        secretId: id,
        targetMarkerPayload: '{"tier":"keychain"}',
        applyWrapperFromSecret: (handed) async => observedWrapId = handed,
        persistConfigFromSecret: (handed) async => observedPersistId = handed,
        clearPrevious: () async {},
      );
      expect(observedRekeyId, id);
      expect(observedWrapId, id);
      expect(observedPersistId, id);
    });
  });
}
