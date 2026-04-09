import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/format.dart';

/// Fuzz tests for [sanitizeError].
///
/// Generates random error-like strings and objects to verify
/// the parser never crashes with an unhandled exception.
void main() {
  group('Fuzz sanitizeError', () {
    final rng = Random(42);

    test('handles 1000 random string errors without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final error = _randomErrorString(rng);
        sanitizeError(error);
      }
    });

    test('handles random errno patterns', () {
      for (var i = 0; i < 500; i++) {
        final errno = rng.nextInt(200);
        final msgs = [
          'OS Error: something, errno = $errno',
          'FileSystemException: blah, errno = $errno, path = /tmp/x',
          "FileSystemException: blah, errno = $errno, path = '${_randomString(rng, 50)}'",
          'errno=$errno',
          'errno = $errno',
        ];
        final msg = msgs[rng.nextInt(msgs.length)];
        sanitizeError(Exception(msg));
      }
    });

    test('handles deeply nested exception chains', () {
      Object error = Exception('root');
      for (var i = 0; i < 20; i++) {
        error = Exception(error.toString());
      }
      sanitizeError(error);
    });

    test('handles empty and null-like strings', () {
      sanitizeError('');
      sanitizeError(Exception(''));
      sanitizeError(Exception('null'));
      sanitizeError(Exception('undefined'));
    });

    test('handles unicode and special characters', () {
      for (var i = 0; i < 200; i++) {
        final s = String.fromCharCodes(
          List.generate(rng.nextInt(100), (_) => rng.nextInt(0xFFFF)),
        );
        sanitizeError(Exception(s));
      }
    });

    test('handles various object types', () {
      sanitizeError(42);
      sanitizeError(3.14);
      sanitizeError(true);
      sanitizeError([1, 2, 3]);
      sanitizeError({'key': 'value'});
      sanitizeError(StateError('bad state'));
      sanitizeError(ArgumentError('bad arg'));
      sanitizeError(const FormatException('bad format'));
      sanitizeError(RangeError.range(5, 0, 3));
      sanitizeError(UnsupportedError('unsupported'));
    });
  });

  group('Fuzz formatSize', () {
    final rng = Random(42);

    test('handles 1000 random byte values without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final bytes = rng.nextInt(1 << 32);
        final result = formatSize(bytes);
        expect(result, isNotEmpty);
      }
    });
  });

  group('Fuzz formatDuration', () {
    final rng = Random(42);

    test('handles 1000 random durations without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final ms = Duration(milliseconds: rng.nextInt(1 << 30));
        final result = formatDuration(ms);
        expect(result, isNotEmpty);
      }
    });
  });
}

String _randomString(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen);
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789 /\\:.,-_()[]{}';
  return String.fromCharCodes(
    List.generate(len, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

String _randomErrorString(Random rng) {
  final templates = [
    'OS Error: ${_randomString(rng, 30)}, errno = ${rng.nextInt(200)}',
    'FileSystemException: ${_randomString(rng, 30)}, errno = ${rng.nextInt(200)}',
    "FileSystemException: x, errno = ${rng.nextInt(200)}, path = '${_randomString(rng, 40)}'",
    'SocketException: ${_randomString(rng, 50)}',
    _randomString(rng, 100),
    'Connection refused (errno = ${rng.nextInt(200)})',
    '',
    'errno = ${rng.nextInt(200)}',
  ];
  return templates[rng.nextInt(templates.length)];
}
