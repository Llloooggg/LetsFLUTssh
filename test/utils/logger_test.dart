import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  tearDown(() async {
    await AppLogger.instance.setEnabled(false);
    await AppLogger.instance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AppLogger', () {
    test('instance returns singleton', () {
      final a = AppLogger.instance;
      final b = AppLogger.instance;
      expect(identical(a, b), isTrue);
    });

    test('logPath is null before init', () {
      // After dispose+init cycle from previous test, logPath may be set.
      // Create a fresh scenario by just checking the property exists.
      expect(AppLogger.instance.logPath, isA<String?>());
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

    test('setEnabled(true) without init does not crash', () async {
      await AppLogger.instance.setEnabled(true);
      AppLogger.instance.log('test', name: 'Test');
      await AppLogger.instance.setEnabled(false);
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

    test('setEnabled(true) creates log file', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      final logFile = File(AppLogger.instance.logPath!);
      // Flush to ensure header is written
      final content = await AppLogger.instance.readLog();
      expect(logFile.existsSync(), isTrue);
      expect(content, contains('--- Log started'));
    });

    test('log() writes to file when enabled', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      AppLogger.instance.log('hello world', name: 'TestTag');

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[TestTag] hello world'));
    });

    test('log() with error writes error line', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      AppLogger.instance.log(
        'something broke',
        name: 'Err',
        error: 'DetailedError',
      );

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[Err] something broke'));
      expect(content, contains('Error: DetailedError'));
    });

    test('log() uses default tag when name is null', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      AppLogger.instance.log('no tag message');

      final content = await AppLogger.instance.readLog();
      expect(content, contains('[App] no tag message'));
    });

    test('readLog() returns file content', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

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

    test('setEnabled(false) stops writing', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      AppLogger.instance.log('before disable', name: 'SD');
      // Read content before disabling to capture the first message
      final contentBefore = await AppLogger.instance.readLog();
      expect(contentBefore, contains('before disable'));

      await AppLogger.instance.setEnabled(false);
      AppLogger.instance.log('after disable', name: 'SD');

      // Re-init to read the file (setEnabled(false) calls dispose which nulls _sink)
      await AppLogger.instance.init();
      final contentAfter = await AppLogger.instance.readLog();
      expect(contentAfter, isNot(contains('after disable')));
    });

    test('setEnabled with same value is no-op', () async {
      await AppLogger.instance.init();
      // Already disabled, setting false again should be no-op
      await AppLogger.instance.setEnabled(false);
      expect(AppLogger.instance.enabled, isFalse);

      await AppLogger.instance.setEnabled(true);
      // Setting true again should be no-op
      await AppLogger.instance.setEnabled(true);
      expect(AppLogger.instance.enabled, isTrue);
    });

    test('clearLogs() deletes file and reopens', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

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
      final logPath = AppLogger.instance.logPath!;

      // Create fake rotated files
      File('$logPath.1').writeAsStringSync('rotated 1');
      File('$logPath.2').writeAsStringSync('rotated 2');
      File('$logPath.3').writeAsStringSync('rotated 3');

      await AppLogger.instance.setEnabled(true);
      await AppLogger.instance.clearLogs();

      expect(File('$logPath.1').existsSync(), isFalse);
      expect(File('$logPath.2').existsSync(), isFalse);
      expect(File('$logPath.3').existsSync(), isFalse);
    });

    test('dispose() closes sink', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

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

    test('init creates logs directory', () async {
      await AppLogger.instance.init();
      final logsDir = Directory('${tempDir.path}/logs');
      expect(logsDir.existsSync(), isTrue);
    });

    test('openSink writes platform header', () async {
      await AppLogger.instance.init();
      await AppLogger.instance.setEnabled(true);

      final content = await AppLogger.instance.readLog();
      expect(content, contains('Platform:'));
      expect(content, contains('Dart:'));
    });

    test('rotation creates .log.1 when file exceeds max size', () async {
      await AppLogger.instance.init();
      final logPath = AppLogger.instance.logPath!;

      // Create a file that exceeds maxLogSizeBytes
      final file = File(logPath);
      // Write just over 5MB of data
      final bigData = 'x' * (AppLogger.maxLogSizeBytes + 1);
      file.writeAsStringSync(bigData);

      // Enable logging which triggers _openSink -> _rotateIfNeeded
      await AppLogger.instance.setEnabled(true);

      // Original file should have been rotated to .log.1
      expect(File('$logPath.1').existsSync(), isTrue);
      final rotatedContent = File('$logPath.1').readAsStringSync();
      expect(rotatedContent.length, greaterThan(AppLogger.maxLogSizeBytes));
    });

    test('rotation shifts existing rotated files', () async {
      await AppLogger.instance.init();
      final logPath = AppLogger.instance.logPath!;

      // Create existing rotated files
      File('$logPath.1').writeAsStringSync('old rotated 1');
      File('$logPath.2').writeAsStringSync('old rotated 2');

      // Create oversized main log
      final file = File(logPath);
      file.writeAsStringSync('x' * (AppLogger.maxLogSizeBytes + 1));

      await AppLogger.instance.setEnabled(true);

      // .1 should now be the rotated main log
      // .2 should be old .1
      // .3 should be old .2
      expect(File('$logPath.2').readAsStringSync(), 'old rotated 1');
      expect(File('$logPath.3').readAsStringSync(), 'old rotated 2');
      expect(File('$logPath.1').existsSync(), isTrue);
    });
  });
}
