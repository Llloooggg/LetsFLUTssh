import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/platform/macos/code_signing/codesigner.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';

void main() {
  group('CodesignException', () {
    test('toString embeds subpath + message', () {
      final e = CodesignException(
        'Foo.framework',
        'codesign exited 1: bad sig',
      );
      expect(
        e.toString(),
        'CodesignException(Foo.framework): codesign exited 1: bad sig',
      );
      expect(e, isA<Exception>());
    });
  });

  group('Codesigner.extractEntitlements', () {
    test('returns the plist on exit 0 with non-empty stdout', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 0, '<plist><dict/></plist>', ''),
      );
      final cs = Codesigner(runner: runner);

      final out = await cs.extractEntitlements(Directory.current);

      expect(out, '<plist><dict/></plist>');
      expect(
        runner.calls.single.arguments,
        containsAll(['-d', '--entitlements', ':-']),
      );
    });

    test('returns null on non-zero exit', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 1, '', 'no signature'),
      );
      final cs = Codesigner(runner: runner);

      expect(await cs.extractEntitlements(Directory.current), isNull);
    });

    test('returns null when stdout is whitespace-only', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 0, '   \n  ', ''),
      );
      final cs = Codesigner(runner: runner);

      expect(await cs.extractEntitlements(Directory.current), isNull);
    });
  });

  group('Codesigner.verify', () {
    test('returns true on exit 0', () async {
      final runner = _FakeProcessRunner.canned(ProcessResult(0, 0, '', ''));
      expect(
        await Codesigner(runner: runner).verify(Directory.current),
        isTrue,
      );
      expect(
        runner.calls.single.arguments,
        containsAll(['--verify', '--deep', '--strict', '--verbose=2']),
      );
    });

    test('returns false on non-zero exit', () async {
      final runner = _FakeProcessRunner.canned(
        ProcessResult(0, 1, '', 'invalid signature'),
      );
      expect(
        await Codesigner(runner: runner).verify(Directory.current),
        isFalse,
      );
    });
  });

  group('Codesigner.resignInsideOut', () {
    late Directory tmp;
    late Directory bundle;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lfs_codesign_');
      // Build a fake bundle layout so the leaf walker has something
      // to traverse.
      bundle = Directory('${tmp.path}/MyApp.app')..createSync();
      Directory('${bundle.path}/Contents').createSync();
      Directory('${bundle.path}/Contents/Frameworks').createSync();
      Directory(
        '${bundle.path}/Contents/Frameworks/Foo.framework',
      ).createSync();
      File('${bundle.path}/Contents/lib_a.dylib').writeAsStringSync('x');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('signs leaf-first: dylib, framework, then outer bundle', () async {
      final runner = _FakeProcessRunner.alwaysSuccess();
      final cs = Codesigner(runner: runner);

      await cs.resignInsideOut(appBundle: bundle, commonName: 'Self-Sign');

      // Expect ≥ 3 codesign calls. Order: dylib(s), framework(s), then outer.
      expect(runner.calls.length, greaterThanOrEqualTo(3));
      // Last call is the outer bundle.
      expect(runner.calls.last.arguments.last, bundle.path);

      // Every call passes the canonical baseSign trio.
      for (final c in runner.calls) {
        expect(
          c.arguments,
          containsAll([
            '--force',
            '--options',
            'runtime',
            '--sign',
            'Self-Sign',
          ]),
        );
      }
    });

    test('outer-bundle pass adds --entitlements when provided', () async {
      final runner = _FakeProcessRunner.alwaysSuccess();
      final cs = Codesigner(runner: runner);

      await cs.resignInsideOut(
        appBundle: bundle,
        commonName: 'Self-Sign',
        entitlementsPlist: '<plist><dict/></plist>',
      );

      // Outer pass = last call.
      final outer = runner.calls.last;
      expect(outer.arguments, contains('--entitlements'));
      // The arg right after `--entitlements` is the temp plist path
      // — it must point at a file the factory created on disk.
      final eIdx = outer.arguments.indexOf('--entitlements');
      final entPath = outer.arguments[eIdx + 1];
      // The factory deletes the tmp dir after the outer call, so by
      // the time we observe it the file is gone — but its parent dir
      // path has the `lfs-codesign-ent-` prefix.
      expect(entPath, contains('lfs-codesign-ent-'));
    });

    test('useSudo prepends sudo to every invocation', () async {
      final runner = _FakeProcessRunner.alwaysSuccess();
      await Codesigner(runner: runner).resignInsideOut(
        appBundle: bundle,
        commonName: 'Self-Sign',
        useSudo: true,
      );

      for (final c in runner.calls) {
        expect(c.executable, 'sudo');
        // The next positional is the codesign path.
        expect(c.arguments.first, '/usr/bin/codesign');
      }
    });

    test('throws CodesignException with the failing subpath', () async {
      // Fail on the very first sign attempt (the dylib).
      final runner = _FakeProcessRunner._failOnIndex(
        attempt: 0,
        exit: 1,
        stderr: 'bad signature',
      );
      final cs = Codesigner(runner: runner);

      await expectLater(
        () => cs.resignInsideOut(appBundle: bundle, commonName: 'Self-Sign'),
        throwsA(
          isA<CodesignException>()
              .having((e) => e.subpath, 'subpath', endsWith('lib_a.dylib'))
              .having((e) => e.message, 'message', contains('bad signature')),
        ),
      );
    });

    test('skips frameworks dir when it does not exist', () async {
      Directory(
        '${bundle.path}/Contents/Frameworks',
      ).deleteSync(recursive: true);
      final runner = _FakeProcessRunner.alwaysSuccess();
      await Codesigner(
        runner: runner,
      ).resignInsideOut(appBundle: bundle, commonName: 'Self-Sign');
      // Should still complete — dylib + outer bundle, no framework
      // pass.
      expect(runner.calls.length, greaterThanOrEqualTo(2));
    });
  });
}

class _FakeProcessRunner implements IProcessRunner {
  _FakeProcessRunner._raw(this._behaviour);

  factory _FakeProcessRunner.canned(ProcessResult result) =>
      _FakeProcessRunner._raw((_) => result);

  factory _FakeProcessRunner.alwaysSuccess() =>
      _FakeProcessRunner._raw((_) => ProcessResult(0, 0, '', ''));

  factory _FakeProcessRunner._failOnIndex({
    required int attempt,
    required int exit,
    required String stderr,
  }) => _FakeProcessRunner._raw(
    (i) => i == attempt
        ? ProcessResult(0, exit, '', stderr)
        : ProcessResult(0, 0, '', ''),
  );

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
