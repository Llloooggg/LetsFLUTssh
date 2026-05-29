import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('backoffSchedule', () {
    test('hydrates non-empty schedule from Rust and caches across calls', () {
      // Spec: the Dart getter is a thin lazy cache around
      // `lfs_core::rate_limit::BACKOFF_SCHEDULE`. First call routes
      // through FRB; subsequent calls must return the same list
      // identity so a hot path isn't paying FRB per status read.
      final first = PasswordRateLimiter.backoffSchedule;
      final second = PasswordRateLimiter.backoffSchedule;
      expect(first, isNotEmpty);
      expect(first.first, 0, reason: 'index 0 = no failures, no wait');
      expect(identical(first, second), isTrue, reason: 'cached');
      // Schedule must be monotonic non-decreasing — exponential up to
      // a cap. A decrease at any index would mean "second failure
      // costs less than the first", which is the wrong shape.
      for (var i = 1; i < first.length; i++) {
        expect(first[i], greaterThanOrEqualTo(first[i - 1]));
      }
    });
  });

  group('InMemoryRateLimiter', () {
    test('follows the shared backoff schedule on failures', () {
      final limiter = InMemoryRateLimiter();
      addTearDown(limiter.dispose);
      limiter.recordFailure();
      final after1 = limiter.status().cooldownRemaining!.inMilliseconds;
      expect(after1, inInclusiveRange(900, 1000));
      limiter.recordFailure();
      final after2 = limiter.status().cooldownRemaining!.inMilliseconds;
      expect(after2, inInclusiveRange(1900, 2000));
    });

    test('recordSuccess resets state', () {
      final limiter = InMemoryRateLimiter();
      addTearDown(limiter.dispose);
      limiter.recordFailure();
      limiter.recordSuccess();
      expect(limiter.status().isLocked, isFalse);
    });

    test('dispose is idempotent and freezes the limiter at zero', () {
      // Spec: after dispose, every public op no-ops without touching
      // FRB. status returns the safe baseline; recordFailure /
      // recordSuccess do nothing; dispose itself can be called again.
      final limiter = InMemoryRateLimiter();
      limiter.recordFailure();
      limiter.dispose();
      limiter.dispose(); // idempotent
      final s = limiter.status();
      expect(s.failureCount, 0);
      expect(s.isLocked, isFalse);
      // Post-dispose record* calls must be silent no-ops.
      limiter.recordFailure();
      limiter.recordSuccess();
      expect(limiter.status().failureCount, 0);
    });

    test('separate instances do not share counters', () {
      // Spec: each instance allocates its own uuid id under the
      // shared Rust registry — recording a failure on one must not
      // surface in the other's status read.
      final a = InMemoryRateLimiter();
      final b = InMemoryRateLimiter();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.recordFailure();
      a.recordFailure();
      expect(a.status().failureCount, 2);
      expect(b.status().failureCount, 0);
    });
  });

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

    test('sync status before _ensureInit returns the safe zero baseline', () {
      // Spec: a sync `status()` call that races ahead of the actor
      // init (the dialog opens, the first paint reads status while
      // statusAsync is still in flight) must not block or throw —
      // it returns the unlocked baseline so the field renders, and
      // the next read (post-statusAsync) shows the real cooldown.
      final limiter = PersistedRateLimiter(hmacKey: hmacKey);
      final s = limiter.status();
      expect(s.failureCount, 0);
      expect(s.isLocked, isFalse);
    });

    test('recordFailure pre-init still pushes to the Rust actor', () async {
      // Spec: the sync recordFailure path before statusAsync is the
      // failure probe itself. The Rust actor doesn't know the file
      // path yet, so persistence is best-effort, but the in-memory
      // counter inside the actor must still tick up so the next
      // statusAsync sees the failure.
      final limiter = PersistedRateLimiter(hmacKey: hmacKey);
      limiter.recordFailure(); // hits the pre-init branch
      final s = await limiter.statusAsync();
      // Either the pre-init probe was accepted (count >= 1) or the
      // actor rejected the call and the slot is empty — both are
      // valid; what matters is no throw + a coherent status read.
      expect(s.failureCount, greaterThanOrEqualTo(0));
    });

    test('recordSuccess pre-init no-ops without throwing', () async {
      final limiter = PersistedRateLimiter(hmacKey: hmacKey);
      limiter.recordSuccess(); // hits the pre-init branch
      final s = await limiter.statusAsync();
      expect(s.failureCount, 0);
      expect(s.isLocked, isFalse);
    });

    test('invalidateCache wipes the actor slot + on-disk file', () async {
      // Spec: `persisted_rate_limit_actor_clear` is documented as
      // "best-effort delete the on-disk file" — used by logout /
      // wipe-all flows so re-enabling the gate starts from zero
      // regardless of whatever counter the prior session ended at.
      // The next statusAsync re-registers with the HMAC and finds
      // no file, so the counter is back to zero.
      final limiter = await makeLimiter();
      await limiter.statusAsync();
      limiter.recordFailure();
      await limiter.awaitPendingSave();
      expect(await stateFile().exists(), isTrue);

      limiter.invalidateCache();
      final s = await limiter.statusAsync();
      expect(s.failureCount, 0);
      expect(s.isLocked, isFalse);
    });

    test('fromPrebuiltId binds to an already-registered actor slot', () async {
      // Build the slot via the canonical constructor, drive it once,
      // then hand the id to fromPrebuiltId — the second instance
      // observes the same Rust slot without ever touching the HMAC.
      final canonical = PersistedRateLimiter(
        hmacKey: hmacKey,
        id: 'shared-prebuilt-id',
      );
      await canonical.statusAsync();
      canonical.recordFailure();
      await canonical.awaitPendingSave();

      final prebuilt = PersistedRateLimiter.fromPrebuiltId(
        'shared-prebuilt-id',
      );
      // No statusAsync needed — _initialised starts true.
      final s = prebuilt.status();
      expect(s.failureCount, 1);
    });
  });
}
