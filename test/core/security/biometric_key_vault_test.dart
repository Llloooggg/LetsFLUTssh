import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';
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
  });
}
