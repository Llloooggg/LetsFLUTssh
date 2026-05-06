/// Coverage for [KeychainPasswordGate] — Dart-side branches that
/// run on every platform / CI runner.
///
/// The full set / verify / clear lifecycle round-trip is intentionally
/// out of scope here: it requires a reachable OS keychain (libsecret
/// + running keyring daemon on Linux, login keychain on macOS,
/// Credential Manager on Windows). Headless GitHub-Actions Linux
/// runners do not have libsecret wired up, so a lifecycle test
/// would always print `[skipped]` there — which is no test at all.
/// Real-keychain coverage lives in the user's release-QA matrix on
/// dev / production hardware.
///
/// What's portable: the Dart-side `rateLimiter()` fallback chain
/// (missing file → null without an FRB call, AnyhowException → null,
/// generic factory failure → null), and the default-constructor
/// wiring path. Each branch survives without a working keychain
/// because the early returns short-circuit before the FRB / OS-API
/// edge.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';

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

  tearDown(() {
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

  group('default constructor', () {
    test('builds without arguments — production wiring path', () {
      // Constructor must not throw — it captures the default support-dir
      // factory but does not invoke it until the first call. Production
      // bootstrap pins one of these for the entire process lifetime.
      expect(KeychainPasswordGate.new, returnsNormally);
    });
  });
}
