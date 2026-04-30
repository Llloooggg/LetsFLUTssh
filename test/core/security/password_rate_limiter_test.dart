import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('HardwareRateLimiter', () {
    test('follows the shared backoff schedule on failures', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = HardwareRateLimiter(now: () => clock);
      limiter.recordFailure();
      expect(limiter.status().cooldownRemaining!.inSeconds, 1);
      limiter.recordFailure();
      expect(limiter.status().cooldownRemaining!.inSeconds, 2);
    });

    test('recordSuccess resets state', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = HardwareRateLimiter(now: () => clock);
      limiter.recordFailure();
      limiter.recordSuccess();
      expect(limiter.status().isLocked, isFalse);
    });
  });

  group('PersistedRateLimiter', () {
    late Directory tempDir;
    late Uint8List hmacKey;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('persisted_limiter_');
      hmacKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File stateFile() => File('${tempDir.path}/rate_limit_state.bin');

    Future<PersistedRateLimiter> makeLimiter({
      DateTime Function()? now,
      Uint8List? key,
    }) async {
      return PersistedRateLimiter(
        hmacKey: key ?? hmacKey,
        stateFileFactory: () async => stateFile(),
        now: now,
      );
    }

    test('fresh state reports unlocked even before first write', () async {
      final limiter = await makeLimiter();
      final status = await limiter.statusAsync();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });

    test('recordFailure persists and survives restart', () async {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final first = await makeLimiter(now: () => clock);
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

      final reborn = await makeLimiter(now: () => clock);
      final status = await reborn.statusAsync();
      expect(status.failureCount, 2);
      expect(status.isLocked, isTrue);
    });

    test('recordSuccess persists reset', () async {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final first = await makeLimiter(now: () => clock);
      await first.statusAsync();
      first.recordFailure();
      first.recordSuccess();
      await first.awaitPendingSave();

      final reborn = await makeLimiter(now: () => clock);
      final status = await reborn.statusAsync();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });

    test('tampered state file is detected and forces max cooldown', () async {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final first = await makeLimiter(now: () => clock);
      await first.statusAsync();
      first.recordFailure();
      await first.awaitPendingSave();

      // Overwrite the file with garbage.
      await stateFile().writeAsString('not json');

      final reborn = await makeLimiter(now: () => clock);
      final status = await reborn.statusAsync();
      expect(status.isLocked, isTrue);
      expect(status.cooldownRemaining!.inSeconds, inInclusiveRange(1, 120));
    });

    test('wrong hmac key (e.g. password cycled) fails tamper check', () async {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final first = await makeLimiter(now: () => clock);
      await first.statusAsync();
      first.recordFailure();
      await first.awaitPendingSave();

      final wrongKey = Uint8List.fromList(List<int>.filled(32, 0xFF));
      final reborn = await makeLimiter(now: () => clock, key: wrongKey);
      final status = await reborn.statusAsync();
      expect(status.isLocked, isTrue);
    });
  });
}
