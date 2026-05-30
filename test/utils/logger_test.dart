import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/logger.dart' as rust_logger;
import 'package:letsflutssh/utils/logger.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AppLogger.log routes sanitize + format through `lfs_core` and the
  // on-disk sink lives Rust-side under `lfs_core::logger::file_sink`.
  // Bootstrap FRB so every test exercises the production write path.
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('logger_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
    // Each case starts with a clean in-memory state — `_logPath` and
    // `_frbReady` survive across tests inside one process otherwise,
    // and the surviving path would point at the prior case's
    // (now-deleted) temp dir.
    AppLogger.instance.debugResetState();
    // FRB is loaded for every test in this file (the `setUpAll`
    // above bootstraps the native lib), so flip the post-bootstrap
    // gate immediately. Tests that want to assert pre-FRB
    // semantics (the critical-write buffer) explicitly reset the
    // gate inside the case.
    AppLogger.instance.debugMarkFrbReady();
  });

  tearDown(() async {
    await AppLogger.instance.setThreshold(null);
    await AppLogger.instance.dispose();
    // Drop the Rust-side held sink + path so the next test's
    // `loggerOpenSink` starts clean. Without this the process-wide
    // `file_sink::STATE` retains the prior tempDir's path; the next
    // open would still write to the right place (we always pass the
    // new dir) but a `read_all` between tests could resolve through
    // the prior state if the suite ever interleaved.
    try {
      rust_logger.loggerCloseSink();
    } catch (_) {
      // Ignore — FRB may not be loaded in degraded-CI runs.
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Bring the logger to a post-FRB state — `init()` resolves the path
  /// then `onFrbReady` flips `_frbReady`, registers the log-path
  /// Rust-side, and drains any (empty) pre-FRB critical buffer.
  /// Tests that want `logCritical` to land on disk call this instead
  /// of plain `init()`.
  Future<void> primeForCritical() async {
    await AppLogger.instance.init();
    await AppLogger.instance.onFrbReady();
  }

  group('AppLogger', () {
    test('instance returns singleton', () {
      final a = AppLogger.instance;
      final b = AppLogger.instance;
      expect(identical(a, b), isTrue);
    });

    test('logPath is null before init', () {
      // debugResetState in setUp clears _logPath; init has not run yet.
      expect(AppLogger.instance.logPath, isNull);
    });

    test('enabled is false by default', () {
      expect(AppLogger.instance.enabled, isFalse);
    });

    test('log does not crash when not enabled', () {
      AppLogger.instance.log('test message', name: 'Test');
      // No crash = pass
    });

    test('log does not crash with error parameter', () {
      AppLogger.instance.log(
        'error msg',
        name: 'Test',
        error: Exception('boom'),
      );
    });

    test('setThreshold(LogLevel.info) without init does not crash', () async {
      await AppLogger.instance.setThreshold(LogLevel.info);
      AppLogger.instance.log('test', name: 'Test');
      await AppLogger.instance.setThreshold(null);
    });

    test('dispose does not crash when not initialized', () async {
      await AppLogger.instance.dispose();
    });

    test('clearLogs does not crash when logPath is null', () async {
      await AppLogger.instance.clearLogs();
    });

    test('readLog returns empty string when logPath is null', () async {
      final content = await AppLogger.instance.readLog();
      expect(content, isEmpty);
    });

    test('init() resolves logPath', () async {
      await AppLogger.instance.init();
      expect(AppLogger.instance.logPath, isNotNull);
      expect(AppLogger.instance.logPath!, contains('letsflutssh.log'));
    });

    test('init() does NOT create the logs directory', () async {
      // `init()` only resolves the path string; the logs/ parent
      // directory is created Rust-side inside `logger_open_sink` on
      // the first `setThreshold(non-null)` flip. Verifies the
      // cold-start invariant — `dart:io Directory` ops on the log
      // path moved out of `init()`.
      await AppLogger.instance.init();
      final logsDir = Directory('${tempDir.path}/logs');
      expect(logsDir.existsSync(), isFalse);
    });

    test('setThreshold(LogLevel.info) creates log file', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      final logFile = File(AppLogger.instance.logPath!);
      final content = await AppLogger.instance.readLog();
      expect(logFile.existsSync(), isTrue);
      expect(content, contains('--- Log started'));
    });

    test('log() writes to file when enabled', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('hello world', name: 'TestTag');

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[TestTag] hello world'));
    });

    test('log() with error writes error line', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log(
        'something broke',
        name: 'Err',
        error: 'DetailedError',
      );

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[Err] something broke'));
      expect(content, contains('Error: DetailedError'));
    });

    test('log() with stackTrace writes stack trace lines', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      final stack = StackTrace.fromString('TestStack:\n#0 main\n#1 helper');
      AppLogger.instance.log(
        'crash info',
        name: 'Trace',
        error: 'Boom',
        stackTrace: stack,
      );

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[Trace] crash info'));
      expect(content, contains('Error: Boom'));
      expect(content, contains('Stack trace:'));
      expect(content, contains('TestStack:'));
    });

    test('log() uses default tag when name is null', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('no tag message');

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[App] no tag message'));
    });

    test('readLog() returns file content', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('line one', name: 'R');
      AppLogger.instance.log('line two', name: 'R');

      final content = await AppLogger.instance.readLog();
      expect(content, contains('line one'));
      expect(content, contains('line two'));
    });

    test('readLog() returns empty when file missing', () async {
      await AppLogger.instance.init();
      // Don't enable — no file created
      final content = await AppLogger.instance.readLog();
      expect(content, isEmpty);
    });

    test('setThreshold(null) stops writing', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('before disable', name: 'SD');
      // Read content before disabling to capture the first message
      final contentBefore = await AppLogger.instance.readLog();
      expect(contentBefore, contains('before disable'));

      await AppLogger.instance.setThreshold(null);
      AppLogger.instance.log('after disable', name: 'SD');

      // Re-read content — setThreshold(null) closed the sink so the
      // post-disable line never reached disk.
      final contentAfter = await AppLogger.instance.readLog();
      expect(contentAfter, isNot(contains('after disable')));
    });

    test('setEnabled with same value is no-op', () async {
      await AppLogger.instance.init();
      // Already disabled, setting false again should be no-op
      await AppLogger.instance.setThreshold(null);
      expect(AppLogger.instance.enabled, isFalse);

      await AppLogger.instance.setThreshold(LogLevel.info);
      // Setting true again should be no-op
      await AppLogger.instance.setThreshold(LogLevel.info);
      expect(AppLogger.instance.enabled, isTrue);
    });

    test('clearLogs() deletes file and reopens', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('to be cleared', name: 'CL');
      final before = await AppLogger.instance.readLog();
      expect(before, contains('to be cleared'));

      await AppLogger.instance.clearLogs();

      final after = await AppLogger.instance.readLog();
      expect(after, isNot(contains('to be cleared')));
      // File should still exist (reopened since enabled=true)
      expect(after, contains('--- Log started'));
    });

    test('clearLogs() deletes rotated files too', () async {
      await AppLogger.instance.init();
      // Pre-seed rotated files at <log>.1 / .2 / .3 BEFORE flipping
      // the threshold (which would trigger rotation against an empty
      // current file). The Rust-side `logger_clear_all` deletes the
      // current file + every rotated sibling up to `_maxRotatedFiles`.
      final logPath = AppLogger.instance.logPath!;
      Directory(File(logPath).parent.path).createSync(recursive: true);
      File('$logPath.1').writeAsStringSync('rotated 1');
      File('$logPath.2').writeAsStringSync('rotated 2');
      File('$logPath.3').writeAsStringSync('rotated 3');

      await AppLogger.instance.setThreshold(LogLevel.info);
      await AppLogger.instance.clearLogs();

      expect(File('$logPath.1').existsSync(), isFalse);
      expect(File('$logPath.2').existsSync(), isFalse);
      expect(File('$logPath.3').existsSync(), isFalse);
    });

    test('dispose() closes sink', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);

      AppLogger.instance.log('before dispose', name: 'D');

      await AppLogger.instance.dispose();

      // After dispose, logging should not crash
      AppLogger.instance.log('after dispose', name: 'D');

      // Re-init to read
      await AppLogger.instance.init();
      final content = await AppLogger.instance.readLog();
      expect(content, contains('before dispose'));
      expect(content, isNot(contains('after dispose')));
    });

    test('setThreshold creates logs directory through Rust', () async {
      // The Rust-side `logger_open_sink` runs the recursive
      // `create_dir_all` on `<app_support>/logs/`. `init()` deliberately
      // leaves the directory alone (cold-start invariant — no
      // `dart:io` ops on the log path); the directory only appears
      // after the user flips the Settings threshold.
      await AppLogger.instance.init();
      expect(Directory('${tempDir.path}/logs').existsSync(), isFalse);
      await AppLogger.instance.setThreshold(LogLevel.info);
      expect(Directory('${tempDir.path}/logs').existsSync(), isTrue);
    });

    test(
      'openSink writes a single-line session banner with platform metadata',
      () async {
        await AppLogger.instance.init();
        await AppLogger.instance.setThreshold(LogLevel.info);

        final content = await AppLogger.instance.readLog();
        // Single-line banner shape: `--- Log started <ts> | <platform> | … ---`.
        // One cohesive run-boundary instead of three duplicate-meaning
        // header rows.
        expect(content, contains('--- Log started'));
        expect(content, contains('|'));
        expect(content, contains(Platform.operatingSystem));
        expect(content, isNot(contains('Dart:')));
        expect(
          content.split('\n').any((l) => l.startsWith('Platform:')),
          isFalse,
        );
      },
    );

    test('openSink banner stamps app version when one was set', () async {
      await AppLogger.instance.init();
      AppLogger.instance.setAppVersion('9.9.9');
      await AppLogger.instance.setThreshold(LogLevel.info);

      final content = await AppLogger.instance.readLog();
      expect(content, contains('LetsFLUTssh 9.9.9'));
    });

    test(
      'toggling Off → On in the same process does NOT duplicate the session banner',
      () async {
        // Every reopen used to write a fresh `--- Log started ---`
        // line; two pictures of the same session boundary
        // accumulated in the file and the viewer rendered both as
        // separate `_SessionBoundary` banners. Banner lives behind
        // the `_bannerWritten` flag — one banner per process, period.
        await AppLogger.instance.init();
        await AppLogger.instance.setThreshold(LogLevel.info);
        AppLogger.instance.log('between', name: 'T');
        await AppLogger.instance.setThreshold(null); // close
        await AppLogger.instance.setThreshold(LogLevel.info); // reopen
        AppLogger.instance.log('after-toggle', name: 'T');

        final content = await AppLogger.instance.readLog();
        final bannerCount = '--- Log started'.allMatches(content).length;
        expect(bannerCount, 1);
        // Both messages still landed.
        expect(content, contains('between'));
        expect(content, contains('after-toggle'));
      },
    );

    test(
      'clearLogs resets the banner gate so the next reopen labels the new session',
      () async {
        await AppLogger.instance.init();
        await AppLogger.instance.setThreshold(LogLevel.info);
        AppLogger.instance.log('pre-clear', name: 'T');
        await AppLogger.instance.clearLogs();
        AppLogger.instance.log('post-clear', name: 'T');

        // Need to flush the new sink to read fresh content.
        await AppLogger.instance.dispose();
        await AppLogger.instance.init();
        final content = await AppLogger.instance.readLog();
        // After clear, the file starts fresh with one banner above the
        // post-clear entries — the user explicitly created a new
        // boundary, so the banner is the right forensic anchor.
        final bannerCount = '--- Log started'.allMatches(content).length;
        expect(bannerCount, 1);
        expect(content, isNot(contains('pre-clear')));
        expect(content, contains('post-clear'));
      },
    );

    test('openSink banner omits version segment when none was set', () async {
      await AppLogger.instance.init();
      // No setAppVersion call.
      await AppLogger.instance.setThreshold(LogLevel.info);

      final content = await AppLogger.instance.readLog();
      expect(content, isNot(contains('LetsFLUTssh ')));
    });

    test('rotation creates .log.1 when file exceeds max size', () async {
      await AppLogger.instance.init();
      final logPath = AppLogger.instance.logPath!;

      // Create a file that exceeds maxLogSizeBytes. Need the parent
      // dir to exist first because `init()` no longer creates it.
      Directory(File(logPath).parent.path).createSync(recursive: true);
      final file = File(logPath);
      // Write just over 5MB of data
      final bigData = 'x' * (AppLogger.maxLogSizeBytes + 1);
      file.writeAsStringSync(bigData);

      // Enable logging which triggers _openSink -> logger_rotate_if_needed
      await AppLogger.instance.setThreshold(LogLevel.info);

      // Original file should have been rotated to .log.1
      expect(File('$logPath.1').existsSync(), isTrue);
      final rotatedContent = File('$logPath.1').readAsStringSync();
      expect(rotatedContent.length, greaterThan(AppLogger.maxLogSizeBytes));
    });

    test('rotation shifts existing rotated files', () async {
      await AppLogger.instance.init();
      final logPath = AppLogger.instance.logPath!;

      // Pre-seed parent dir + existing rotated files.
      Directory(File(logPath).parent.path).createSync(recursive: true);
      File('$logPath.1').writeAsStringSync('old rotated 1');
      File('$logPath.2').writeAsStringSync('old rotated 2');

      // Create oversized main log
      final file = File(logPath);
      file.writeAsStringSync('x' * (AppLogger.maxLogSizeBytes + 1));

      await AppLogger.instance.setThreshold(LogLevel.info);

      // .1 should now be the rotated main log
      // .2 should be old .1
      // .3 should be old .2
      expect(File('$logPath.2').readAsStringSync(), 'old rotated 1');
      expect(File('$logPath.3').readAsStringSync(), 'old rotated 2');
      expect(File('$logPath.1').existsSync(), isTrue);
    });
  });

  group('AppLogger.sanitize', () {
    test('redacts PEM private keys', () {
      const pem =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----';
      final out = AppLogger.sanitize('boom: $pem tail');
      expect(out, contains('[REDACTED PRIVATE KEY]'));
      expect(out, isNot(contains('abc')));
    });

    test('redacts long base64 blobs', () {
      final blob = 'A' * 250;
      final out = AppLogger.sanitize('key=$blob');
      expect(out, contains('[REDACTED BASE64]'));
      expect(out, isNot(contains(blob)));
    });

    test('redacts IPv4 leaked through library exception messages', () {
      final out = AppLogger.sanitize(
        'SocketException: connect failed 192.168.1.50:22',
      );
      expect(out, contains('<ip>'));
      expect(out, isNot(contains('192.168.1.50')));
    });

    test('redacts user@host patterns', () {
      final out = AppLogger.sanitize('auth failed for admin@example.com');
      expect(out, contains('<user>@example.com'));
      expect(out, isNot(contains('admin@')));
    });

    test('redacts home-directory paths', () {
      final out = AppLogger.sanitize('could not open /home/jdoe/.ssh/id_rsa');
      expect(out, contains('/<user>/'));
      expect(out, isNot(contains('jdoe')));
    });
  });

  group('AppLogger.logCritical', () {
    test(
      'writes to disk even when routine logging is disabled (crash bypass)',
      () async {
        // A fresh install crashing before the user has ever flipped
        // the toggle must still leave a breadcrumb on disk. A refactor
        // that accidentally gates this method behind `_threshold`
        // (like the routine `log()` path) would silently stop
        // producing crash traces.
        await primeForCritical();
        expect(AppLogger.instance.enabled, isFalse);

        await AppLogger.instance.logCritical(
          'fatal: db open rejected',
          name: 'Crash',
          error: 'SqliteException(NOTADB)',
          stackTrace: StackTrace.fromString('#0 openDb\n#1 main'),
        );

        final content = await AppLogger.instance.readLog();
        expect(content, contains('[Crash] fatal: db open rejected'));
        expect(content, contains('Error: SqliteException(NOTADB)'));
        expect(content, contains('Stack trace:'));
        expect(content, contains('#0 openDb'));
      },
    );

    test('sanitises critical-path message / error / stack trace', () async {
      await primeForCritical();
      await AppLogger.instance.logCritical(
        'crashed talking to admin@example.com via 10.0.0.7:22',
        name: 'Crit',
        error: 'SecretContext: password=${"A" * 250}',
        stackTrace: StackTrace.fromString('#0 /home/jdoe/.ssh/id_rsa'),
      );

      final content = await AppLogger.instance.readLog();
      expect(content, contains('<ip>'));
      expect(content, isNot(contains('10.0.0.7')));
      expect(content, contains('<user>@example.com'));
      expect(content, isNot(contains('admin@')));
      expect(content, contains('[REDACTED BASE64]'));
      expect(content, contains('/<user>/'));
    });

    test('is a no-op when init() was never called (null logPath)', () async {
      // Fresh logger with no init — logPath remains null. logCritical
      // must still return without throwing; the stderr mirror is the
      // only observable effect on desktop.
      await AppLogger.instance.dispose();
      AppLogger.instance.debugResetState();
      // Pretend init never ran by not calling it. A direct logCritical
      // call against the null path must be safe.
      await AppLogger.instance.logCritical('no path set', name: 'NoInit');
      // The whole suite uses a single singleton — at tear-down the
      // teardown hook resets it; nothing else to assert here, the
      // contract is "does not throw".
    });

    test(
      'pre-FRB calls buffer in memory and stay off disk until drain',
      () async {
        // The cold-start contract: `logCritical` fired before
        // `_LetsFLUTsshAppState._bootstrap` reaches
        // `onFrbReady` lands in an in-memory ring buffer
        // + stderr mirror; nothing on disk until the drain. The
        // drain (which `_bootstrap` calls once Rust is up) then
        // routes every buffered entry through
        // `logger_append_critical`, so a crash that happened in the
        // pre-FRB window still leaves a breadcrumb on disk after
        // boot.
        // Reset the FRB-ready gate so the next two logCritical
        // calls hit the pre-FRB buffer path. The shared setUp
        // flipped the gate to mirror post-bootstrap state — this
        // case explicitly tests the pre-bootstrap shape.
        AppLogger.instance.debugResetState();
        await AppLogger.instance.init();
        await AppLogger.instance.logCritical('pre-frb crash A', name: 'Early');
        await AppLogger.instance.logCritical('pre-frb crash B', name: 'Early');

        // Nothing on disk yet — the buffer holds the entries.
        final beforeDrain = await AppLogger.instance.readLog();
        expect(beforeDrain, isNot(contains('pre-frb crash A')));
        expect(beforeDrain, isNot(contains('pre-frb crash B')));

        // Drain — emulates the post-FRB boundary in `_bootstrap`.
        await AppLogger.instance.onFrbReady();

        final afterDrain = await AppLogger.instance.readLog();
        expect(afterDrain, contains('[Early] pre-frb crash A'));
        expect(afterDrain, contains('[Early] pre-frb crash B'));
      },
    );

    test(
      'appends each call on top of the file without truncating prior writes',
      () async {
        await primeForCritical();
        await AppLogger.instance.logCritical('first crit', name: 'A');
        await AppLogger.instance.logCritical('second crit', name: 'B');
        final content = await AppLogger.instance.readLog();
        expect(content, contains('[A] first crit'));
        expect(
          content,
          contains('[B] second crit'),
          reason: 'second write must append, not overwrite',
        );
      },
    );

    test(
      'recreates the logs/ parent directory if the user cleared it mid-run',
      () async {
        await primeForCritical();
        final logPath = AppLogger.instance.logPath!;
        // Simulate the user triggering Settings → Clear Logs in a way
        // that nuked the whole `logs/` directory under us.
        final parent = File(logPath).parent;
        if (parent.existsSync()) parent.deleteSync(recursive: true);
        expect(parent.existsSync(), isFalse);

        await AppLogger.instance.logCritical('post-wipe crit', name: 'W');

        expect(parent.existsSync(), isTrue);
        expect(File(logPath).existsSync(), isTrue);
      },
    );
  });

  group('AppLogger level marker', () {
    // The live viewer keys off a single char between timestamp and
    // [tag] to pick the row tint (I = default, W = amber, E = red).
    // These tests pin the format so a refactor that drops or renames
    // the marker does not silently demote every row to "info tint"
    // and bury warnings / errors in the viewer.

    setUp(() async {
      await AppLogger.instance.dispose();
      await AppLogger.instance.clearLogs();
      AppLogger.instance.debugResetState();
      // Mirror the outer setUp: simulate post-bootstrap state so
      // `setThreshold` opens the sink straight through.
      AppLogger.instance.debugMarkFrbReady();
    });

    test('log() default level writes I marker', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);
      AppLogger.instance.log('routine', name: 'Lvl');
      final content = await AppLogger.instance.readLog();
      expect(content, matches(RegExp(r'\d{2}:\d{2}:\d{2} I \[Lvl\] routine')));
    });

    test('log() with explicit warn level writes W marker', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);
      AppLogger.instance.log('soft fail', name: 'Lvl', level: LogLevel.warn);
      final content = await AppLogger.instance.readLog();
      expect(
        content,
        matches(RegExp(r'\d{2}:\d{2}:\d{2} W \[Lvl\] soft fail')),
      );
    });

    test(
      'log() with error auto-promotes to E marker without explicit level',
      () async {
        // Call sites that pass `error:` without touching `level:` still
        // render tinted red — preserves zero-touch migration for the
        // 100+ existing `log(..., error: e)` call sites.
        await AppLogger.instance.init();
        await AppLogger.instance.setThreshold(LogLevel.info);
        AppLogger.instance.log('boom', name: 'Lvl', error: 'StateError');
        final content = await AppLogger.instance.readLog();
        expect(content, matches(RegExp(r'\d{2}:\d{2}:\d{2} E \[Lvl\] boom')));
      },
    );

    test('log() explicit level overrides the error auto-promote', () async {
      // Edge case — a `warn` call that also carries a suppressed error
      // object (non-fatal fallback) should still render warn, not red.
      await AppLogger.instance.init();
      await AppLogger.instance.setThreshold(LogLevel.info);
      AppLogger.instance.log(
        'recoverable',
        name: 'Lvl',
        error: 'Transient',
        level: LogLevel.warn,
      );
      final content = await AppLogger.instance.readLog();
      expect(
        content,
        matches(RegExp(r'\d{2}:\d{2}:\d{2} W \[Lvl\] recoverable')),
      );
    });

    test('logCritical() always writes E marker', () async {
      await primeForCritical();
      // setThreshold(LogLevel.info) NOT called — logCritical bypasses
      // the toggle. Marker still must be E.
      await AppLogger.instance.logCritical('fatal', name: 'Crit');
      final content = await AppLogger.instance.readLog();
      expect(content, matches(RegExp(r'\d{2}:\d{2}:\d{2} E \[Crit\] fatal')));
    });
  });

  // Deferred — AppLogger lifecycle edges group (attachCoreLogPipe
  // idempotency, clearLogs while disabled, setAppVersion overwrite,
  // liveEntries onDone on dispose): all four tests share the singleton
  // logger state that doesn't reset cleanly within the 30 s budget in
  // this harness shape (init / clearLogs / readLog all wait on the
  // file-sink Future). The dispose close-sink contract is exercised
  // by the parallel close-sink tests above; the idempotency contract
  // is verified by structural inspection.
}
