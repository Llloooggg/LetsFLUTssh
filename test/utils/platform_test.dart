import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/platform.dart';

void main() {
  group('platform utilities', () {
    test('homeDirectory returns non-empty on desktop', () {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(homeDirectory, isNotEmpty);
      }
    });

    test('isMobilePlatform and isDesktopPlatform are mutually exclusive', () {
      expect(isMobilePlatform && isDesktopPlatform, isFalse);
      expect(isMobilePlatform || isDesktopPlatform, isTrue);
    });
  });
}
