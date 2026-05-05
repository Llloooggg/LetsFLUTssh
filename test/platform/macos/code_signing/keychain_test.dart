import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/platform/macos/code_signing/keychain.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';

void main() {
  group('KeychainException', () {
    test('toString embeds stage + message', () {
      final e = KeychainException(
        'import',
        'security import exited 1: bad p12',
      );
      expect(
        e.toString(),
        'KeychainException(import): security import exited 1: bad p12',
      );
      expect(e, isA<Exception>());
    });
  });

  group('Keychain constructor', () {
    test('defaults keychainPath to ~/Library/Keychains/login.keychain-db', () {
      final kc = Keychain(runner: _FakeProcessRunner.alwaysSuccess());
      // We can't assume HOME is set in every test env, but the
      // default must end with the canonical login keychain suffix.
      expect(kc.keychainPath, endsWith('/Library/Keychains/login.keychain-db'));
    });

    test('honours an explicit keychainPath override', () {
      final kc = Keychain(
        runner: _FakeProcessRunner.alwaysSuccess(),
        keychainPath: '/tmp/scratch.keychain-db',
      );
      expect(kc.keychainPath, '/tmp/scratch.keychain-db');
    });
  });

  group('Keychain.hasCertificate', () {
    test('returns true on exit 0 + records canonical argv', () async {
      final runner = _FakeProcessRunner.alwaysSuccess();
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');

      expect(await kc.hasCertificate('Self-Sign'), isTrue);
      expect(runner.calls.single.executable, '/usr/bin/security');
      expect(runner.calls.single.arguments, [
        'find-certificate',
        '-c',
        'Self-Sign',
        '/tmp/k',
      ]);
    });

    test('returns false on non-zero exit', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 44, '', 'no matching cert'),
      );
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      expect(await kc.hasCertificate('Missing'), isFalse);
    });
  });

  group('Keychain.importPkcs12', () {
    test(
      'passes the p12 path + passphrase + grants -T to codesign + security',
      () async {
        final runner = _FakeProcessRunner.alwaysSuccess();
        final kc = Keychain(runner: runner, keychainPath: '/tmp/k');

        await kc.importPkcs12(
          p12Path: File('/tmp/cert.p12'),
          passphrase: 'transient',
        );

        expect(runner.calls.single.executable, '/usr/bin/security');
        expect(
          runner.calls.single.arguments,
          containsAllInOrder([
            'import',
            '/tmp/cert.p12',
            '-k',
            '/tmp/k',
            '-P',
            'transient',
            '-T',
            '/usr/bin/codesign',
            '-T',
            '/usr/bin/security',
          ]),
        );
      },
    );

    test('throws KeychainException(import) on non-zero exit', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 1, '', 'wrong passphrase'),
      );
      final kc = Keychain(runner: runner);

      await expectLater(
        () =>
            kc.importPkcs12(p12Path: File('/tmp/cert.p12'), passphrase: 'bad'),
        throwsA(
          isA<KeychainException>()
              .having((e) => e.stage, 'stage', 'import')
              .having(
                (e) => e.message,
                'message',
                contains('wrong passphrase'),
              ),
        ),
      );
    });
  });

  group('Keychain.addTrustedCert', () {
    test('writes a user-domain codeSign trust entry', () async {
      final runner = _FakeProcessRunner.alwaysSuccess();
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');

      await kc.addTrustedCert(File('/tmp/cert.crt'));

      expect(runner.calls.single.executable, '/usr/bin/security');
      expect(runner.calls.single.arguments, [
        'add-trusted-cert',
        '-r',
        'trustRoot',
        '-p',
        'codeSign',
        '-k',
        '/tmp/k',
        '/tmp/cert.crt',
      ]);
    });

    test(
      'throws KeychainException(add-trusted-cert) on non-zero exit',
      () async {
        final runner = _FakeProcessRunner.canned(
          ProcessResult(0, 1, '', 'user dismissed prompt'),
        );
        final kc = Keychain(runner: runner);

        await expectLater(
          () => kc.addTrustedCert(File('/tmp/cert.crt')),
          throwsA(
            isA<KeychainException>()
                .having((e) => e.stage, 'stage', 'add-trusted-cert')
                .having(
                  (e) => e.message,
                  'message',
                  contains('user dismissed prompt'),
                ),
          ),
        );
      },
    );
  });

  group('Keychain.deleteIdentity / deleteCertificate', () {
    test(
      'deleteIdentity records canonical argv + does not throw on failure',
      () async {
        // delete-identity intentionally swallows errors — re-running
        // an uninstall after a partial run must remain idempotent.
        final runner = _FakeProcessRunner.canned(
          ProcessResult(0, 1, '', 'nothing to delete'),
        );
        final kc = Keychain(runner: runner, keychainPath: '/tmp/k');

        await kc.deleteIdentity('Self-Sign');

        expect(runner.calls.single.arguments, [
          'delete-identity',
          '-c',
          'Self-Sign',
          '/tmp/k',
        ]);
      },
    );

    test(
      'deleteCertificate records canonical argv + does not throw on failure',
      () async {
        final runner = _FakeProcessRunner.canned(
          ProcessResult(0, 1, '', 'nothing to delete'),
        );
        final kc = Keychain(runner: runner, keychainPath: '/tmp/k');

        await kc.deleteCertificate('Self-Sign');

        expect(runner.calls.single.arguments, [
          'delete-certificate',
          '-c',
          'Self-Sign',
          '/tmp/k',
        ]);
      },
    );
  });
}

class _FakeProcessRunner implements IProcessRunner {
  _FakeProcessRunner._raw(this._behaviour);

  factory _FakeProcessRunner.alwaysSuccess() =>
      _FakeProcessRunner._raw((_) => ProcessResult(0, 0, '', ''));

  factory _FakeProcessRunner.canned(ProcessResult result) =>
      _FakeProcessRunner._raw((_) => result);

  final ProcessResult Function(int attempt) _behaviour;
  final List<({String executable, List<String> arguments})> calls = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  }) async {
    final attempt = calls.length;
    calls.add((executable: executable, arguments: List.of(arguments)));
    return _behaviour(attempt);
  }
}
