import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/active_dbkey.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

/// Pure-Dart marker stand-in for tests. The production
/// [LinuxKeychainMarker] now delegates each op across the FRB
/// boundary into `lfs_core::security::keychain_marker`; under
/// flutter_test the FRB native lib is not loaded so the production
/// shim's `set` swallows the exception and the marker stays unset.
/// This subclass overrides the surface to flip an in-memory flag so
/// vault tests that depend on the post-store marker visibility keep
/// working without bootstrapping the native lib. The Rust
/// implementation has its own unit-test coverage in
/// `lfs_core::security::keychain_marker::tests`.
class _InMemoryMarker extends LinuxKeychainMarker {
  bool _set = false;
  _InMemoryMarker({bool initialState = false}) : _set = initialState, super();
  @override
  Future<bool> exists({bool skipOnNonLinux = true}) async {
    if (skipOnNonLinux && !Platform.isLinux) return true;
    return _set;
  }

  @override
  Future<void> set() async => _set = true;
  @override
  Future<void> clear() async => _set = false;

  bool get raw => _set;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Linux orchestrator routes through `lfs_core::security::biometric_key_vault::linux`
  // and `lfs_os_security::secure_key_storage` via FRB; bootstrap the
  // native lib so the dispatch + path-resolution contract gets exercised.
  late Directory tmp;
  setUpAll(() async {
    await requireFrbLoaded();
    // The Linux vault ops resolve the support dir pinned Rust-side at
    // configStoreInit; pin a fresh temp dir (no vault file) so the
    // platform-dispatch assertions below see a clean install.
    tmp = Directory.systemTemp.createTempSync('bio_vault_');
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Round-trip / seal-file / atomic-write coverage lives Rust-side
  // under `lfs_core::security::biometric_key_vault::linux::tests`.
  // Under flutter_test we cannot drive a real TPM (CI flake) and the
  // Dart-side TpmClient seams retired with the orchestrator move,
  // so this suite limits itself to the platform-dispatch contract.

  group('BiometricKeyVault', () {
    test('linuxTpmReady is false on non-Linux hosts', () async {
      if (Platform.isLinux) return;
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      expect(await vault.linuxTpmReady(), isFalse);
    });

    test('isStored is false for a fresh support dir', () async {
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      expect(await vault.isStored(), isFalse);
    });

    test('clear is a no-op against a fresh support dir', () async {
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      await vault.clear();
      expect(await vault.isStored(), isFalse);
    });

    test('default constructor falls back to the shared LinuxKeychainMarker '
        'singleton', () {
      // Production call sites (security_provider, lock-screen wiring)
      // build the vault with no explicit marker — the constructor
      // must default to `LinuxKeychainMarker.defaultInstance`.
      // Pure construction smoke; no FRB call.
      final vault = BiometricKeyVault();
      expect(vault, isA<BiometricKeyVault>());
    });

    test('isStored on Linux short-circuits to false when both the Rust probe '
        'misses and the marker is absent', () async {
      if (!Platform.isLinux) return;
      // On Linux `isStored` first tries the TPM-sealed file via
      // `biometricVaultLinuxIsStored`; with a fresh tmp support
      // dir there is no `biometric_vault.tpm` file, so the call
      // returns false. The libsecret fallback then gates on the
      // marker — absent → short-circuit to false without ever
      // waking zbus.
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      expect(await vault.isStored(), isFalse);
    });

    test('clear on Linux invokes the Rust TPM-clear path without throwing '
        'when no seal file exists', () async {
      if (!Platform.isLinux) return;
      // The Linux `clear` branch runs three best-effort Rust calls
      // (TPM-clear, libsecret-delete, marker-clear). With a fresh
      // support dir and no seal file, none of them should propagate
      // — the wipe/tier-switch flow has to keep going regardless.
      final marker = _InMemoryMarker(initialState: true);
      final vault = BiometricKeyVault(marker: marker);
      await expectLater(vault.clear(), completes);
      // Marker is cleared after the call.
      expect(marker.raw, isFalse);
    });

    test(
      'storeFromActive delegates to storeFromSecret with the canonical '
      'active-DB-key id',
      () async {
        // The active SecretStore slot is empty on a fresh install;
        // `storeFromActive` is sugar for
        // `storeFromSecret(kActiveDbKeySecretId)`. Without bytes
        // staged the Rust write surfaces "secret not found" and the
        // façade reports false — that is the contract the
        // post-unlock listener depends on (no bytes → no false
        // positive). The bytes-present path needs a real biometric
        // prompt and lives in the integration suite.
        expect(rust_app.secretsHas(id: kActiveDbKeySecretId), isFalse);
        final vault = BiometricKeyVault(marker: _InMemoryMarker());
        final ok = await vault.storeFromActive();
        expect(ok, isFalse);
      },
      // storeFromSecret on darwin / Windows / Android requires a real
      // biometric prompt (Touch ID / Hello / BiometricPrompt); only
      // the empty-secret rejection path is exercised here. The full
      // round-trip is covered by integration: requires a live
      // biometric backend.
    );

    test('readToActive reports false on a fresh install — no key has ever '
        'been stashed', () async {
      // On a clean support dir the Linux Rust probe returns false
      // (no seal file), the marker is unset (libsecret fallback
      // gated off), and on every other platform
      // `secure_storage_read_biometric_to_secret` finds nothing in
      // the keychain. Contract: nothing stored → readToActive
      // returns false without surfacing an exception and without
      // staging into the active SecretStore slot. The bytes-present
      // path needs a real biometric prompt and lives in the
      // integration suite.
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      // Drop any prior leak so the post-call observation is clean.
      try {
        rust_app.secretsDrop(id: kActiveDbKeySecretId);
      } catch (_) {
        // FRB unavailable — the test already skipped at setUpAll.
      }
      final ok = await vault.readToActive();
      expect(ok, isFalse);
      // And critically, no bytes landed under the active slot —
      // a false positive here would mis-route the unlock cascade.
      expect(rust_app.secretsHas(id: kActiveDbKeySecretId), isFalse);
    });

    test('clear is idempotent — repeated calls on the same fresh vault stay '
        'a no-op', () async {
      // Wipe/disable flow may run twice (user toggles biometric
      // off then re-opens settings before the listener cascade
      // settles). The second `clear` must not throw or otherwise
      // misbehave.
      final vault = BiometricKeyVault(marker: _InMemoryMarker());
      await vault.clear();
      await expectLater(vault.clear(), completes);
      expect(await vault.isStored(), isFalse);
    });

    // Paths requiring a real biometric / TPM / Secure Enclave / Hello
    // prompt — covered by integration:
    //   * `storeFromSecret` with bytes staged → needs Touch ID / Hello /
    //     BiometricPrompt on darwin / Windows / Android; needs `tpm2-tools`
    //     + fprintd on Linux. Rust-side coverage in
    //     `lfs_core::security::biometric_key_vault::linux::tests` and
    //     `lfs_os_security::secure_key_storage::tests`.
    //   * `readToActive` with a real stash → same biometric gate.
    //   * `clear` removing a real stash → same biometric gate to read,
    //     unconditional delete to wipe.
  });
}
