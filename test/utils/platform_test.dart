import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/platform.dart';

void main() {
  group('debugMobilePlatformOverride', () {
    tearDown(() {
      debugMobilePlatformOverride = null;
      debugDesktopPlatformOverride = null;
    });

    test('overrides isMobilePlatform to true', () {
      debugMobilePlatformOverride = true;
      expect(isMobilePlatform, isTrue);
    });

    test('overrides isMobilePlatform to false', () {
      debugMobilePlatformOverride = false;
      expect(isMobilePlatform, isFalse);
    });

    test('null override falls back to Platform detection', () {
      debugMobilePlatformOverride = null;
      final expected = Platform.isAndroid || Platform.isIOS;
      expect(isMobilePlatform, expected);
    });
  });

  group('debugDesktopPlatformOverride', () {
    tearDown(() {
      debugMobilePlatformOverride = null;
      debugDesktopPlatformOverride = null;
    });

    test('overrides isDesktopPlatform to true', () {
      debugDesktopPlatformOverride = true;
      expect(isDesktopPlatform, isTrue);
    });

    test('overrides isDesktopPlatform to false', () {
      debugDesktopPlatformOverride = false;
      expect(isDesktopPlatform, isFalse);
    });

    test('null override falls back to Platform detection', () {
      debugDesktopPlatformOverride = null;
      final expected =
          Platform.isLinux || Platform.isMacOS || Platform.isWindows;
      expect(isDesktopPlatform, expected);
    });
  });

  group('overrides are independent', () {
    tearDown(() {
      debugMobilePlatformOverride = null;
      debugDesktopPlatformOverride = null;
    });

    test('can set both to true simultaneously', () {
      debugMobilePlatformOverride = true;
      debugDesktopPlatformOverride = true;
      expect(isMobilePlatform, isTrue);
      expect(isDesktopPlatform, isTrue);
    });

    test('setting mobile does not affect desktop', () {
      debugMobilePlatformOverride = true;
      final desktopBefore = isDesktopPlatform;
      debugMobilePlatformOverride = false;
      expect(isDesktopPlatform, desktopBefore);
    });
  });
}
