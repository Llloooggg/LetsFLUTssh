import 'dart:convert';
import 'dart:io';

/// Minimal abstraction over `Process.run` — the macOS code-signing
/// flow spawns `openssl`, `security`, `codesign`, `hdiutil`, and
/// `rsync`, and every test would otherwise need a real binary in
/// `PATH`. Having a typed process runner lets the tests inject a
/// fake and assert on argv / cwd / stdin composition instead.
abstract class IProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  });
}

/// Real `Process.run`-backed implementation used in production.
class SystemProcessRunner implements IProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  }) async {
    // `Process.run` doesn't accept a stdin blob directly — use
    // `Process.start` when the caller needs to feed bytes in.
    if (stdin == null) {
      return Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
      );
    }
    final proc = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    );
    proc.stdin.add(stdin);
    await proc.stdin.close();
    final stdoutBytes = <int>[];
    final stderrBytes = <int>[];
    await Future.wait([
      proc.stdout.forEach(stdoutBytes.addAll),
      proc.stderr.forEach(stderrBytes.addAll),
    ]);
    final exitCode = await proc.exitCode;
    return ProcessResult(
      proc.pid,
      exitCode,
      utf8.decode(stdoutBytes, allowMalformed: true),
      utf8.decode(stderrBytes, allowMalformed: true),
    );
  }
}
