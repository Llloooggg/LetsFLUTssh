import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('HardwareRateLimiter', () {
    test('follows the shared backoff schedule on failures', () {
      // FRB path: status snapshots Rust's nextRetryAt minus
      // SystemTime::now. We assert milli-second ranges instead of
      // an exact integer-seconds match because the FRB hop runs at
      // a few hundred microseconds — `inSeconds` rounds 999 ms down
      // to 0. The schedule math (1 s → 2 s → ...) lives in Rust;
      // the test here is "the limiter applied the schedule", not
      // "the constants are 1 and 2".
      final limiter = HardwareRateLimiter();
      addTearDown(limiter.dispose);
      limiter.recordFailure();
      final after1 = limiter.status().cooldownRemaining!.inMilliseconds;
      expect(after1, inInclusiveRange(900, 1000));
      limiter.recordFailure();
      final after2 = limiter.status().cooldownRemaining!.inMilliseconds;
      expect(after2, inInclusiveRange(1900, 2000));
    });

    test('recordSuccess resets state', () {
      final limiter = HardwareRateLimiter();
      addTearDown(limiter.dispose);
      limiter.recordFailure();
      limiter.recordSuccess();
      expect(limiter.status().isLocked, isFalse);
    });
  });

  group('PersistedRateLimiter', () {
    late Directory tempDir;
    late Uint8List hmacKey;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('persisted_limiter_');
      // The actor resolves `<support>/rate_limit_state.bin` from the
      // dir pinned at configStoreInit; pin this temp dir so the
      // restart-persistence + tamper assertions hit a known file.
      rust_config.configStoreInit(supportDir: tempDir.path);
    });

    tearDownAll(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File stateFile() => File('${tempDir.path}/rate_limit_state.bin');

    setUp(() {
      hmacKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
      // Shared pinned dir across the group — drop any persisted state a
      // prior test left so each starts from a clean limiter file.
      final f = stateFile();
      if (f.existsSync()) f.deleteSync();
    });

    Future<PersistedRateLimiter> makeLimiter({Uint8List? key}) async {
      return PersistedRateLimiter(hmacKey: key ?? hmacKey);
    }

    test('fresh state reports unlocked even before first write', () async {
      final limiter = await makeLimiter();
      final status = await limiter.statusAsync();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });

    test('recordFailure persists and survives restart', () async {
      final first = await makeLimiter();
      // statusAsync triggers `_ensureBackend` which calls
      // `init_or_get(state_file_path)` against the Rust actor — the
      // sync probe path in `recordFailure` doesn't know the file
      // path, so without this prologue the actor records in-memory
      // but never persists. Same shape as the production unlock
      // dialog, which awaits statusAsync on first frame.
      await first.statusAsync();
      first.recordFailure();
      first.recordFailure();
      // Allow the fire-and-forget save to flush.
      await first.awaitPendingSave();
      expect(await stateFile().exists(), isTrue);

      final reborn = await makeLimiter();
      final status = await reborn.statusAsync();
      expect(status.failureCount, 2);
      expect(status.isLocked, isTrue);
    });

    test('recordSuccess persists reset', () async {
      final first = await makeLimiter();
      await first.statusAsync();
      first.recordFailure();
      first.recordSuccess();
      await first.awaitPendingSave();

      final reborn = await makeLimiter();
      final status = await reborn.statusAsync();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });

    test('tampered state file is detected and forces max cooldown', () async {
      final first = await makeLimiter();
      await first.statusAsync();
      first.recordFailure();
      await first.awaitPendingSave();

      // Overwrite the file with garbage.
      await stateFile().writeAsString('not json');

      final reborn = await makeLimiter();
      final status = await reborn.statusAsync();
      expect(status.isLocked, isTrue);
      expect(status.cooldownRemaining!.inSeconds, inInclusiveRange(1, 120));
    });

    test('wrong hmac key (e.g. password cycled) fails tamper check', () async {
      final first = await makeLimiter();
      await first.statusAsync();
      first.recordFailure();
      await first.awaitPendingSave();

      final wrongKey = Uint8List.fromList(List<int>.filled(32, 0xFF));
      final reborn = await makeLimiter(key: wrongKey);
      final status = await reborn.statusAsync();
      expect(status.isLocked, isTrue);
    });
  });
}
