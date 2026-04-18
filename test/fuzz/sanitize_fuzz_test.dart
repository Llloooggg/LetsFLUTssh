import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/sanitize.dart';

/// Property-based fuzz suite for [redactSecrets] + [sanitizeErrorMessage].
///
/// Drives 10k pseudo-random payloads — a mix of well-formed secrets,
/// path-shaped strings, and raw entropy — through the pipeline and
/// checks the following invariants on every output:
///
/// 1. No literal IPv4 address survives — `1.2.3.4`-style dotted quads
///    must be replaced by `<ip>`.
/// 2. No home-directory path survives — `/home/<name>`, `/Users/<name>`,
///    `C:\Users\<name>` must be redacted.
/// 3. No PEM private key block survives — the BEGIN/END marker set is
///    replaced by `[REDACTED PRIVATE KEY]`.
/// 4. No long base64 run (≥200 chars) survives.
/// 5. Idempotence — running the pipeline twice on the same input yields
///    the same output.
/// 6. Stability — running the same input again is byte-identical across
///    calls (the pipeline must be deterministic — no time-based salts,
///    no PRNG).
///
/// Seed is fixed so a CI failure reproduces locally via the same suite.
void main() {
  const iterations = 10000;

  final seed = 0xDEADBEEF;
  final rng = Random(seed);

  // Pre-compute regexes once — hot loop.
  final ipv4 = RegExp(r'\b(\d{1,3}\.){3}\d{1,3}\b');
  final unixHome = RegExp(r'/(?:home|Users)/[a-zA-Z0-9_.-]+');
  final winHome = RegExp(r'[A-Z]:\\Users\\[a-zA-Z0-9_.-]+');
  final pemBlock = RegExp(
    r'-----BEGIN[^\n]*?PRIVATE KEY[^\n]*?-----',
    multiLine: true,
  );
  final longBase64 = RegExp(r'[A-Za-z0-9+/=]{200,}');

  group('Fuzz sanitizeErrorMessage + redactSecrets — 10k inputs', () {
    test('ipv4 redaction invariant', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final out = sanitizeErrorMessage(redactSecrets(input));
        expect(
          ipv4.hasMatch(out),
          isFalse,
          reason: 'IPv4 leaked through: seed=${seed + i} input=$input out=$out',
        );
      }
    });

    test('unix/macOS home path redaction invariant', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final out = sanitizeErrorMessage(redactSecrets(input));
        expect(
          unixHome.hasMatch(out),
          isFalse,
          reason:
              'unix home path leaked: seed=${seed + i} input=$input out=$out',
        );
      }
    });

    test('windows home path redaction invariant', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final out = sanitizeErrorMessage(redactSecrets(input));
        expect(
          winHome.hasMatch(out),
          isFalse,
          reason:
              'win home path leaked: seed=${seed + i} input=$input out=$out',
        );
      }
    });

    test('PEM private key block redaction invariant', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final out = redactSecrets(input);
        expect(
          pemBlock.hasMatch(out),
          isFalse,
          reason: 'PEM block leaked: seed=${seed + i} input=$input out=$out',
        );
      }
    });

    test('long base64 runs redacted', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final out = redactSecrets(input);
        expect(
          longBase64.hasMatch(out),
          isFalse,
          reason: 'long base64 leaked: seed=${seed + i} input=$input out=$out',
        );
      }
    });

    test('idempotence — running pipeline twice is a fixed point', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final once = sanitizeErrorMessage(redactSecrets(input));
        final twice = sanitizeErrorMessage(redactSecrets(once));
        expect(
          twice,
          equals(once),
          reason:
              'not idempotent: seed=${seed + i} input=$input once=$once twice=$twice',
        );
      }
    });

    test('stability — same input, same output across separate calls', () {
      for (var i = 0; i < iterations; i++) {
        final input = _randomPayload(rng, seed: seed + i);
        final a = sanitizeErrorMessage(redactSecrets(input));
        final b = sanitizeErrorMessage(redactSecrets(input));
        expect(
          a,
          equals(b),
          reason:
              'non-deterministic output: seed=${seed + i} input=$input a=$a b=$b',
        );
      }
    });
  });
}

/// Build a random payload seeded by [seed] so any failing run is a
/// single-seed reproducer rather than "rerun the whole suite and hope".
///
/// Mix of shapes:
/// - plain random text (catches codec edge cases)
/// - an IPv4-shaped dotted quad (exercises the ip rule)
/// - a `/home/<random>` or `/Users/<random>` path
/// - a `C:\Users\<random>` path
/// - a full synthetic PEM private key block
/// - a long random base64-looking run
/// - a composite that stitches several of the above back-to-back
String _randomPayload(Random _, {required int seed}) {
  final rng = Random(seed);
  final shape = rng.nextInt(8);
  switch (shape) {
    case 0:
      return _randomText(rng, 5 + rng.nextInt(80));
    case 1:
      return 'connecting to '
          '${rng.nextInt(256)}.${rng.nextInt(256)}'
          '.${rng.nextInt(256)}.${rng.nextInt(256)} '
          'failed';
    case 2:
      return 'open /home/${_randomIdent(rng, 3 + rng.nextInt(10))}/file';
    case 3:
      return 'open /Users/${_randomIdent(rng, 3 + rng.nextInt(10))}/x';
    case 4:
      final letter = String.fromCharCode(65 + rng.nextInt(26));
      return 'open $letter:\\Users\\${_randomIdent(rng, 3 + rng.nextInt(10))}\\f';
    case 5:
      final body = _randomBase64(rng, 60 + rng.nextInt(400));
      return '-----BEGIN OPENSSH PRIVATE KEY-----\n$body\n'
          '-----END OPENSSH PRIVATE KEY-----';
    case 6:
      return _randomBase64(rng, 200 + rng.nextInt(400));
    default:
      final ip =
          '${rng.nextInt(256)}.${rng.nextInt(256)}'
          '.${rng.nextInt(256)}.${rng.nextInt(256)}';
      final ident = _randomIdent(rng, 3 + rng.nextInt(10));
      final body = _randomBase64(rng, 250);
      return 'Error: connect to $ip as $ident failed at '
          '/home/$ident/session — cipher $body';
  }
}

String _randomText(Random rng, int length) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?@-_+*/\\\n';
  final sb = StringBuffer();
  for (var i = 0; i < length; i++) {
    sb.writeCharCode(alphabet.codeUnitAt(rng.nextInt(alphabet.length)));
  }
  return sb.toString();
}

String _randomIdent(Random rng, int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789_.-';
  final sb = StringBuffer();
  for (var i = 0; i < length; i++) {
    sb.writeCharCode(alphabet.codeUnitAt(rng.nextInt(alphabet.length)));
  }
  return sb.toString();
}

String _randomBase64(Random rng, int length) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final sb = StringBuffer();
  for (var i = 0; i < length; i++) {
    sb.writeCharCode(alphabet.codeUnitAt(rng.nextInt(alphabet.length)));
  }
  return sb.toString();
}
