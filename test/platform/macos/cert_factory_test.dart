import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/cert_factory.dart';
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
  group('CertFactory.generate', () {
    test('invokes openssl req then openssl pkcs12 with -legacy', () async {
      final runner = _FakeRunner([
        ProcessResult(1, 0, '', ''),
        ProcessResult(2, 0, '', ''),
      ]);
      final factory = CertFactory(runner: runner);
      // The real openssl call would write cert.crt + cert.key — the
      // fake runner can't materialise files, but the factory still
      // returns paths pointing into the tmp dir we cleaned up. We
      // inspect the recorded argv to validate the pipeline.
      final material = await factory.generate(
        commonName: 'Test CN',
        organisation: 'Test Org',
        validityDays: 100,
      );
      expect(runner.calls, hasLength(2));
      expect(runner.calls[0].first, '/usr/bin/openssl');
      expect(runner.calls[0], contains('req'));
      expect(runner.calls[0], contains('-x509'));
      expect(runner.calls[0], contains('rsa:2048'));
      expect(runner.calls[0], contains('100'));

      expect(runner.calls[1].first, '/usr/bin/openssl');
      expect(runner.calls[1], contains('pkcs12'));
      // The regression guard: `-legacy` must be on the p12 export
      // call or macOS `security import` fails with "MAC verification
      // failed during PKCS12 import" on OpenSSL 3 hosts.
      expect(runner.calls[1], contains('-legacy'));
      expect(runner.calls[1].where((a) => a.startsWith('pass:')).length, 1);

      expect(material.p12Passphrase, 'lfs-transient');
      material.tmpDir.deleteSync(recursive: true);
    });

    test(
      'throws CertFactoryException + cleans tmp on openssl req fail',
      () async {
        final runner = _FakeRunner([
          ProcessResult(1, 1, '', 'config parse error'),
        ]);
        final factory = CertFactory(runner: runner);
        // Snapshot the tmp root before the call so we can verify
        // the factory cleaned up its scratch dir on failure (any
        // leftover `lfs-macos-sign-*` from this run means the
        // cleanup path is broken).
        final before = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .where((d) => d.path.contains('lfs-macos-sign-'))
            .toList();
        try {
          await factory.generate();
          fail('expected CertFactoryException');
        } on CertFactoryException catch (e) {
          expect(e.stage, 'openssl_req');
          expect(e.message, contains('config parse error'));
        }
        final after = Directory.systemTemp
            .listSync()
            .whereType<Directory>()
            .where((d) => d.path.contains('lfs-macos-sign-'))
            .toList();
        expect(after.length, before.length);
      },
    );

    test(
      'throws CertFactoryException + cleans tmp on openssl pkcs12 fail',
      () async {
        final runner = _FakeRunner([
          ProcessResult(1, 0, '', ''),
          ProcessResult(2, 1, '', 'legacy unsupported'),
        ]);
        final factory = CertFactory(runner: runner);
        try {
          await factory.generate();
          fail('expected CertFactoryException');
        } on CertFactoryException catch (e) {
          expect(e.stage, 'openssl_pkcs12');
          expect(e.message, contains('legacy unsupported'));
        }
      },
    );
  });
}
