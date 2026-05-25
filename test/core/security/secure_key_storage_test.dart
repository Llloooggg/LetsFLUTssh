import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/src/rust/api/security_capabilities.dart';

/// SecureKeyStorage round-trip / probe / delete coverage moved
/// Rust-side after the cleanup arc retired
/// `flutter_secure_storage`. Every platform now routes through
/// `lfs_os_security::secure_key_storage::*`, whose unit suite
/// exercises the real OS backend on each target (libsecret on the
/// Linux CI runner, SecItem on darwin, CredRead/Write/Delete on
/// Windows, AndroidKeyStore via JNI on Android). Re-running those
/// flows from Dart with a MethodChannel mock would only re-validate
/// FRB plumbing already covered by the FRB codegen + bus tests.
///
/// What stays Dart-side: the [DbKeyringProbeResult] enum vocabulary
/// (Settings UI maps reason codes to ARB strings; a silent new enum
/// value without a matching locale key surfaces as a blank tooltip)
/// and the [SecureKeyStorage.enableRuntimeSubprocessProbes] static
/// latch contract.
void main() {
  group('SecureKeyStorage Dart-side surface', () {
    test('probeSecretServiceReachability: false short-circuits the Linux '
        'probe to available without a D-Bus connect', () async {
      // The opt-out flag exists so widget tests get a deterministic
      // `available` without a live session-bus connect. On Linux that
      // is a pure-Dart short-circuit (no FRB call), so we can assert
      // the observable effect directly; on other platforms `probe()`
      // round-trips through the OS keychain over FRB, which is out of
      // scope for a unit test (see the file header).
      final result = await SecureKeyStorage(
        probeSecretServiceReachability: false,
      ).probe();
      expect(result, DbKeyringProbeResult.available);
    }, skip: Platform.isLinux ? false : 'Linux-only pure-Dart short-circuit');

    test(
      'DbKeyringProbeResult carries every documented classification label',
      () {
        expect(DbKeyringProbeResult.values, <DbKeyringProbeResult>[
          DbKeyringProbeResult.available,
          DbKeyringProbeResult.linuxNoSecretService,
          DbKeyringProbeResult.probeFailed,
        ]);
      },
    );
  });
}
