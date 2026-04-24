import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> fakeStore;

  setUp(() {
    fakeStore = {};
    // FlutterSecureStorage talks to the host via a MethodChannel — replace
    // it with an in-memory fake so the test doesn't need a keychain.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, Object?>() ?? {};
            switch (call.method) {
              case 'write':
                fakeStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return fakeStore[args['key']];
              case 'delete':
                fakeStore.remove(args['key']);
                return null;
              case 'containsKey':
                return fakeStore.containsKey(args['key']);
              case 'readAll':
                return Map<String, String>.from(fakeStore);
              case 'deleteAll':
                fakeStore.clear();
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  group('BiometricKeyVault', () {
    test('store → read round-trips the key bytes', () async {
      final vault = BiometricKeyVault();
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

      expect(await vault.store(key), isTrue);
      expect(await vault.isStored(), isTrue);
      final read = await vault.read();
      expect(read, key);
    });

    test('encodes key as base64 for transport', () async {
      final vault = BiometricKeyVault();
      final key = Uint8List.fromList([1, 2, 3, 4, 5]);
      await vault.store(key);
      // Verify the stored blob is base64 — we don't want plaintext bytes
      // shuttled through a platform channel log on iOS/Android.
      final raw = fakeStore.values.first;
      expect(base64Decode(raw), key);
    });

    test('clear wipes the stored key', () async {
      final vault = BiometricKeyVault();
      await vault.store(Uint8List.fromList([1, 2, 3]));
      await vault.clear();
      expect(await vault.isStored(), isFalse);
      expect(await vault.read(), isNull);
    });

    test('read returns null when nothing stored', () async {
      final vault = BiometricKeyVault();
      expect(await vault.read(), isNull);
      expect(await vault.isStored(), isFalse);
    });

    test('iOS options bind the key to Secure Enclave + biometryCurrentSet', () {
      // Anchors the iOS/macOS Secure Enclave binding invariant: a change that
      // removes the biometryCurrentSet flag (or downgrades the
      // accessibility tier away from passcode-required) must break this
      // test so the regression is caught before ship.
      expect(
        BiometricKeyVault.iosOptions.accessibility,
        KeychainAccessibility.passcode,
      );
      expect(
        BiometricKeyVault.iosOptions.accessControlFlags,
        contains(AccessControlFlag.biometryCurrentSet),
      );
      expect(BiometricKeyVault.iosOptions.synchronizable, isFalse);
    });

    test('macOS options mirror iOS (Secure Enclave + biometryCurrentSet)', () {
      expect(
        BiometricKeyVault.macOsOptions.accessibility,
        KeychainAccessibility.passcode,
      );
      expect(
        BiometricKeyVault.macOsOptions.accessControlFlags,
        contains(AccessControlFlag.biometryCurrentSet),
      );
      expect(BiometricKeyVault.macOsOptions.synchronizable, isFalse);
    });
  });

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

    test(
      'store falls back to libsecret when TPM is unavailable on Linux',
      () async {
        if (!Platform.isLinux) return;
        final tpm = _FakeTpm(available: false);
        final fprintd = _FakeFprintd(hash: Uint8List.fromList([1]));
        final vault = newVault(tpm: tpm, fprintd: fprintd);
        final key = Uint8List.fromList([1, 2, 3, 4]);

        expect(await vault.store(key), isTrue);
        // No TPM seal file should exist — fallback went through libsecret.
        expect(
          File('${tempDir.path}/biometric_vault.tpm').existsSync(),
          isFalse,
        );
        // Stored value is base64 of the key, in the libsecret mock.
        expect(await vault.read(), key);
      },
    );

    test(
      'store falls back to libsecret when fprintd enrolment is missing',
      () async {
        if (!Platform.isLinux) return;
        final tpm = _FakeTpm(available: true);
        final fprintd = _FakeFprintd(hash: null);
        final vault = newVault(tpm: tpm, fprintd: fprintd);
        final key = Uint8List.fromList([5, 6, 7, 8]);

        expect(await vault.store(key), isTrue);
        expect(
          File('${tempDir.path}/biometric_vault.tpm').existsSync(),
          isFalse,
        );
        expect(await vault.read(), key);
      },
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
