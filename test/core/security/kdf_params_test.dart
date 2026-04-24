import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';

void main() {
  group('KdfParams.encode/decode', () {
    test('round-trips production defaults', () {
      final encoded = KdfParams.productionDefaults.encode();
      final decoded = KdfParams.decode(encoded);
      expect(decoded, KdfParams.productionDefaults);
    });

    test('round-trips custom Argon2id params', () {
      const params = KdfParams.argon2id(
        memoryKiB: 19456,
        iterations: 3,
        parallelism: 2,
      );
      final encoded = params.encode();
      expect(encoded.length, params.encodedLength);
      final decoded = KdfParams.decode(encoded);
      expect(decoded, params);
    });

    test('first byte of encoding is the algorithm id', () {
      final bytes = KdfParams.productionDefaults.encode();
      expect(bytes[0], KdfAlgorithm.argon2id.id);
    });

    test('rejects empty buffer', () {
      expect(
        () => KdfParams.decode(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown algorithm id', () {
      expect(
        () => KdfParams.decode(Uint8List.fromList([0xFF])),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects truncated Argon2id params', () {
      // Only algorithm id byte, no memory/iterations/parallelism.
      expect(
        () => KdfParams.decode(
          Uint8List.fromList([KdfAlgorithm.argon2id.id, 0, 0]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects zero-valued params (ambiguous / unusable KDF)', () {
      final encoded = const KdfParams.argon2id().encode();
      // Zero out memoryKiB.
      encoded[1] = 0;
      encoded[2] = 0;
      encoded[3] = 0;
      encoded[4] = 0;
      expect(() => KdfParams.decode(encoded), throwsA(isA<FormatException>()));
    });

    test('rejects crafted memory value past sanity cap (OOM defuse)', () {
      // A malicious `credentials.kdf` could request gigabytes-of-RAM
      // via an oversized uint32 in the memory slot. Decoder must
      // reject before the derivation isolate allocates the buffer.
      final encoded = const KdfParams.argon2id().encode();
      final view = ByteData.sublistView(encoded);
      view.setUint32(1, 0xFFFFFFFF); // ~4 GiB requested
      expect(() => KdfParams.decode(encoded), throwsA(isA<FormatException>()));
    });

    test('rejects crafted iteration count past sanity cap', () {
      final encoded = const KdfParams.argon2id().encode();
      final view = ByteData.sublistView(encoded);
      view.setUint32(5, 1000000); // a million iterations
      expect(() => KdfParams.decode(encoded), throwsA(isA<FormatException>()));
    });

    test('rejects crafted parallelism past sanity cap', () {
      final encoded = const KdfParams.argon2id().encode();
      encoded[9] = 0xFF;
      expect(() => KdfParams.decode(encoded), throwsA(isA<FormatException>()));
    });
  });

  group('KdfAlgorithm.fromId', () {
    test('recognises Argon2id', () {
      expect(
        KdfAlgorithm.fromId(KdfAlgorithm.argon2id.id),
        KdfAlgorithm.argon2id,
      );
    });

    test('returns null on unknown id', () {
      expect(KdfAlgorithm.fromId(0x00), isNull);
      expect(KdfAlgorithm.fromId(0xFF), isNull);
    });
  });
}
