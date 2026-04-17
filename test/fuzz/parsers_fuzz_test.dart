// Property-based fuzz suite for the parsers that ingest untrusted bytes.
//
// CLAUDE.md mandates that any function reading untrusted input has a
// corresponding fuzz test that confirms it never throws an unhandled
// exception, regardless of the shape of the input. A "handled" outcome
// is either a typed return (`null`, an `Either`, a documented result
// type) or a typed exception that callers know to catch. Anything else
// — RangeError, FormatException, StateError leaking through to a
// caller that wasn't expecting it — is a defect.
//
// The harness here is intentionally tiny: deterministic Random.secure()
// would make the tests flaky; we use a seeded Random so failing cases
// are reproducible from the seed printed in the test name. Each parser
// gets a few thousand iterations of bytes / string shapes; the budget
// is small enough to run in `make test` but big enough to surface most
// fence-post mistakes (out-of-bound index, wrong base64 length, etc.).

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';

const _seed = 0xC0FFEE;
const _iterations = 2000;

/// Build a printable-but-arbitrary string up to [maxLen] characters from
/// [rng]. Mixes ASCII and a handful of multi-byte sequences so the parser
/// sees both happy-path bytes and trip-wires (control chars, fragments
/// of escape sequences, unbalanced quotes).
String _rngString(Random rng, int maxLen) {
  final len = rng.nextInt(maxLen);
  final buf = StringBuffer();
  const chars =
      'abcdefghijklmnopqrstuvwxyz0123456789'
      "ABCDEFGHIJKLMNOPQRSTUVWXYZ:./@#%-=+_<>?[]{}\\'\"`~ \t\n\r\u0000";
  for (var i = 0; i < len; i++) {
    buf.writeCharCode(chars.codeUnitAt(rng.nextInt(chars.length)));
  }
  return buf.toString();
}

void main() {
  final rng = Random(_seed);

  group('Fuzz: KnownHostsManager.importFromString', () {
    test(
      'never throws on $_iterations random byte-shape inputs (seed=$_seed)',
      () async {
        final manager = KnownHostsManager();
        for (var i = 0; i < _iterations; i++) {
          final input = _rngString(rng, 4096);
          // Returns the count of new entries added (or 0). Anything that
          // throws here — including a stack frame from inside split/regex —
          // is a parser defect, even on garbage input.
          await expectLater(
            () => manager.importFromString(input),
            returnsNormally,
            reason: 'iteration=$i input.length=${input.length}',
          );
        }
      },
    );
  });

  group('Fuzz: DeepLinkHandler.parseConnectUri', () {
    test('never throws on $_iterations random URI inputs (seed=$_seed)', () {
      for (var i = 0; i < _iterations; i++) {
        // Build a valid scheme + path so Uri.parse itself doesn't throw —
        // we want to fuzz the parser's interpretation of the query
        // parameters, not the dart:core URI parser.
        final query = _rngString(rng, 256);
        final encoded = Uri.encodeQueryComponent(query);
        // Random key-value sprinkling so parameter combinations exercise
        // the host/user/port/auth branches.
        final extras = <String, String>{};
        for (var j = 0; j < rng.nextInt(6); j++) {
          extras[_rngString(rng, 16)] = _rngString(rng, 32);
        }
        final uriStr =
            'letsflutssh://connect?host=${_rngString(rng, 64)}'
            '&user=${_rngString(rng, 64)}'
            '&port=${rng.nextInt(200000)}'
            '&junk=$encoded'
            '${extras.entries.map((e) => '&${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join()}';
        Uri? uri;
        try {
          uri = Uri.parse(uriStr);
        } catch (_) {
          continue; // dart:core URI was unhappy; skip — not what we fuzz
        }
        expect(
          () => DeepLinkHandler.parseConnectUri(uri!),
          returnsNormally,
          reason:
              'iteration=$i uri=${uri.toString().substring(0, uri.toString().length.clamp(0, 100))}',
        );
      }
    });
  });

  group('Fuzz: utf8.decode + jsonDecode pipeline (ARB / manifest reader)', () {
    test(
      'never throws unhandled errors on $_iterations random byte buffers (seed=$_seed)',
      () {
        // Emulates what every JSON-shaped parser in the project does:
        // utf8.decode(bytes) followed by jsonDecode. Standard exceptions
        // (FormatException) are expected; every other type is a bug.
        for (var i = 0; i < _iterations; i++) {
          final byteCount = rng.nextInt(1024);
          final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
          try {
            final str = utf8.decode(bytes, allowMalformed: true);
            jsonDecode(str);
          } on FormatException {
            // Expected on garbage — the contract says callers handle this.
          } catch (e, stack) {
            fail('unexpected exception $e at iteration=$i: $stack');
          }
        }
      },
    );
  });
}
