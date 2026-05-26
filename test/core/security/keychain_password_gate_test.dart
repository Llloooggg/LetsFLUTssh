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
/// (missing file → null, malformed blob → null) and the default
/// constructor wiring path. Each branch survives without a working
/// keychain because the early returns short-circuit before the OS-API
/// edge. The gate ops resolve the support dir pinned Rust-side at
/// `configStoreInit`, so the test pins a temp dir up front.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final gate = KeychainPasswordGate();

  setUpAll(() async {
    await requireFrbLoaded();
    tmp = Directory.systemTemp.createTempSync('lfs_keychain_gate_');
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  tearDown(() {
    // Clear the on-disk hash a test may have written so the pinned dir
    // starts clean for the next one.
    final hash = File('${tmp.path}/security_pass_hash.bin');
    if (hash.existsSync()) hash.deleteSync();
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('rateLimiter — Dart-side fallback paths', () {
    test('returns null when the hash file does not exist', () async {
      // No setPassword was called → no on-disk hash → the Rust builder
      // returns `None` and the Dart caller maps it to null.
      expect(await gate.rateLimiter(), isNull);
    });

    test('returns null on a malformed hash file', () async {
      // Drop garbage where the gate expects an envelope. The Rust
      // decoder collapses every "no recoverable HMAC" outcome to the
      // null branch (or raises, which the Dart catch also maps to null)
      // so the caller falls through to "no rate limiter available".
      final file = File('${tmp.path}/security_pass_hash.bin');
      await file.writeAsString('not a valid keychain hash blob');
      expect(await gate.rateLimiter(), isNull);
    });
  });

  group('default constructor', () {
    test('builds without arguments — production wiring path', () {
      // Constructor must not throw — the gate ops resolve the pinned
      // support dir lazily on first call.
      expect(KeychainPasswordGate.new, returnsNormally);
    });
  });
}
