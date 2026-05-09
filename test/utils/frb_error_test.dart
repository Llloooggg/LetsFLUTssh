import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/frb_error.dart';

void main() {
  group('FrbError.fromWire', () {
    test('empty string surfaces as generic with empty detail', () {
      final err = FrbError.fromWire('');
      expect(err.kind, 'generic');
      expect(err.detail, isEmpty);
    });

    test('plain (non-JSON) string falls through to generic with the '
        'original text as detail', () {
      final err = FrbError.fromWire('something went wrong');
      expect(err.kind, 'generic');
      expect(err.detail, 'something went wrong');
    });

    test('well-formed JSON envelope routes kind and detail straight '
        'through', () {
      final err = FrbError.fromWire(
        '{"kind":"auth_failed","detail":"wrong password"}',
      );
      expect(err.kind, 'auth_failed');
      expect(err.detail, 'wrong password');
    });

    test('JSON without expected fields falls back to generic so the wire '
        'stays the detail rather than throwing', () {
      final err = FrbError.fromWire('{"unrelated": "field"}');
      expect(err.kind, 'generic');
      expect(err.detail, '{"unrelated": "field"}');
    });

    test('JSON with non-string kind falls back to generic — pin the '
        'type-check on the discriminator so a stray int from a misformed '
        'producer does not surface as a routable kind', () {
      final err = FrbError.fromWire('{"kind":42,"detail":"x"}');
      expect(err.kind, 'generic');
    });

    test('JSON with non-string detail falls back to generic', () {
      final err = FrbError.fromWire('{"kind":"timeout","detail":42}');
      expect(err.kind, 'generic');
    });

    test('malformed JSON-shaped input (starts with { but parse fails) '
        'falls back to generic with the wire as detail', () {
      final err = FrbError.fromWire('{not actually json');
      expect(err.kind, 'generic');
      expect(err.detail, '{not actually json');
    });

    test('JSON envelope with empty detail still lands in the typed '
        'bucket — empty detail is legitimate for variants like '
        'auth_failed where the kind alone carries the routing', () {
      final err = FrbError.fromWire('{"kind":"auth_failed","detail":""}');
      expect(err.kind, 'auth_failed');
      expect(err.detail, isEmpty);
    });
  });

  group('FrbError.from', () {
    test('FrbError input passes through unchanged', () {
      const original = FrbError(kind: 'timeout', detail: 'slow');
      expect(identical(FrbError.from(original), original), isTrue);
    });

    test('String input routes through fromWire', () {
      final err = FrbError.from('{"kind":"cancelled","detail":""}');
      expect(err.kind, 'cancelled');
    });

    test('arbitrary thrown object surfaces as generic with toString '
        'as detail', () {
      final err = FrbError.from(StateError('not initialized'));
      expect(err.kind, 'generic');
      expect(err.detail, contains('not initialized'));
    });
  });

  group('FrbError variant predicates', () {
    test('every kind predicate fires for the matching wire name and '
        'is false for any other kind', () {
      const cases = <String, bool Function(FrbError)>{
        'cancelled': _isCancelled,
        'auth_failed': _isAuthFailed,
        'passphrase_required': _isPassphraseRequired,
        'passphrase_incorrect': _isPassphraseIncorrect,
        'host_key_rejected': _isHostKeyRejected,
        'timeout': _isTimeout,
        'vault_corrupt': _isVaultCorrupt,
        'vault_platform_unsupported': _isVaultPlatformUnsupported,
      };
      for (final entry in cases.entries) {
        final matched = FrbError(kind: entry.key, detail: '');
        expect(
          entry.value(matched),
          isTrue,
          reason: '${entry.key} predicate must match its own kind',
        );
        // Every other variant's predicate must reject this kind.
        for (final other in cases.entries) {
          if (other.key == entry.key) continue;
          expect(
            other.value(matched),
            isFalse,
            reason: '${other.key} predicate must not match ${entry.key}',
          );
        }
      }
    });

    test('predicates are false for the generic bucket', () {
      const generic = FrbError(kind: 'generic', detail: 'x');
      expect(generic.isCancelled, isFalse);
      expect(generic.isAuthFailed, isFalse);
      expect(generic.isPassphraseRequired, isFalse);
      expect(generic.isPassphraseIncorrect, isFalse);
      expect(generic.isHostKeyRejected, isFalse);
      expect(generic.isTimeout, isFalse);
      expect(generic.isVaultCorrupt, isFalse);
      expect(generic.isVaultPlatformUnsupported, isFalse);
    });

    test('vault_corrupt predicate gates the destructive reset cascade — '
        'verify the discriminator stays distinct from the recoverable '
        'kind=vault bucket', () {
      const corrupt = FrbError(
        kind: 'vault_corrupt',
        detail: 'truncated header',
      );
      const recoverable = FrbError(kind: 'vault', detail: 'wrong PIN');
      expect(corrupt.isVaultCorrupt, isTrue);
      expect(
        recoverable.isVaultCorrupt,
        isFalse,
        reason: 'kind=vault must NOT trigger reset — only vault_corrupt',
      );
    });
  });

  group('FrbError.toString', () {
    test('renders kind alone when detail is empty', () {
      const err = FrbError(kind: 'auth_failed', detail: '');
      expect(err.toString(), '[auth_failed]');
    });

    test('renders kind + detail when both populated', () {
      const err = FrbError(kind: 'sftp', detail: 'no such file');
      expect(err.toString(), '[sftp] no such file');
    });
  });
}

bool _isCancelled(FrbError e) => e.isCancelled;
bool _isAuthFailed(FrbError e) => e.isAuthFailed;
bool _isPassphraseRequired(FrbError e) => e.isPassphraseRequired;
bool _isPassphraseIncorrect(FrbError e) => e.isPassphraseIncorrect;
bool _isHostKeyRejected(FrbError e) => e.isHostKeyRejected;
bool _isTimeout(FrbError e) => e.isTimeout;
bool _isVaultCorrupt(FrbError e) => e.isVaultCorrupt;
bool _isVaultPlatformUnsupported(FrbError e) => e.isVaultPlatformUnsupported;
