import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';

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
  _InMemoryMarker() : super();
  @override
  Future<bool> exists({bool skipOnNonLinux = true}) async {
    if (skipOnNonLinux && !Platform.isLinux) return true;
    return _set;
  }

  @override
  Future<void> set() async => _set = true;
  @override
  Future<void> clear() async => _set = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Linux orchestrator routes through `lfs_core::security::biometric_key_vault::linux`
  // and `lfs_os_security::secure_key_storage` via FRB; bootstrap the
  // native lib so the dispatch + path-resolution contract gets exercised.
  setUpAll(requireFrbLoaded);

  // Round-trip / seal-file / atomic-write coverage lives Rust-side
  // under `lfs_core::security::biometric_key_vault::linux::tests`.
  // Under flutter_test we cannot drive a real TPM (CI flake) and the
  // Dart-side TpmClient seams retired with the orchestrator move,
  // so this suite limits itself to the platform-dispatch contract.

  group('BiometricKeyVault', () {
    test('linuxTpmReady is false on non-Linux hosts', () async {
      if (Platform.isLinux) return;
      final vault = BiometricKeyVault(
        marker: _InMemoryMarker(),
        supportDirPath: () async =>
            Directory.systemTemp.createTempSync('bio_vault_').path,
      );
      expect(await vault.linuxTpmReady(), isFalse);
    });

    test('isStored is false for a fresh support dir', () async {
      final tmp = Directory.systemTemp.createTempSync('bio_vault_isstored_');
      try {
        final vault = BiometricKeyVault(
          marker: _InMemoryMarker(),
          supportDirPath: () async => tmp.path,
        );
        expect(await vault.isStored(), isFalse);
      } finally {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      }
    });

    test('clear is a no-op against a fresh support dir', () async {
      final tmp = Directory.systemTemp.createTempSync('bio_vault_clear_');
      try {
        final vault = BiometricKeyVault(
          marker: _InMemoryMarker(),
          supportDirPath: () async => tmp.path,
        );
        await vault.clear();
        expect(await vault.isStored(), isFalse);
      } finally {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      }
    });
  });
}
