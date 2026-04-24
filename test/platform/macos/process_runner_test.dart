@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';

/// [SystemProcessRunner] lives in `platform/macos/` but only thin-
/// wraps `Process.run` / `Process.start` — the behaviour is POSIX-
/// generic so the test runs on Linux CI too. Skipped on Windows
/// because the stdin / argv shapes below assume Unix `echo` and
/// `cat`; a Windows equivalent would need `cmd /c` scaffolding
/// that is not worth carrying for a test that the real users of
/// `IProcessRunner` (the macOS-only self-sign flow) will exercise
/// on macOS anyway.
void main() {
  const runner = SystemProcessRunner();

  test('run without stdin surfaces stdout + exit=0', () async {
    final r = await runner.run('/bin/echo', ['hello']);
    expect(r.exitCode, 0);
    expect((r.stdout as String).trim(), 'hello');
  });

  test('run with stdin pipes bytes through', () async {
    final r = await runner.run('/bin/cat', [], stdin: utf8.encode('piped'));
    expect(r.exitCode, 0);
    expect(r.stdout, 'piped');
  });

  test('non-zero exit propagates + stderr captured', () async {
    // `/bin/false` exits 1 with no output. `/bin/sh -c "..."` gives
    // us a portable way to emit stderr + an explicit exit code.
    final r = await runner.run('/bin/sh', ['-c', 'echo problem >&2; exit 42']);
    expect(r.exitCode, 42);
    expect((r.stderr as String).trim(), 'problem');
  });

  test('workingDirectory + env threaded through without stdin', () async {
    final tmp = Directory.systemTemp.createTempSync('runner_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final r = await runner.run(
      '/bin/sh',
      ['-c', 'pwd; echo "lfs_test=\$LFS_TEST_MARKER"'],
      workingDirectory: tmp.path,
      environment: {'LFS_TEST_MARKER': 'x'},
    );
    expect(r.exitCode, 0);
    // Some systems realpath the tmp dir (macOS `/var` → `/private/var`);
    // accept either so the test is portable.
    expect(r.stdout, contains('lfs_test=x'));
  });
}
