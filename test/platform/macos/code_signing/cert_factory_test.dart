import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/platform/macos/code_signing/cert_factory.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';

void main() {
  group('CertFactoryException', () {
    test('toString embeds stage + message', () {
      final e = CertFactoryException('openssl_req', 'exit 1: bad config');
      expect(
        e.toString(),
        'CertFactoryException(openssl_req): exit 1: bad config',
      );
      expect(e, isA<Exception>());
    });
  });

  group('GeneratedCertMaterial', () {
    test('carries every field through the constructor', () {
      final tmp = Directory.systemTemp.createTempSync('lfs_cm_');
      try {
        final crt = File('${tmp.path}/cert.crt');
        final p12 = File('${tmp.path}/cert.p12');
        final material = GeneratedCertMaterial(
          tmpDir: tmp,
          crtPath: crt,
          p12Path: p12,
          p12Passphrase: 'transient',
        );
        expect(material.tmpDir, tmp);
        expect(material.crtPath, crt);
        expect(material.p12Path, p12);
        expect(material.p12Passphrase, 'transient');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('CertFactory.generate', () {
    test('emits cert + p12 paths on the happy path', () async {
      final runner = _FakeProcessRunner.success();
      final factory = CertFactory(runner: runner);

      final material = await factory.generate();

      expect(material.crtPath.path, endsWith('/cert.crt'));
      expect(material.p12Path.path, endsWith('/cert.p12'));
      expect(material.p12Passphrase, isNotEmpty);

      // Two openssl invocations: req + pkcs12 -export -legacy.
      expect(runner.calls, hasLength(2));
      expect(
        runner.calls[0].arguments,
        containsAll(['req', '-x509', '-newkey', 'rsa:2048']),
      );
      expect(
        runner.calls[1].arguments,
        containsAll(['pkcs12', '-export', '-legacy']),
      );

      material.tmpDir.deleteSync(recursive: true);
    });

    test('passes commonName + organisation through the cnf file', () async {
      final runner = _FakeProcessRunner.success();
      final factory = CertFactory(runner: runner);

      await factory.generate(
        commonName: 'Custom Name',
        organisation: 'Custom Org',
      );

      // Read the cnf file the factory wrote — first arg of the req
      // call is `req`, then `-x509` etc.; the `-config` flag points
      // at the cnf path.
      final reqArgs = runner.calls[0].arguments;
      final cnfIdx = reqArgs.indexOf('-config');
      expect(cnfIdx, isNot(-1));
      final cnfPath = reqArgs[cnfIdx + 1];
      final cnf = File(cnfPath).readAsStringSync();
      expect(cnf, contains('CN = Custom Name'));
      expect(cnf, contains('O  = Custom Org'));

      // Cleanup the tmp dir openssl-step would normally drop into.
      Directory(File(cnfPath).parent.path).deleteSync(recursive: true);
    });

    test('passes validityDays through to -days', () async {
      final runner = _FakeProcessRunner.success();
      final factory = CertFactory(runner: runner);

      await factory.generate(validityDays: 1);

      final reqArgs = runner.calls[0].arguments;
      final daysIdx = reqArgs.indexOf('-days');
      expect(daysIdx, isNot(-1));
      expect(reqArgs[daysIdx + 1], '1');

      final cnfIdx = reqArgs.indexOf('-config');
      Directory(
        File(reqArgs[cnfIdx + 1]).parent.path,
      ).deleteSync(recursive: true);
    });

    test('throws + cleans up tmp on openssl req failure', () async {
      final runner = _FakeProcessRunner.failingOn(
        attemptIndex: 0,
        exitCode: 1,
        stderr: 'bad cnf syntax',
      );
      final factory = CertFactory(runner: runner);

      await expectLater(
        () => factory.generate(),
        throwsA(
          isA<CertFactoryException>()
              .having((e) => e.stage, 'stage', 'openssl_req')
              .having((e) => e.message, 'message', contains('bad cnf syntax')),
        ),
      );

      // Tmp dir should have been cleaned up — the runner only saw
      // one call (the failed req), so the cnf path is the only
      // artefact and even it was wiped.
      final cnfPath = runner
          .calls[0]
          .arguments[runner.calls[0].arguments.indexOf('-config') + 1];
      expect(Directory(File(cnfPath).parent.path).existsSync(), isFalse);
    });

    test('throws + cleans up tmp on openssl pkcs12 failure', () async {
      final runner = _FakeProcessRunner.failingOn(
        attemptIndex: 1,
        exitCode: 2,
        stderr: 'pkcs12 export blew up',
      );
      final factory = CertFactory(runner: runner);

      await expectLater(
        () => factory.generate(),
        throwsA(
          isA<CertFactoryException>()
              .having((e) => e.stage, 'stage', 'openssl_pkcs12')
              .having(
                (e) => e.message,
                'message',
                contains('pkcs12 export blew up'),
              ),
        ),
      );

      // Both calls fired before the failure; tmp still cleaned up.
      expect(runner.calls, hasLength(2));
      final cnfPath = runner
          .calls[0]
          .arguments[runner.calls[0].arguments.indexOf('-config') + 1];
      expect(Directory(File(cnfPath).parent.path).existsSync(), isFalse);
    });
  });
}

/// Records every invocation; returns canned ProcessResults.
class _FakeProcessRunner implements IProcessRunner {
  _FakeProcessRunner._({
    this.failAt = -1,
    this.failExitCode = 1,
    this.failStderr = '',
  });

  factory _FakeProcessRunner.success() => _FakeProcessRunner._();

  factory _FakeProcessRunner.failingOn({
    required int attemptIndex,
    required int exitCode,
    required String stderr,
  }) => _FakeProcessRunner._(
    failAt: attemptIndex,
    failExitCode: exitCode,
    failStderr: stderr,
  );

  final int failAt;
  final int failExitCode;
  final String failStderr;
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
    if (attempt == failAt) {
      return ProcessResult(0, failExitCode, '', failStderr);
    }
    return ProcessResult(0, 0, '', '');
  }
}
