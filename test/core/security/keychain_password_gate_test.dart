/// Coverage for [KeychainPasswordGate] — the L2 UX-only password gate.
///
/// The Dart class is a thin façade over
/// `lfs_core::security::keychain_password_gate_actor`; the meaningful
/// branches still on the Dart side are (1) the `rateLimiter()`
/// fallback chain (missing file → null without an FRB call,
/// AnyhowException → null, generic error → null + log), (2) the
/// support-dir wiring through the constructor's `hashFileFactory`,
/// and (3) the full set / verify / clear lifecycle round-trip.
///
/// Lifecycle tests gate on a runtime probe of
/// `secureStorageSecretServiceReachable()` so a CI / WSL run with no
/// running keyring daemon prints a clear `[skipped — …]` marker and
/// keeps the suite green. Dev / release QA runs against a real
/// keyring exercise the round-trip end-to-end.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/src/rust/api/secure_key_storage.dart' as sks;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tmp;
  late KeychainPasswordGate gate;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lfs_keychain_gate_');
    gate = KeychainPasswordGate(
      hashFileFactory: () async => File('${tmp.path}/security_pass_hash.bin'),
    );
  });

  tearDown(() async {
    // Best effort — clear() may fail when the keyring is unreachable;
    // the temp dir wipe still prevents on-disk leakage.
    try {
      await gate.clear();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('rateLimiter — Dart-side fallback paths', () {
    test('returns null when the hash file does not exist', () async {
      // No setPassword was called → no on-disk hash → the early
      // `await file.exists()` short-circuits without an FRB decode.
      expect(await gate.rateLimiter(), isNull);
    });

    test('returns null on a malformed hash file (AnyhowException)', () async {
      // Drop garbage where the gate expects a JSON envelope. The
      // Rust decoder raises AnyhowException; the Dart catch maps to
      // null so the caller falls through to "no rate limiter
      // available" instead of bubbling the throw.
      final file = File('${tmp.path}/security_pass_hash.bin');
      await file.writeAsString('not a valid keychain hash blob');
      expect(await gate.rateLimiter(), isNull);
    });

    test('factory failure surfaces null, not an exception', () async {
      final broken = KeychainPasswordGate(
        hashFileFactory: () async => throw StateError('factory boom'),
      );
      expect(await broken.rateLimiter(), isNull);
    });
  });

  group('full lifecycle (gated on keyring reachability)', () {
    test('isConfigured / setPassword / verify / clear round-trip', () async {
      final reachable = await sks.secureStorageSecretServiceReachable();
      if (!reachable) {
        markTestSkipped(
          'OS keychain unreachable — Linux without a libsecret '
          'provider, or CI runner without Keychain / Credential '
          'Manager. Release QA on real hardware exercises this path.',
        );
        return;
      }

      // Fresh tmp dir → no gate configured.
      expect(await gate.isConfigured(), isFalse);

      // Set a password — disk salt + keychain pepper land in their
      // respective slots; the resulting HMAC is on disk.
      final password = Uint8List.fromList('hunter2'.codeUnits);
      await gate.setPassword(password);
      expect(await gate.isConfigured(), isTrue);

      // Correct password verifies; wrong password rejects without
      // throwing.
      expect(await gate.verify(password), isTrue);
      expect(
        await gate.verify(Uint8List.fromList('hunter3'.codeUnits)),
        isFalse,
      );

      // Rate-limiter handle now resolves to a real PersistedRateLimiter
      // (HMAC available + state file path is set).
      expect(await gate.rateLimiter(), isNotNull);

      // Clear drops the disk file + the keychain pepper; isConfigured
      // returns false again.
      await gate.clear();
      expect(await gate.isConfigured(), isFalse);
    });

    test('rateLimiter is null after clear', () async {
      final reachable = await sks.secureStorageSecretServiceReachable();
      if (!reachable) {
        markTestSkipped('keyring unreachable in this environment');
        return;
      }
      final password = Uint8List.fromList('correct horse'.codeUnits);
      await gate.setPassword(password);
      expect(await gate.rateLimiter(), isNotNull);
      await gate.clear();
      expect(await gate.rateLimiter(), isNull);
    });

    test('setPassword overwrites — second call replaces the first', () async {
      final reachable = await sks.secureStorageSecretServiceReachable();
      if (!reachable) {
        markTestSkipped('keyring unreachable in this environment');
        return;
      }
      final pwA = Uint8List.fromList('alpha'.codeUnits);
      final pwB = Uint8List.fromList('bravo'.codeUnits);
      await gate.setPassword(pwA);
      expect(await gate.verify(pwA), isTrue);
      await gate.setPassword(pwB);
      // The second setPassword fully replaces the prior credentials —
      // verifying with the OLD password must now fail, even though
      // the gate is still "configured".
      expect(await gate.verify(pwA), isFalse);
      expect(await gate.verify(pwB), isTrue);
    });
  });

  group('default constructor', () {
    test('builds without arguments — production wiring path', () {
      // Constructor must not throw — it captures the default support-dir
      // factory but does not invoke it until the first call. Production
      // bootstrap pins one of these for the entire process lifetime.
      expect(() => KeychainPasswordGate(), returnsNormally);
    });
  });
}
