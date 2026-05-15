import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:letsflutssh/core/security/kdf_params.dart';

/// Flutter test harness called before every test file.
///
/// `stderr` is replaced with a discarding sink for the test isolate.
/// `AppLogger.logCritical` mirrors to stderr by design (forensic
/// visibility on a crashing app launched from a terminal), and tests
/// that exercise it would otherwise flood `make test` output with
/// `[Crit]` / `[Crash]` lines that no assertion covers. The file-sink
/// + sanitiser contracts on `AppLogger` are pinned by `logger_test.dart`
/// without depending on the stderr channel. `IOOverrides.global` is
/// chosen over `runZoned` so the override propagates across every
/// nested zone the flutter_test runner spins up per test.
///
/// KDF cost for tests that exercise the real `MasterPasswordManager`
/// is passed per-construction via the `kdfParams:` constructor
/// argument (see `master_password_test.dart`). Production constructs
/// without the argument and lands on `KdfParams.productionDefaults`,
/// the Dart mirror of `lfs_core::security::master_password::
/// KdfParams::defaults` populated at startup by
/// `KdfParams.bootstrapFromRust()`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  IOOverrides.global = _SilentStderrIOOverrides();
  // Pre-seed [KdfParams.productionDefaults] with cheap test-time
  // values so widget tests that never load FRB don't trip the
  // `late` field on `MasterPasswordManager()` construction. Tests
  // that load FRB call `KdfParams.bootstrapFromRust()` in their
  // own `setUpAll` and overwrite this with the canonical Rust
  // profile.
  KdfParams.bootstrapForTests();
  await testMain();
}

final class _SilentStderrIOOverrides extends IOOverrides {
  static final _DiscardingStdout _sink = _DiscardingStdout();
  @override
  Stdout get stderr => _sink;
}

class _DiscardingStdout implements Stdout {
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<void> close() async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> get done => Future<void>.value();
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
  @override
  bool get hasTerminal => false;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => this;
  @override
  int get terminalColumns =>
      throw const StdoutException('no terminal in test stderr');
  @override
  int get terminalLines =>
      throw const StdoutException('no terminal in test stderr');
  @override
  String get lineTerminator => '\n';
  @override
  set lineTerminator(String value) {}
}
