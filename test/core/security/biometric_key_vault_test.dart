import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';
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
  _InMemoryMarker() : super(supportDirFactory: () async => '');
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
  // BiometricKeyVault writes the salt blob via writeBytesAtomic
  // which routes through `lfs_core::path::write_bytes_atomic` —
  // bootstrap FRB so the canonical Rust write path is exercised.
  setUpAll(requireFrbLoaded);

  late LinuxKeychainMarker marker;

  setUp(() {
    marker = _InMemoryMarker();
  });

  // The previous round-trip / base64 / clear / read-empty tests
  // mocked the `plugins.it_nomads.com/flutter_secure_storage`
  // MethodChannel. After the cleanup arc retired
  // `flutter_secure_storage`, BiometricKeyVault calls
  // `lfs_os_security::secure_key_storage::*_biometric` directly
  // through FRB → real OS keychain. Equivalent round-trip /
  // clear / read-empty coverage now lives Rust-side under
  // `lfs_os_security::secure_key_storage::tests`, exercising the
  // real platform backend (libsecret on the Linux CI runner,
  // SecItem on darwin, CredWrite/Read/Delete on Windows,
  // AndroidKeyStore on Android). Two-language Dart-side mocking
  // tests would only re-validate FRB plumbing already covered by
  // the FRB codegen + bus tests.

  group('BiometricKeyVault Linux TPM branch', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('bio_vault_linux_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    BiometricKeyVault newVault({
      required TpmClient tpm,
      required FprintdClient fprintd,
    }) => BiometricKeyVault(
      tpmClient: tpm,
      fprintdClient: fprintd,
      marker: marker,
      linuxSealFileFactory: () async =>
          File('${tempDir.path}/biometric_vault.tpm'),
    );

    test('linuxTpmReady is false when not on Linux', () async {
      if (Platform.isLinux) return;
      final vault = newVault(
        tpm: _FakeTpm(available: true),
        fprintd: _FakeFprintd(hash: Uint8List.fromList([1])),
      );
      expect(await vault.linuxTpmReady(), isFalse);
    });

    test('linuxTpmReady delegates to TPM probe on Linux', () async {
      if (!Platform.isLinux) return;
      expect(
        await newVault(
          tpm: _FakeTpm(available: true),
          fprintd: _FakeFprintd(hash: null),
        ).linuxTpmReady(),
        isTrue,
      );
      expect(
        await newVault(
          tpm: _FakeTpm(available: false),
          fprintd: _FakeFprintd(hash: null),
        ).linuxTpmReady(),
        isFalse,
      );
    });

    test(
      'store → read round-trips through the TPM seal file on Linux',
      () async {
        if (!Platform.isLinux) return;
        final tpm = _FakeTpm(available: true);
        final fprintd = _FakeFprintd(hash: Uint8List.fromList([9, 9, 9]));
        final vault = newVault(tpm: tpm, fprintd: fprintd);
        final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

        expect(await vault.store(key), isTrue);
        expect(await vault.isStored(), isTrue);
        // Seal file must exist on disk after a successful Linux seal.
        expect(
          File('${tempDir.path}/biometric_vault.tpm').existsSync(),
          isTrue,
        );
        expect(await vault.read(), key);
      },
    );

    // The two libsecret-fallback tests below moved to the Rust
    // side after the cleanup arc retired flutter_secure_storage.
    // The fallback now goes through `lfs_os_security::secure_key_storage`
    // (Rust `secret-service` crate, libsecret D-Bus); the equivalent
    // round-trip lives in
    // `lfs_os_security::secure_key_storage::tests` (Linux integration
    // path) where it can talk to a real session bus on the CI runner
    // instead of mocking a MethodChannel that no longer exists.
    test(
      'store falls back to libsecret when TPM is unavailable on Linux',
      () async {},
      skip:
          'Moved to Rust integration tests under '
          'lfs_os_security::secure_key_storage::tests after the '
          'flutter_secure_storage retire',
    );
    test(
      'store falls back to libsecret when fprintd enrolment is missing',
      () async {},
      skip:
          'Moved to Rust integration tests under '
          'lfs_os_security::secure_key_storage::tests after the '
          'flutter_secure_storage retire',
    );

    test(
      'clear removes both the TPM seal file and the libsecret entry',
      () async {
        if (!Platform.isLinux) return;
        final tpm = _FakeTpm(available: true);
        final fprintd = _FakeFprintd(hash: Uint8List.fromList([1]));
        final vault = newVault(tpm: tpm, fprintd: fprintd);
        await vault.store(Uint8List.fromList([1, 2]));
        await vault.clear();
        expect(
          File('${tempDir.path}/biometric_vault.tpm').existsSync(),
          isFalse,
        );
        expect(await vault.isStored(), isFalse);
      },
    );

    test('read returns null when the seal file is missing', () async {
      if (!Platform.isLinux) return;
      final vault = newVault(
        tpm: _FakeTpm(available: true),
        fprintd: _FakeFprintd(hash: Uint8List.fromList([1])),
      );
      expect(await vault.read(), isNull);
    });

    test('linuxSeal writes atomically — no .tmp sibling survives', () async {
      // A crash between `openWrite` and `flush` used to leave a
      // truncated seal blob. On next launch `isStored()` returns
      // true (file exists), unseal reads garbage, and the whole
      // biometric-unlock path silently drops back to the PIN
      // dialog with no "vault broken" hint. `writeBytesAtomic`
      // renames a fully-written tmp file into place; this test
      // asserts no leftover tmp file after a successful seal.
      if (!Platform.isLinux) return;
      final tpm = _FakeTpm(available: true);
      final fprintd = _FakeFprintd(hash: Uint8List.fromList([1, 2, 3]));
      final vault = newVault(tpm: tpm, fprintd: fprintd);

      expect(await vault.store(Uint8List.fromList(List.filled(32, 7))), isTrue);
      final siblings = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.tmp'))
          .toList();
      expect(
        siblings,
        isEmpty,
        reason:
            'writeBytesAtomic must rename the tmp file into place; '
            'no .tmp* sibling should remain.',
      );
    });
  });
}

class _FakeTpm implements TpmClient {
  _FakeTpm({required this.available});
  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Uint8List?> seal(
    Uint8List secret, {
    required Uint8List authValue,
  }) async => Uint8List.fromList([
    0x55,
    ...authValue.length.toString().codeUnits,
    0x55,
    ...authValue,
    ...secret,
  ]);

  @override
  Future<Uint8List?> unseal(
    Uint8List blob, {
    required Uint8List authValue,
  }) async {
    final prefix = authValue.length.toString().codeUnits;
    final headerLen = 2 + prefix.length + authValue.length;
    if (blob.length < headerLen) return null;
    if (blob[0] != 0x55) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (blob[1 + i] != prefix[i]) return null;
    }
    if (blob[1 + prefix.length] != 0x55) return null;
    for (var i = 0; i < authValue.length; i++) {
      if (blob[2 + prefix.length + i] != authValue[i]) return null;
    }
    return Uint8List.fromList(blob.sublist(headerLen));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFprintd implements FprintdClient {
  _FakeFprintd({required this.hash});
  final Uint8List? hash;

  @override
  Future<Uint8List?> getEnrolmentHash() async => hash;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
