import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/logger.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('logger_test_');
  });

  tearDown(() async {
    await AppLogger.instance.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('AppLogger', () {
    test('instance returns singleton', () {
      final a = AppLogger.instance;
      final b = AppLogger.instance;
      expect(identical(a, b), isTrue);
    });

    test('logPath is null before init', () {
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
      AppLogger.instance.log('error msg', name: 'Test', error: Exception('boom'));
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
  });
}
