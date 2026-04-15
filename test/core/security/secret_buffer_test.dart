import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secret_buffer.dart';

void main() {
  group('SecretBuffer', () {
    test('allocate fills with zeros and exposes length', () {
      final buf = SecretBuffer.allocate(16);
      try {
        expect(buf.length, 16);
        expect(buf.bytes, List<int>.filled(16, 0));
      } finally {
        buf.dispose();
      }
    });

    test('fromBytes copies source into locked buffer', () {
      final buf = SecretBuffer.fromBytes([1, 2, 3, 4]);
      try {
        expect(buf.bytes, [1, 2, 3, 4]);
      } finally {
        buf.dispose();
      }
    });

    test('bytes view is a live alias — writes visible across reads', () {
      final buf = SecretBuffer.allocate(8);
      try {
        buf.bytes[0] = 0xAA;
        buf.bytes[7] = 0xBB;
        expect(buf.bytes[0], 0xAA);
        expect(buf.bytes[7], 0xBB);
      } finally {
        buf.dispose();
      }
    });

    test('dispose is idempotent', () {
      final buf = SecretBuffer.allocate(4);
      buf.dispose();
      buf.dispose(); // Must not throw.
    });

    test('bytes access after dispose throws', () {
      final buf = SecretBuffer.allocate(4);
      buf.dispose();
      expect(() => buf.bytes, throwsStateError);
    });

    test('rejects non-positive length', () {
      expect(() => SecretBuffer.allocate(0), throwsArgumentError);
      expect(() => SecretBuffer.allocate(-1), throwsArgumentError);
    });
  });
}
