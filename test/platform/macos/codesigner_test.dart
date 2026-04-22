import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/codesigner.dart';
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
  Directory makeFakeBundle() {
    final tmp = Directory.systemTemp.createTempSync('lfs-codesigner-bundle-');
    Directory('${tmp.path}/Contents').createSync(recursive: true);
    Directory('${tmp.path}/Contents/Frameworks').createSync(recursive: true);
    return tmp;
  }

  group('Codesigner.extractEntitlements', () {
    test('returns stdout plist on success', () async {
      final runner = _FakeRunner([
        ProcessResult(1, 0, '<plist>...</plist>', ''),
      ]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);
      final ent = await signer.extractEntitlements(tmp);
      expect(ent, '<plist>...</plist>');
      expect(
        runner.calls.single,
        containsAllInOrder(['-d', '--entitlements', ':-']),
      );
    });

    test(
      'returns null on empty output (ad-hoc with no entitlements)',
      () async {
        final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
        final tmp = makeFakeBundle();
        addTearDown(() => tmp.deleteSync(recursive: true));
        final signer = Codesigner(runner: runner);
        expect(await signer.extractEntitlements(tmp), isNull);
      },
    );

    test('returns null on non-zero exit', () async {
      final runner = _FakeRunner([ProcessResult(1, 1, '', 'err')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);
      expect(await signer.extractEntitlements(tmp), isNull);
    });
  });

  group('Codesigner.resignInsideOut', () {
    test('signs empty bundle with outer --options runtime', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);

      await signer.resignInsideOut(appBundle: tmp, commonName: 'Test CN');

      // Exactly one codesign call (no dylibs / frameworks / xpc in
      // the fake bundle), and it targets the outer .app.
      expect(runner.calls, hasLength(1));
      final call = runner.calls.single;
      expect(call.first, '/usr/bin/codesign');
      expect(call, containsAllInOrder(['--options', 'runtime']));
      expect(call, containsAllInOrder(['--sign', 'Test CN']));
      expect(call, contains(tmp.path));
    });

    test('outer bundle receives --entitlements when plist supplied', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);

      await signer.resignInsideOut(
        appBundle: tmp,
        commonName: 'Test CN',
        entitlementsPlist: '<?xml version="1.0"?><plist><dict></dict></plist>',
      );
      final call = runner.calls.single;
      final entIdx = call.indexOf('--entitlements');
      expect(entIdx, greaterThanOrEqualTo(0));
      // Path value follows the flag, file was produced in a tmp
      // dir. Existence check happens inside the factory (runner is
      // stubbed here).
      expect(call[entIdx + 1], endsWith('entitlements.plist'));
    });

    test('CodesignException carries failing subpath', () async {
      final runner = _FakeRunner([ProcessResult(1, 1, '', 'sig invalid')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);
      await expectLater(
        signer.resignInsideOut(appBundle: tmp, commonName: 'Test CN'),
        throwsA(
          isA<CodesignException>()
              .having((e) => e.subpath, 'subpath', tmp.path)
              .having((e) => e.message, 'message', contains('sig invalid')),
        ),
      );
    });
  });

  group('Codesigner.verify', () {
    test('returns true on exit 0', () async {
      final runner = _FakeRunner([ProcessResult(1, 0, '', '')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);
      expect(await signer.verify(tmp), isTrue);
    });

    test('returns false on non-zero exit', () async {
      final runner = _FakeRunner([ProcessResult(1, 1, '', 'broken')]);
      final tmp = makeFakeBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signer = Codesigner(runner: runner);
      expect(await signer.verify(tmp), isFalse);
    });
  });
}
