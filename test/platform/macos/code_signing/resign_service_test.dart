import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/platform/macos/code_signing/cert_factory.dart';
import 'package:letsflutssh/platform/macos/code_signing/codesigner.dart';
import 'package:letsflutssh/platform/macos/code_signing/keychain.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';
import 'package:letsflutssh/platform/macos/code_signing/resign_service.dart';

void main() {
  group('ResignOutcome enum', () {
    test('all four cases are reachable + distinct', () {
      expect(ResignOutcome.values, hasLength(4));
      expect(ResignOutcome.values.toSet(), {
        ResignOutcome.succeeded,
        ResignOutcome.reusedExisting,
        ResignOutcome.cancelledOrFailed,
        ResignOutcome.bundleNotWritable,
      });
    });
  });

  group('ResignService.ensureIdentity', () {
    test(
      'returns false + does NOT generate when cert already present',
      () async {
        final runner = _RoutingRunner({
          // hasCertificate → exit 0 = present.
          ('/usr/bin/security', 'find-certificate'): ProcessResult(
            0,
            0,
            '',
            '',
          ),
        });
        final service = ResignService(
          certFactory: CertFactory(runner: runner),
          keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
          codesigner: Codesigner(runner: runner),
        );

        final created = await service.ensureIdentity(commonName: 'Self-Sign');

        expect(created, isFalse);
        // Only one call — find-certificate. No openssl, no import.
        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.arguments.first, 'find-certificate');
      },
    );

    test('returns true + runs full pipeline when no cert is present', () async {
      final runner = _RoutingRunner({
        // No cert yet → find-certificate returns non-zero.
        ('/usr/bin/security', 'find-certificate'): ProcessResult(0, 1, '', ''),
        // openssl req + pkcs12 succeed.
        ('openssl', 'req'): ProcessResult(0, 0, '', ''),
        ('openssl', 'pkcs12'): ProcessResult(0, 0, '', ''),
        // import + add-trusted-cert succeed.
        ('/usr/bin/security', 'import'): ProcessResult(0, 0, '', ''),
        ('/usr/bin/security', 'add-trusted-cert'): ProcessResult(0, 0, '', ''),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
        codesigner: Codesigner(runner: runner),
      );

      final created = await service.ensureIdentity(commonName: 'Self-Sign');

      expect(created, isTrue);
      // Should have routed: find-certificate, openssl req, openssl
      // pkcs12, security import, add-trusted-cert.
      final firstArgs = runner.calls.map((c) => c.arguments.first).toList();
      expect(firstArgs, [
        'find-certificate',
        'req',
        'pkcs12',
        'import',
        'add-trusted-cert',
      ]);
    });

    test('cleans up the tmp dir even when add-trusted-cert fails', () async {
      final runner = _RoutingRunner({
        ('/usr/bin/security', 'find-certificate'): ProcessResult(0, 1, '', ''),
        ('openssl', 'req'): ProcessResult(0, 0, '', ''),
        ('openssl', 'pkcs12'): ProcessResult(0, 0, '', ''),
        ('/usr/bin/security', 'import'): ProcessResult(0, 0, '', ''),
        // Final step fails — user dismissed the prompt.
        ('/usr/bin/security', 'add-trusted-cert'): ProcessResult(
          0,
          1,
          '',
          'user cancelled',
        ),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
        codesigner: Codesigner(runner: runner),
      );

      // Service rethrows the KeychainException — caller (UI) decides
      // whether to map it to ResignOutcome.cancelledOrFailed.
      await expectLater(
        () => service.ensureIdentity(commonName: 'Self-Sign'),
        throwsA(isA<KeychainException>()),
      );

      // The cnf path lives under a tmpDir the cert factory created
      // — by the time we observe it, the finally block must have
      // wiped it.
      final reqArgs = runner.calls
          .firstWhere((c) => c.arguments.first == 'req')
          .arguments;
      final cnfPath = reqArgs[reqArgs.indexOf('-config') + 1];
      expect(Directory(File(cnfPath).parent.path).existsSync(), isFalse);
    });
  });

  group('ResignService.resignBundle', () {
    late Directory tmp;
    late Directory bundle;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lfs_resign_svc_');
      bundle = Directory('${tmp.path}/MyApp.app')..createSync();
      Directory('${bundle.path}/Contents').createSync();
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('returns bundleNotWritable when the probe-write fails', () async {
      // Point at a path that doesn't exist — `writeAsStringSync`
      // raises FileSystemException, which the service maps to
      // bundleNotWritable.
      final runner = _RoutingRunner({});
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner),
        codesigner: Codesigner(runner: runner),
      );

      final outcome = await service.resignBundle(
        appBundle: Directory('/this/path/does/not/exist'),
      );
      expect(outcome, ResignOutcome.bundleNotWritable);
      // No process spawned at all — short-circuited before codesign.
      expect(runner.calls, isEmpty);
    });

    test('returns succeeded when the codesign verify passes', () async {
      final runner = _RoutingRunner({
        // extractEntitlements → empty plist on stdout.
        ('/usr/bin/codesign', '-d'): ProcessResult(
          0,
          0,
          '<plist><dict/></plist>',
          '',
        ),
        // Every signing pass + verify exits 0.
        ('/usr/bin/codesign', '--force'): ProcessResult(0, 0, '', ''),
        ('/usr/bin/codesign', '--verify'): ProcessResult(0, 0, '', ''),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner),
        codesigner: Codesigner(runner: runner),
      );

      final outcome = await service.resignBundle(appBundle: bundle);
      expect(outcome, ResignOutcome.succeeded);
    });

    test('returns cancelledOrFailed when verify exits non-zero', () async {
      final runner = _RoutingRunner({
        ('/usr/bin/codesign', '-d'): ProcessResult(
          0,
          0,
          '<plist><dict/></plist>',
          '',
        ),
        ('/usr/bin/codesign', '--force'): ProcessResult(0, 0, '', ''),
        ('/usr/bin/codesign', '--verify'): ProcessResult(
          0,
          1,
          '',
          'invalid signature',
        ),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner),
        codesigner: Codesigner(runner: runner),
      );

      final outcome = await service.resignBundle(appBundle: bundle);
      expect(outcome, ResignOutcome.cancelledOrFailed);
    });
  });

  group('ResignService.uninstallIdentity', () {
    test('runs delete-identity then delete-certificate', () async {
      final runner = _RoutingRunner({
        ('/usr/bin/security', 'delete-identity'): ProcessResult(0, 0, '', ''),
        ('/usr/bin/security', 'delete-certificate'): ProcessResult(
          0,
          0,
          '',
          '',
        ),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
        codesigner: Codesigner(runner: runner),
      );

      await service.uninstallIdentity(commonName: 'Self-Sign');

      expect(runner.calls.map((c) => c.arguments.first).toList(), [
        'delete-identity',
        'delete-certificate',
      ]);
    });
  });

  group('ResignService.hasIdentity', () {
    test('mirrors keychain.hasCertificate', () async {
      final runner = _RoutingRunner({
        ('/usr/bin/security', 'find-certificate'): ProcessResult(0, 0, '', ''),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
        codesigner: Codesigner(runner: runner),
      );

      expect(await service.hasIdentity(commonName: 'Self-Sign'), isTrue);
    });

    test('returns false when the cert is missing', () async {
      final runner = _RoutingRunner({
        ('/usr/bin/security', 'find-certificate'): ProcessResult(
          0,
          44,
          '',
          'no matching cert',
        ),
      });
      final service = ResignService(
        certFactory: CertFactory(runner: runner),
        keychain: Keychain(runner: runner, keychainPath: '/tmp/k'),
        codesigner: Codesigner(runner: runner),
      );

      expect(await service.hasIdentity(), isFalse);
    });
  });
}

/// Routes calls to canned [ProcessResult]s by `(executable, firstArg)`.
/// Any unmatched call returns `ProcessResult(0, 0, '', '')` — so tests
/// only need to declare the calls whose outcome they care about.
class _RoutingRunner implements IProcessRunner {
  _RoutingRunner(this._table);

  final Map<(String, String), ProcessResult> _table;
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
    calls.add((executable: executable, arguments: List.of(arguments)));
    final firstArg = arguments.isEmpty ? '' : arguments.first;
    return _table[(executable, firstArg)] ?? ProcessResult(0, 0, '', '');
  }
}
