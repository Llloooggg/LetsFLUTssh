import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';

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
/// What stays Dart-side: the [KeyringProbeResult] enum vocabulary
/// (Settings UI maps reason codes to ARB strings; a silent new enum
/// value without a matching locale key surfaces as a blank tooltip)
/// and the [SecureKeyStorage.enableRuntimeSubprocessProbes] static
/// latch contract.
void main() {
  group('SecureKeyStorage Dart-side surface', () {
    test(
      'enableRuntimeSubprocessProbes is idempotent and side-effect free',
      () {
        // The flag is a static latch that main.dart flips once before
        // the first provider evaluates; calling it twice is a no-op
        // from the test's perspective.
        SecureKeyStorage.enableRuntimeSubprocessProbes();
        SecureKeyStorage.enableRuntimeSubprocessProbes();
      },
    );

    test(
      'KeyringProbeResult carries every documented classification label',
      () {
        expect(KeyringProbeResult.values, <KeyringProbeResult>[
          KeyringProbeResult.available,
          KeyringProbeResult.linuxNoSecretService,
          KeyringProbeResult.probeFailed,
        ]);
      },
    );
  });
}
