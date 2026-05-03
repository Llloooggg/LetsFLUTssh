import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/linux/tpm_client.dart';
import 'package:letsflutssh/src/rust/api/tpm.dart' as rust_tpm;

/// Tests drive [TpmClient] through its DI seams — no FRB, no
/// `tpm2-tools` shell-out, no real `/dev/tpmrm0`. Every branch
/// reachable from Dart (platform short-circuit, 128-byte secret
/// guard, throw-on-rust-error → null collapse, 5-way enum mapping)
/// gets a deterministic input and a strict output assertion.
void main() {
  group('TpmClient.probe', () {
    test('returns wrongPlatform when host is not Linux', () async {
      final calls = <String>[];
      final client = TpmClient(
        isLinuxFn: () => false,
        probeFn: ({required binary, required device, required timeoutMs}) {
          calls.add('probe');
          return Future.value(rust_tpm.DbTpmProbeResult.available);
        },
      );
      expect(await client.probe(), TpmProbeResult.wrongPlatform);
      expect(calls, isEmpty, reason: 'Rust probe must NOT run off-Linux');
    });

    test('maps every Rust enum variant onto the Dart enum', () async {
      final cases = {
        rust_tpm.DbTpmProbeResult.available: TpmProbeResult.available,
        rust_tpm.DbTpmProbeResult.deviceNodeMissing:
            TpmProbeResult.deviceNodeMissing,
        rust_tpm.DbTpmProbeResult.binaryMissing: TpmProbeResult.binaryMissing,
        rust_tpm.DbTpmProbeResult.probeFailed: TpmProbeResult.probeFailed,
        // The "Rust says notLinux even though we're on Linux" case is
        // theoretical — the Rust dispatcher classifies platform itself.
        // Still mapped so a future cross-platform Rust build doesn't
        // throw a switch-exhaustiveness panic.
        rust_tpm.DbTpmProbeResult.notLinux: TpmProbeResult.wrongPlatform,
      };
      for (final entry in cases.entries) {
        final client = TpmClient(
          isLinuxFn: () => true,
          probeFn: ({required binary, required device, required timeoutMs}) =>
              Future.value(entry.key),
        );
        expect(
          await client.probe(),
          entry.value,
          reason: '${entry.key} → ${entry.value}',
        );
      }
    });

    test('passes the configured binary / device / timeout into Rust', () async {
      late String capturedBinary;
      late String capturedDevice;
      late BigInt capturedTimeoutMs;
      final client = TpmClient(
        binary: '/usr/local/bin/tpm2',
        tpmDevice: '/dev/tpmrm9',
        timeout: const Duration(milliseconds: 1234),
        isLinuxFn: () => true,
        probeFn: ({required binary, required device, required timeoutMs}) {
          capturedBinary = binary;
          capturedDevice = device;
          capturedTimeoutMs = timeoutMs;
          return Future.value(rust_tpm.DbTpmProbeResult.available);
        },
      );
      await client.probe();
      expect(capturedBinary, '/usr/local/bin/tpm2');
      expect(capturedDevice, '/dev/tpmrm9');
      expect(capturedTimeoutMs, BigInt.from(1234));
    });

    test(
      'isAvailable shorthand returns true only on the available variant',
      () async {
        rust_tpm.DbTpmProbeResult next = rust_tpm.DbTpmProbeResult.available;
        final client = TpmClient(
          isLinuxFn: () => true,
          probeFn: ({required binary, required device, required timeoutMs}) =>
              Future.value(next),
        );
        expect(await client.isAvailable(), isTrue);

        next = rust_tpm.DbTpmProbeResult.binaryMissing;
        expect(await client.isAvailable(), isFalse);

        next = rust_tpm.DbTpmProbeResult.deviceNodeMissing;
        expect(await client.isAvailable(), isFalse);
      },
    );
  });

  group('TpmClient.seal', () {
    test('rejects > 128-byte secrets without calling Rust', () async {
      var sealCalled = 0;
      final client = TpmClient(
        sealFn:
            ({
              required secret,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) {
              sealCalled += 1;
              return Future.value(Uint8List(0));
            },
      );
      final result = await client.seal(Uint8List(129), authValue: Uint8List(0));
      expect(result, isNull);
      expect(sealCalled, 0);
    });

    test('128-byte secret is the inclusive upper bound', () async {
      Uint8List? returnedBlob;
      final blob = Uint8List.fromList(List.filled(64, 0xAA));
      final client = TpmClient(
        sealFn:
            ({
              required secret,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) {
              returnedBlob = secret;
              return Future.value(blob);
            },
      );
      final out = await client.seal(Uint8List(128), authValue: Uint8List(0));
      expect(out, blob);
      expect(returnedBlob!.length, 128);
    });

    test('Rust seal throw collapses to null', () async {
      final client = TpmClient(
        sealFn:
            ({
              required secret,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) => Future.error(StateError('tpm not present')),
      );
      expect(await client.seal(Uint8List(32), authValue: Uint8List(0)), isNull);
    });

    test(
      'seal forwards secret + authValue + binary / device / timeout',
      () async {
        late Uint8List capturedSecret;
        late Uint8List capturedAuth;
        late String capturedBinary;
        late String capturedDevice;
        late BigInt capturedTimeoutMs;

        final client = TpmClient(
          binary: 'tpm-x',
          tpmDevice: '/dev/tpmrmX',
          timeout: const Duration(seconds: 7),
          sealFn:
              ({
                required secret,
                required authValue,
                required binary,
                required device,
                required timeoutMs,
              }) {
                capturedSecret = secret;
                capturedAuth = authValue;
                capturedBinary = binary;
                capturedDevice = device;
                capturedTimeoutMs = timeoutMs;
                return Future.value(Uint8List.fromList([1, 2, 3]));
              },
        );
        final secret = Uint8List.fromList(List.generate(32, (i) => i));
        final auth = Uint8List.fromList(List.generate(16, (i) => i + 100));
        await client.seal(secret, authValue: auth);
        expect(capturedSecret, secret);
        expect(capturedAuth, auth);
        expect(capturedBinary, 'tpm-x');
        expect(capturedDevice, '/dev/tpmrmX');
        expect(capturedTimeoutMs, BigInt.from(7000));
      },
    );
  });

  group('TpmClient.unseal', () {
    test('Rust returns plaintext bytes', () async {
      final client = TpmClient(
        unsealFn:
            ({
              required blob,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) => Future.value(Uint8List.fromList([0xCA, 0xFE])),
      );
      expect(
        await client.unseal(Uint8List(8), authValue: Uint8List(0)),
        Uint8List.fromList([0xCA, 0xFE]),
      );
    });

    test('Rust throw (wrong auth, missing TPM, …) collapses to null', () async {
      final client = TpmClient(
        unsealFn:
            ({
              required blob,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) => Future.error(Exception('bad auth')),
      );
      expect(
        await client.unseal(Uint8List(8), authValue: Uint8List(0)),
        isNull,
      );
    });

    test('forwards blob + authValue without mutation', () async {
      Uint8List? capturedBlob;
      Uint8List? capturedAuth;
      final client = TpmClient(
        unsealFn:
            ({
              required blob,
              required authValue,
              required binary,
              required device,
              required timeoutMs,
            }) {
              capturedBlob = blob;
              capturedAuth = authValue;
              return Future.value(Uint8List(0));
            },
      );
      final blob = Uint8List.fromList(List.generate(40, (i) => i ^ 0x55));
      final auth = Uint8List.fromList([1, 2, 3, 4]);
      await client.unseal(blob, authValue: auth);
      expect(capturedBlob, blob);
      expect(capturedAuth, auth);
    });
  });

  group('TpmClient ctor defaults', () {
    test('default ctor wires real FRB calls (compiles only)', () {
      // Smoke check that production ctor compiles without seam args.
      // Constructing does not call Rust — only field assignment runs.
      final client = TpmClient();
      expect(client, isNotNull);
    });
  });
}
