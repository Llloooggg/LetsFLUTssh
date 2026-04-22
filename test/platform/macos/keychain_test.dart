import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/keychain.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';

class _FakeRunner implements IProcessRunner {
  final List<List<String>> calls = [];
  final List<ProcessResult> responses;
  int _cursor = 0;

  _FakeRunner(this.responses);

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  }) async {
    calls.add([executable, ...arguments]);
    return responses[_cursor++];
  }
}

void main() {
  group('Keychain', () {
    test('hasCertificate calls find-certificate and maps exit code', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      final hit = await kc.hasCertificate('My CN');
      expect(hit, isTrue);
      expect(runner.calls.single, [
        '/usr/bin/security',
        'find-certificate',
        '-c',
        'My CN',
        '/tmp/k',
      ]);
    });

    test('hasCertificate returns false on non-zero exit', () async {
      final runner = _FakeRunner([ProcessResult(1, 1, '', '')]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      expect(await kc.hasCertificate('Nope'), isFalse);
    });

    test('importPkcs12 grants codesign + security ACL', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      await kc.importPkcs12(p12Path: File('/tmp/c.p12'), passphrase: 'pw');
      final call = runner.calls.single;
      expect(call, contains('import'));
      expect(call, contains('/tmp/c.p12'));
      // The paired `-T /usr/bin/codesign` + `-T /usr/bin/security`
      // ACL is what lets later codesign + security invocations
      // access the private key without a password prompt — the
      // regression guard asserts both are on every import call.
      expect(call, containsAllInOrder(['-T', '/usr/bin/codesign']));
      expect(call, containsAllInOrder(['-T', '/usr/bin/security']));
    });

    test('importPkcs12 throws KeychainException on non-zero exit', () async {
      final runner = _FakeRunner([ProcessResult(1, 1, '', 'bad p12')]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      await expectLater(
        kc.importPkcs12(p12Path: File('/tmp/c.p12'), passphrase: 'pw'),
        throwsA(isA<KeychainException>()),
      );
    });

    test('addTrustedCert scopes the trust to codeSign', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      await kc.addTrustedCert(File('/tmp/c.crt'));
      final call = runner.calls.single;
      expect(call, contains('add-trusted-cert'));
      // -p codeSign narrows the trust scope so the user-level trust
      // entry doesn't leak to TLS / email validation.
      expect(call, containsAllInOrder(['-p', 'codeSign']));
      expect(call, containsAllInOrder(['-r', 'trustRoot']));
    });

    test('uninstall delete-identity + delete-certificate + untrust', () async {
      final runner = _FakeRunner([
        ProcessResult(1, 0, '', ''),
        ProcessResult(2, 0, '', ''),
        ProcessResult(3, 0, '', ''),
      ]);
      final kc = Keychain(runner: runner, keychainPath: '/tmp/k');
      await kc.removeTrustedCert();
      await kc.deleteIdentity('CN');
      await kc.deleteCertificate('CN');
      expect(runner.calls, hasLength(3));
      expect(runner.calls[0], contains('remove-trusted-cert'));
      expect(runner.calls[1], contains('delete-identity'));
      expect(runner.calls[2], contains('delete-certificate'));
    });
  });
}
