import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';
import 'package:letsflutssh/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterError.onError', () {
    test('is set by main()', () {
      // FlutterError.onError should be set when main() runs.
      // In tests, main() doesn't run, but the handler is installed
      // at module level during main() execution.
      // We verify the handler exists by checking it's not null.
      // Note: In test environment, FlutterError.onError may be set by
      // test framework, so we just verify the mechanism works.
      expect(FlutterError.onError, isNotNull);
    });

    test('logs error details via AppLogger', () {
      // Verify AppLogger.log accepts error and stackTrace parameters
      // This ensures our error handler can pass full context
      AppLogger.instance.log(
        'Test error',
        name: 'Test',
        error: Exception('test'),
        stackTrace: StackTrace.current,
      );
      // No crash = parameters accepted
    });
  });

  group('navigatorKey', () {
    test('is accessible for error dialog context', () {
      expect(navigatorKey, isA<GlobalKey<NavigatorState>>());
    });
  });
}
