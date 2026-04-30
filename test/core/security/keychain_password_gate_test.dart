import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/keychain_op_prompt_listener.dart';
import 'package:letsflutssh/app/keychain_pepper_prompt_listener.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:path/path.dart' as p;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Bootstrap FRB and start the production prompt listeners so the
  // gate's Rust actor (`keychain_password_gate_actor::set_password`
  // / `verify` / `clear`) can complete its keychain round-trip
  // against the test's mock `flutter_secure_storage` instead of
  // hanging on an unanswered `KeychainOpPromptRequest`.
  setUpAll(() async {
    await requireFrbLoaded();
    KeychainOpPromptListener.start();
    KeychainPepperPromptListener.start();
  });

  tearDownAll(() {
    KeychainOpPromptListener.stop();
    KeychainPepperPromptListener.stop();
  });

  late Directory tempDir;
  late Map<String, String> fakeKeychain;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('l2_gate_test_');
    fakeKeychain = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, Object?>() ?? {};
            switch (call.method) {
              case 'write':
                fakeKeychain[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return fakeKeychain[args['key']];
              case 'delete':
                fakeKeychain.remove(args['key']);
                return null;
              case 'containsKey':
                return fakeKeychain.containsKey(args['key']);
              case 'deleteAll':
                fakeKeychain.clear();
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  KeychainPasswordGate newGate() => KeychainPasswordGate(
    hashFileFactory: () async => File('${tempDir.path}/security_pass_hash.bin'),
  );

  group('KeychainPasswordGate', () {
    test('isConfigured starts false on a clean install', () async {
      expect(await newGate().isConfigured(), isFalse);
    });

    test('setPassword writes both disk hash + keychain pepper', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.isConfigured(), isTrue);
      expect(fakeKeychain.keys, contains('letsflutssh_l2_pepper'));
      expect(
        File('${tempDir.path}/security_pass_hash.bin').existsSync(),
        isTrue,
      );
    });

    test('verify returns true for the correct password', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.verify('hunter2'), isTrue);
    });

    test('verify returns false for a wrong password', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      expect(await gate.verify('hunter3'), isFalse);
    });

    test('verify is false when either half of the state is missing', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');

      // Drop only the keychain pepper — disk hash alone is useless.
      fakeKeychain.clear();
      expect(await gate.verify('hunter2'), isFalse);

      // Reset, then drop the disk hash.
      await gate.setPassword('hunter2');
      File('${tempDir.path}/security_pass_hash.bin').deleteSync();
      expect(await gate.verify('hunter2'), isFalse);
    });

    test('verify is false when the disk blob is corrupt', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      File(
        '${tempDir.path}/security_pass_hash.bin',
      ).writeAsStringSync('not json');
      expect(await gate.verify('hunter2'), isFalse);
    });

    test('clear drops hash file + pepper', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      await gate.clear();
      expect(await gate.isConfigured(), isFalse);
      expect(
        File('${tempDir.path}/security_pass_hash.bin').existsSync(),
        isFalse,
      );
      expect(fakeKeychain.containsKey('letsflutssh_l2_pepper'), isFalse);
    });

    test('setPassword twice rotates salt + pepper (hash changes)', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      final first = File(
        '${tempDir.path}/security_pass_hash.bin',
      ).readAsStringSync();
      await gate.setPassword('hunter2');
      final second = File(
        '${tempDir.path}/security_pass_hash.bin',
      ).readAsStringSync();
      expect(second, isNot(equals(first)));
      // The new state still verifies the same password.
      expect(await gate.verify('hunter2'), isTrue);
    });

    test('rateLimiter is null before setPassword runs', () async {
      final gate = newGate();
      expect(await gate.rateLimiter(), isNull);
    });

    test('rateLimiter records and persists failure + cooldown', () async {
      final gate = newGate();
      await gate.setPassword('hunter2');
      final limiter = await gate.rateLimiter();
      expect(limiter, isNotNull);
      // Force backend init via the async status path; the actor
      // needs its file_path + hmac_key bound before the first
      // recordFailure can land in a real slot (sync recordFailure
      // on a cold limiter routes through a no-op probe path).
      await (limiter! as PersistedRateLimiter).statusAsync();
      limiter.recordFailure();
      limiter.recordFailure();
      // Any locked limiter reports a non-zero cooldown.
      expect(limiter.status().failureCount, greaterThanOrEqualTo(1));
    });

    test('setPassword writes atomically — no .tmp sibling survives', () async {
      // A `File.writeAsBytes(flush: true)` crash mid-write used to
      // truncate the disk hash. `writeBytesAtomic` renames an
      // already-fsynced tmp file into place, so the target path is
      // only visible in a fully-written state. This test asserts the
      // atomic-rename pattern is wired up by looking for leftover
      // `.tmp*` siblings after a successful call.
      await newGate().setPassword('hunter2');
      final siblings = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('.tmp'))
          .toList();
      expect(
        siblings,
        isEmpty,
        reason:
            'writeBytesAtomic must rename the tmp file into place; no '
            '.tmp* sibling should remain.',
      );
    });

    test(
      'setPassword writes disk hash before keychain pepper (order invariant)',
      () async {
        // Load-bearing for L2 recovery. Disk-first order: a crash
        // between the two writes leaves the OLD hash still verifiable
        // under the OLD pepper still in the keychain. Keychain-first
        // would leave the keychain holding the NEW pepper with the
        // OLD disk hash — correct password stops verifying, user is
        // locked out until full reset.
        //
        // Fail the keychain write on purpose; expect the disk hash to
        // NOT survive (rollback) so `isConfigured()` stays false and
        // the wizard can re-provision cleanly.
        const keyHandler = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keyHandler, (call) async {
              if (call.method == 'write') {
                throw PlatformException(
                  code: 'keychain_unavailable',
                  message: 'simulated failure',
                );
              }
              return null;
            });

        final gate = newGate();
        // The Rust actor catches the PlatformException via the
        // KeychainOpPromptListener, rolls back the disk hash, then
        // throws an `L2 set_password: keychain write failed …;
        // rolled back disk hash` anyhow error so the caller can
        // surface the failure.
        await expectLater(
          () => gate.setPassword('hunter2'),
          throwsA(
            predicate(
              (e) => e.toString().contains('keychain write failed'),
              'rejects with the L2 set_password rollback error',
            ),
          ),
        );
        expect(
          File('${tempDir.path}/security_pass_hash.bin').existsSync(),
          isFalse,
          reason:
              'Keychain failure must roll back the disk hash — otherwise '
              'isConfigured() returns true but verify() can never succeed.',
        );
      },
    );

    test(
      'setPassword wipes rate_limit_state so a new HMAC does not look tampered',
      () async {
        // Regression gate: a user who set a password, failed a couple
        // of unlock attempts, then re-set the password used to land on
        // a 60-second cooldown on the next app launch. Cause: the
        // persisted rate-limit file was still signed with the *old*
        // HMAC, so the fresh limiter's HMAC-verify tripped the
        // tamper branch. Fix: setPassword deletes the state file;
        // this test pins that cleanup.
        final gate = newGate();
        await gate.setPassword('hunter2');
        final limiter1 = await gate.rateLimiter();
        // Init the actor before the first recordFailure (see the
        // sibling rateLimiter test for the same pattern).
        await (limiter1! as PersistedRateLimiter).statusAsync();
        limiter1.recordFailure();
        limiter1.recordFailure();
        // Wait for the fire-and-forget save to land on disk.
        await (limiter1 as PersistedRateLimiter).awaitPendingSave();
        expect(limiter1.status().failureCount, greaterThanOrEqualTo(1));

        await gate.setPassword('newpass');
        final limiter2 = await gate.rateLimiter();
        expect(limiter2, isNotNull);
        final status = await (limiter2! as PersistedRateLimiter).statusAsync();
        expect(
          status.failureCount,
          0,
          reason: 'setPassword must wipe rate-limit state',
        );
        expect(status.cooldownRemaining, Duration.zero);
      },
    );
  });
}
