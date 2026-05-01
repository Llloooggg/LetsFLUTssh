import 'package:flutter_test/flutter_test.dart';

/// Phase 5 of the cleanup arc retired the bus-event prompt protocol
/// the L2 keychain-password gate relied on. The actor now calls
/// `lfs_os_security::secure_key_storage::{read,write,delete}`
/// directly, so the previous Dart-side
/// `KeychainOpPromptListener` / `KeychainPepperPromptListener`
/// MethodChannel mock no longer intercepts the keychain round-trip.
///
/// Equivalent coverage now lives Rust-side under
/// `lfs_core::security::keychain_password_gate_actor::tests`
/// (verify-with-missing-hash-file, verify-with-corrupt-blob,
/// verify-with-absent-pepper, is_configured-when-no-hash-file)
/// plus the integration round-trip in
/// `lfs_os_security::secure_key_storage::tests` (libsecret on the
/// Linux CI runner, SecItem on darwin, CredRead/Write/Delete on
/// Windows, AndroidKeyStore JNI on Android).
///
/// Re-running the round-trip from Dart with a MethodChannel mock
/// would only re-validate FRB plumbing already covered by the FRB
/// codegen + bus tests.
void main() {
  group('KeychainPasswordGate', () {
    test(
      'round-trip / verify / clear / atomic-write / rate-limit-wipe',
      () {},
      skip:
          'Moved to Rust integration tests after Phase 5 retired the '
          'bus-event prompt protocol. See '
          'lfs_core::security::keychain_password_gate_actor::tests + '
          'lfs_os_security::secure_key_storage::tests.',
    );
  });
}
