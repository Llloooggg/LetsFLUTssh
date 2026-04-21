import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';

/// Fake TPM: seal prepends a fixed marker + auth-value-hex so
/// unseal can assert it saw the same auth. Good enough to validate
/// the vault's salt + PIN-HMAC contract without a real TPM.
class _FakeTpm implements TpmClient {
  bool available;
  _FakeTpm({this.available = true});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Uint8List?> seal(
    Uint8List secret, {
    required Uint8List authValue,
  }) async {
    final header = [0x7F, 0x7E];
    return Uint8List.fromList([...header, ...authValue, ...secret]);
  }

  @override
  Future<Uint8List?> unseal(
    Uint8List blob, {
    required Uint8List authValue,
  }) async {
    if (blob.length < 2 + authValue.length) return null;
    if (blob[0] != 0x7F || blob[1] != 0x7E) return null;
    for (var i = 0; i < authValue.length; i++) {
      if (blob[2 + i] != authValue[i]) return null;
    }
    return Uint8List.fromList(blob.sublist(2 + authValue.length));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hw_vault_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  HardwareTierVault newVault({TpmClient? tpm}) => HardwareTierVault(
    tpmClient: tpm ?? _FakeTpm(),
    stateFileFactory: () async => File('${tempDir.path}/hardware_vault.bin'),
  );

  group('HardwareTierVault', () {
    test('isAvailable flows from the TPM probe', () async {
      if (!Platform.isLinux) return;
      expect(
        await newVault(tpm: _FakeTpm(available: true)).isAvailable(),
        isTrue,
      );
      expect(
        await newVault(tpm: _FakeTpm(available: false)).isAvailable(),
        isFalse,
      );
    });

    test('store + read round-trips the DB key under the right PIN', () async {
      if (!Platform.isLinux) return;
      final vault = newVault();
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(await vault.store(dbKey: key, pin: '1234'), isTrue);
      expect(await vault.isStored(), isTrue);
      final readBack = await vault.read('1234');
      expect(readBack, key);
    });

    test('read returns null for a wrong PIN', () async {
      if (!Platform.isLinux) return;
      final vault = newVault();
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      await vault.store(dbKey: key, pin: '1234');
      expect(await vault.read('9999'), isNull);
    });

    test('clear drops the sealed blob', () async {
      if (!Platform.isLinux) return;
      final vault = newVault();
      await vault.store(dbKey: Uint8List.fromList([1, 2, 3]), pin: '1234');
      await vault.clear();
      expect(await vault.isStored(), isFalse);
      expect(await vault.read('1234'), isNull);
    });

    test('store fails when TPM probe is unavailable', () async {
      if (!Platform.isLinux) return;
      final vault = newVault(tpm: _FakeTpm(available: false));
      expect(
        await vault.store(dbKey: Uint8List.fromList([1]), pin: '1234'),
        isFalse,
      );
    });

    test(
      'two calls with the same PIN produce different blobs (salt rotation)',
      () async {
        if (!Platform.isLinux) return;
        final vault = newVault();
        final key = Uint8List.fromList([1, 2, 3]);
        await vault.store(dbKey: key, pin: '1234');
        final first = File(
          '${tempDir.path}/hardware_vault.bin',
        ).readAsBytesSync();
        await vault.store(dbKey: key, pin: '1234');
        final second = File(
          '${tempDir.path}/hardware_vault.bin',
        ).readAsBytesSync();
        expect(second, isNot(equals(first)));
        expect(await vault.read('1234'), key);
      },
    );

    test('non-Linux platforms report unavailable regardless of TPM', () async {
      if (Platform.isLinux) return;
      expect(await newVault().isAvailable(), isFalse);
    });
  });
}
