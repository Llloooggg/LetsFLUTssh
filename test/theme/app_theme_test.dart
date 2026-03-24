import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  group('AppTheme.dark()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.dark();
    });

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness is dark', () {
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('primary is OneDark blue', () {
      expect(theme.colorScheme.primary, const Color(0xFF61AFEF));
    });

    test('error is OneDark red', () {
      expect(theme.colorScheme.error, const Color(0xFFE06C75));
    });

    test('surface is OneDark bg', () {
      expect(theme.colorScheme.surface, const Color(0xFF282C34));
    });

    test('scaffold background matches surface', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });
  });

  group('AppTheme.light()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.light();
    });

    test('brightness is light', () {
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('primary is One Light blue', () {
      expect(theme.colorScheme.primary, const Color(0xFF4078F2));
    });

    test('surface is One Light bg', () {
      expect(theme.colorScheme.surface, const Color(0xFFFAFAFA));
    });
  });

  group('semantic colors', () {
    test('connected is green', () {
      expect(AppTheme.connected, const Color(0xFF98C379));
    });

    test('disconnected is red', () {
      expect(AppTheme.disconnected, const Color(0xFFE06C75));
    });

    test('connecting is yellow', () {
      expect(AppTheme.connecting, const Color(0xFFE5C07B));
    });

    test('info is cyan', () {
      expect(AppTheme.info, const Color(0xFF56B6C2));
    });

    test('folderIcon is yellow', () {
      expect(AppTheme.folderIcon, const Color(0xFFE5C07B));
    });
  });

  group('brightness-aware color resolvers', () {
    test('connectedColor returns dark variant for dark', () {
      expect(AppTheme.connectedColor(Brightness.dark), AppTheme.connected);
    });

    test('connectedColor returns light variant for light', () {
      expect(AppTheme.connectedColor(Brightness.light), AppTheme.connectedLight);
    });

    test('disconnectedColor returns dark variant for dark', () {
      expect(AppTheme.disconnectedColor(Brightness.dark), AppTheme.disconnected);
    });

    test('disconnectedColor returns light variant for light', () {
      expect(AppTheme.disconnectedColor(Brightness.light), AppTheme.disconnectedLight);
    });

    test('connectingColor returns dark variant for dark', () {
      expect(AppTheme.connectingColor(Brightness.dark), AppTheme.connecting);
    });

    test('connectingColor returns light variant for light', () {
      expect(AppTheme.connectingColor(Brightness.light), AppTheme.connectingLight);
    });
  });
}
