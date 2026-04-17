import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/update/release_signing.dart';

// The fixture below is the exact byte string + signature produced by:
//
//   echo "test artifact bytes" > test.bin
//   openssl pkeyutl -sign -inkey release-key-current.pem -rawin -in test.bin
//
// The signature must be 64 bytes (Ed25519). Using a frozen vector here
// instead of generating one in-test means the test would also catch any
// accidental change to the embedded public-key list (a swap would make
// this signature stop verifying).

final Uint8List _fixtureMessage = Uint8List.fromList(
  // "test artifact bytes\n"
  [
    0x74,
    0x65,
    0x73,
    0x74,
    0x20,
    0x61,
    0x72,
    0x74,
    0x69,
    0x66,
    0x61,
    0x63,
    0x74,
    0x20,
    0x62,
    0x79,
    0x74,
    0x65,
    0x73,
    0x0a,
  ],
);

final Uint8List _fixtureCurrentKeySignature = Uint8List.fromList([
  0x87,
  0xfa,
  0x19,
  0xa5,
  0x31,
  0x8f,
  0xb7,
  0x9f,
  0x6b,
  0x93,
  0x47,
  0x64,
  0x67,
  0x3c,
  0xec,
  0x15,
  0xd5,
  0x80,
  0x86,
  0x2a,
  0x55,
  0x09,
  0xf3,
  0xd3,
  0xfa,
  0x03,
  0xb6,
  0x2a,
  0x3c,
  0x0c,
  0xb7,
  0x40,
  0x27,
  0xc3,
  0x47,
  0x30,
  0xfc,
  0xc4,
  0x5e,
  0xc1,
  0x63,
  0x3a,
  0x00,
  0xc0,
  0x20,
  0x34,
  0x00,
  0xca,
  0x7d,
  0x40,
  0x39,
  0xb4,
  0x77,
  0x0b,
  0xbc,
  0x89,
  0x9a,
  0x0b,
  0x62,
  0xd2,
  0xc5,
  0xd0,
  0x3b,
  0x08,
]);

void main() {
  group('ReleaseSigning.verifyBytes', () {
    test('accepts a real signature from the current pinned private key', () {
      expect(
        ReleaseSigning.verifyBytes(
          message: _fixtureMessage,
          signature: _fixtureCurrentKeySignature,
        ),
        isTrue,
      );
    });

    test('rejects a tampered message under the same signature', () {
      final mutated = Uint8List.fromList(_fixtureMessage);
      mutated[0] ^= 0x01; // flip one bit
      expect(
        ReleaseSigning.verifyBytes(
          message: mutated,
          signature: _fixtureCurrentKeySignature,
        ),
        isFalse,
      );
    });

    test('rejects a signature of the wrong length', () {
      expect(
        ReleaseSigning.verifyBytes(
          message: _fixtureMessage,
          signature: Uint8List(63),
        ),
        isFalse,
      );
      expect(
        ReleaseSigning.verifyBytes(
          message: _fixtureMessage,
          signature: Uint8List(65),
        ),
        isFalse,
      );
    });

    test('rejects a randomly-flipped signature byte', () {
      final mutated = Uint8List.fromList(_fixtureCurrentKeySignature);
      mutated[10] ^= 0xFF;
      expect(
        ReleaseSigning.verifyBytes(
          message: _fixtureMessage,
          signature: mutated,
        ),
        isFalse,
      );
    });
  });

  group('ReleaseSigning.verifyFile', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lfs_sign_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('accepts a real on-disk artifact + matching signature', () async {
      final artifact = File('${tmp.path}/release.bin');
      await artifact.writeAsBytes(_fixtureMessage);
      expect(
        await ReleaseSigning.verifyFile(
          artifactPath: artifact.path,
          signature: _fixtureCurrentKeySignature,
        ),
        isTrue,
      );
    });

    test('returns false when the file does not exist', () async {
      expect(
        await ReleaseSigning.verifyFile(
          artifactPath: '${tmp.path}/missing.bin',
          signature: _fixtureCurrentKeySignature,
        ),
        isFalse,
      );
    });
  });
}
