import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/platform.dart';

void main() {
  group('platform utilities', () {
    test('homeDirectory returns non-empty on desktop', () {
      // Tests run on Linux — HOME should be set
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(homeDirectory, isNotEmpty);
      }
    });

    test('homeDirectory uses HOME env on Linux', () {
      if (Platform.isLinux) {
        expect(homeDirectory, equals(Platform.environment['HOME']));
      }
    });

    test('isMobilePlatform is false in test environment', () {
      // Tests run on desktop
      expect(isMobilePlatform, isFalse);
    });

    test('isDesktopPlatform is true in test environment', () {
      expect(isDesktopPlatform, isTrue);
    });

    test('isMobilePlatform and isDesktopPlatform are mutually exclusive', () {
      expect(isMobilePlatform && isDesktopPlatform, isFalse);
      // At least one should be true
      expect(isMobilePlatform || isDesktopPlatform, isTrue);
    });
  });
}
