import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_ref.dart';

void main() {
  group('SecureRef', () {
    test('value returns the initial payload before dispose', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final ref = SecureRef<Uint8List>(bytes, wipe: _zeroFill);
      expect(ref.value, bytes);
      expect(ref.isDisposed, isFalse);
      ref.dispose();
    });

    test('dispose runs wipe exactly once', () {
      var wipeCount = 0;
      final bytes = Uint8List.fromList([9, 9, 9]);
      final ref = SecureRef<Uint8List>(bytes, wipe: (_) => wipeCount++);
      ref.dispose();
      expect(wipeCount, 1);
    });

    test('dispose is idempotent (second call is a no-op)', () {
      var wipeCount = 0;
      final ref = SecureRef<Uint8List>(
        Uint8List.fromList([1, 2]),
        wipe: (_) => wipeCount++,
      );
      ref.dispose();
      ref.dispose();
      ref.dispose();
      expect(
        wipeCount,
        1,
        reason: 'every dispose after the first must be a no-op',
      );
    });

    test('value throws StateError after dispose', () {
      final ref = SecureRef<Uint8List>(
        Uint8List.fromList([7]),
        wipe: _zeroFill,
      );
      ref.dispose();
      expect(() => ref.value, throwsStateError);
    });

    test('isDisposed flips after dispose', () {
      final ref = SecureRef<Uint8List>(
        Uint8List.fromList([7]),
        wipe: _zeroFill,
      );
      expect(ref.isDisposed, isFalse);
      ref.dispose();
      expect(ref.isDisposed, isTrue);
    });

    test('wipe sees the original payload bytes (before disposal)', () {
      final captured = <Uint8List>[];
      final src = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final ref = SecureRef<Uint8List>(
        src,
        wipe: (bytes) {
          captured.add(Uint8List.fromList(bytes));
          for (var i = 0; i < bytes.length; i++) {
            bytes[i] = 0;
          }
        },
      );
      ref.dispose();
      expect(captured.single, [0xAA, 0xBB, 0xCC]);
      expect(
        src,
        [0, 0, 0],
        reason:
            'wipe must mutate the original buffer so the caller '
            'cannot silently reuse the bytes after dispose',
      );
    });

    test('dispose wipe errors are swallowed — do not crash the caller', () {
      final ref = SecureRef<Uint8List>(
        Uint8List.fromList([1]),
        wipe: (_) => throw Exception('simulated wipe failure'),
      );
      // Must not throw.
      ref.dispose();
      expect(ref.isDisposed, isTrue);
    });

    test('typed-tag: SecureRef<String> cannot be read back via .value '
        'after dispose', () {
      final ref = SecureRef<String>('hunter2', wipe: (_) {});
      expect(ref.value, 'hunter2');
      ref.dispose();
      expect(() => ref.value, throwsStateError);
    });
  });
}

void _zeroFill(Uint8List bytes) {
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = 0;
  }
}
