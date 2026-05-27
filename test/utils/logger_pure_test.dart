import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/logger.dart';

/// Pure-Dart slice of `AppLogger` — the level serialisation helpers,
/// the build-time override getter, and the threshold / level-routing
/// logic in `log()`. None of these touch FRB: `logLevelToJson` /
/// `logLevelFromJson` are plain switch expressions, and `log()` is
/// driven against a fake [LoggerBackend] injected through the
/// `debugSetBackend` DI seam so the routing decisions are observable
/// without the Rust file sink. The log path resolves through
/// `path_provider` (a Flutter plugin, not FRB), mocked here. The
/// file-IO behaviours that genuinely need the Rust backend (banner
/// content on disk, rotation, clear, critical drain) stay in
/// `logger_test.dart`.
class _FakeBackend implements LoggerBackend {
  final List<String> lines = <String>[];
  int openCount = 0;
  int closeCount = 0;
  int flushCount = 0;

  @override
  Future<String> openSink(String appSupportDir) async {
    openCount++;
    return appSupportDir;
  }

  @override
  void appendLine(String line) => lines.add(line);

  @override
  void appendCritical(String line, List<String> continuations) {}

  @override
  void flushSink() => flushCount++;

  @override
  Future<String> readAll() async => lines.join('\n');

  @override
  Future<void> rotateIfNeeded(int maxBytes, int maxRotated) async {}

  @override
  Future<void> clearAll(int maxRotated) async {}

  @override
  void closeSink() => closeCount++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('logLevelToJson', () {
    test('maps each level to its stable wire string', () {
      // The JSON token must stay decoupled from the enum's declaration
      // order so reordering `LogLevel` never silently rewrites a
      // persisted `config.json` value.
      expect(logLevelToJson(LogLevel.info), 'info');
      expect(logLevelToJson(LogLevel.warn), 'warn');
      expect(logLevelToJson(LogLevel.error), 'error');
    });

    test('maps null (logging off) to null', () {
      expect(logLevelToJson(null), isNull);
    });
  });

  group('logLevelFromJson', () {
    test('parses each recognised wire string back to its level', () {
      expect(logLevelFromJson('info'), LogLevel.info);
      expect(logLevelFromJson('warn'), LogLevel.warn);
      expect(logLevelFromJson('error'), LogLevel.error);
    });

    test('maps null to null (logging off)', () {
      expect(logLevelFromJson(null), isNull);
    });

    test('maps an unrecognised token to null rather than throwing', () {
      // A hand-edited or future-version config must degrade to
      // "logging off" instead of crashing the config load.
      expect(logLevelFromJson('verbose'), isNull);
      expect(logLevelFromJson(''), isNull);
      expect(logLevelFromJson('INFO'), isNull);
    });

    test('round-trips every level through toJson + fromJson', () {
      for (final level in LogLevel.values) {
        expect(logLevelFromJson(logLevelToJson(level)), level);
      }
    });
  });

  group('buildTimeLogLevelOverride', () {
    test('returns null when no --dart-define was supplied', () {
      // The unit-test process is launched without
      // LETSFLUTSSH_LOG_LEVEL, so the compile-time constant is empty
      // and the getter must yield null — production release builds
      // rely on this to keep logging off unless the user opts in.
      expect(buildTimeLogLevelOverride, isNull);
    });
  });

  group('AppLogger.log routing (fake backend, no Rust file sink)', () {
    late _FakeBackend backend;
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('logger_pure_');
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
      final logger = AppLogger.instance;
      logger.debugResetState();
      logger.debugSetBackend(backend = _FakeBackend());
      // Mark FRB ready so `_openSink` does not defer (the gate only
      // guards the Rust hop; the fake backend stands in for it).
      logger.debugMarkFrbReady();
      await logger.init(); // resolves the log path via mocked plugin
    });

    tearDown(() async {
      await AppLogger.instance.setThreshold(null);
      AppLogger.instance.debugResetBackend();
      AppLogger.instance.debugResetState();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// Append-only view of message lines (drops the banner the first
    /// `_openSink` writes).
    List<String> messageLines() =>
        backend.lines.where((l) => l.contains('[')).toList();

    test('drops lines below the active threshold', () async {
      // Spec: `log()` admits a line only when its resolved level index
      // is >= the threshold index. At threshold=warn an info line must
      // never reach the backend.
      await AppLogger.instance.setThreshold(LogLevel.warn);
      backend.lines.clear();

      AppLogger.instance.log('routine info', name: 'T', level: LogLevel.info);
      expect(
        messageLines().any((l) => l.contains('routine info')),
        isFalse,
        reason: 'info is below the warn threshold and must be dropped',
      );
    });

    test('admits lines at or above the active threshold', () async {
      await AppLogger.instance.setThreshold(LogLevel.warn);
      backend.lines.clear();

      AppLogger.instance.log('a warning', name: 'T', level: LogLevel.warn);
      AppLogger.instance.log('an error', name: 'T', level: LogLevel.error);
      expect(messageLines().any((l) => l.contains('a warning')), isTrue);
      expect(messageLines().any((l) => l.contains('an error')), isTrue);
    });

    test('is a no-op while the threshold is null (logging off)', () {
      // No setThreshold call — `_threshold` stays null, so even with a
      // ready backend and resolved path nothing is written.
      AppLogger.instance.log('should not write', name: 'T');
      expect(backend.lines, isEmpty);
    });

    test(
      'auto-promotes an error-bearing line with no explicit level',
      () async {
        // A `log(..., error: e)` call without `level:` resolves to
        // error — keeps the existing error call sites tinted red
        // without a rewrite. At threshold=error such a line still
        // lands, with its error continuation.
        await AppLogger.instance.setThreshold(LogLevel.error);
        backend.lines.clear();

        AppLogger.instance.log('boom', name: 'T', error: 'StateError');
        expect(
          messageLines().any((l) => RegExp(r'E \[T\] boom').hasMatch(l)),
          isTrue,
        );
        expect(
          backend.lines.any((l) => l.contains('Error: StateError')),
          isTrue,
        );
      },
    );

    test('an explicit level overrides the error auto-promotion', () async {
      // A recoverable fallback that still carries an exception object
      // should render at its explicit warn level, not be forced to
      // error.
      await AppLogger.instance.setThreshold(LogLevel.info);
      backend.lines.clear();

      AppLogger.instance.log(
        'recoverable',
        name: 'T',
        error: 'Transient',
        level: LogLevel.warn,
      );
      expect(
        messageLines().any((l) => RegExp(r'W \[T\] recoverable').hasMatch(l)),
        isTrue,
      );
    });

    test('an info line with no error resolves to the info marker', () async {
      await AppLogger.instance.setThreshold(LogLevel.info);
      backend.lines.clear();

      AppLogger.instance.log('plain', name: 'T');
      expect(
        messageLines().any((l) => RegExp(r'I \[T\] plain').hasMatch(l)),
        isTrue,
      );
    });

    test('defaults the tag to App when name is omitted', () async {
      await AppLogger.instance.setThreshold(LogLevel.info);
      backend.lines.clear();

      AppLogger.instance.log('untagged');
      expect(messageLines().any((l) => l.contains('[App] untagged')), isTrue);
    });

    test('sanitises the message before it reaches the backend', () async {
      // `log()` runs every message through `AppLogger.sanitize` (pure
      // Dart regexes). A user@host in the message must be redacted on
      // the line handed to the backend.
      await AppLogger.instance.setThreshold(LogLevel.info);
      backend.lines.clear();

      AppLogger.instance.log('auth failed for admin@example.com', name: 'T');
      final line = messageLines().firstWhere((l) => l.contains('[T]'));
      expect(line, contains('<user>@example.com'));
      expect(line, isNot(contains('admin@')));
    });

    test('writes a stack-trace continuation when one is supplied', () async {
      await AppLogger.instance.setThreshold(LogLevel.info);
      backend.lines.clear();

      AppLogger.instance.log(
        'crash',
        name: 'T',
        error: 'Boom',
        stackTrace: StackTrace.fromString('#0 main\n#1 helper'),
      );
      expect(backend.lines.any((l) => l.contains('Stack trace:')), isTrue);
      expect(backend.lines.any((l) => l.contains('#0 main')), isTrue);
    });

    test('threshold getter and enabled flag track setThreshold', () async {
      expect(AppLogger.instance.enabled, isFalse);
      expect(AppLogger.instance.threshold, isNull);
      await AppLogger.instance.setThreshold(LogLevel.warn);
      expect(AppLogger.instance.enabled, isTrue);
      expect(AppLogger.instance.threshold, LogLevel.warn);
    });
  });
}
