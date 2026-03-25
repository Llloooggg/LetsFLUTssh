import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  group('AppTheme.light() — detailed checks', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.light();
    });

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('scaffold background is light bg', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFAFAFA));
    });

    test('divider color is light border', () {
      expect(theme.dividerColor, const Color(0xFFD3D3D3));
    });

    test('error color is light red', () {
      expect(theme.colorScheme.error, const Color(0xFFE45649));
    });

    test('appBar background is light surface', () {
      expect(theme.appBarTheme.backgroundColor, const Color(0xFFF0F0F0));
    });

    test('splashFactory is NoSplash', () {
      expect(theme.splashFactory, NoSplash.splashFactory);
    });

    test('tooltip has wait duration', () {
      expect(theme.tooltipTheme.waitDuration, const Duration(milliseconds: 400));
    });

    test('filledButton uses light blue', () {
      expect(theme.colorScheme.primary, const Color(0xFF4078F2));
    });

    test('segmented button resolves selected background', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      final selectedColor = bg.resolve({WidgetState.selected});
      final unselectedColor = bg.resolve({});
      expect(selectedColor, const Color(0xFF4078F2));
      expect(unselectedColor, Colors.white);
    });

    test('segmented button resolves selected foreground', () {
      final style = theme.segmentedButtonTheme.style!;
      final fg = style.foregroundColor!;
      final selectedColor = fg.resolve({WidgetState.selected});
      final unselectedColor = fg.resolve({});
      expect(selectedColor, Colors.white);
      expect(unselectedColor, const Color(0xFF383A42));
    });

    test('progress indicator uses light blue', () {
      expect(theme.progressIndicatorTheme.color, const Color(0xFF4078F2));
    });
  });

  group('AppTheme.dark() — segmented button resolvers', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.dark();
    });

    test('segmented button resolves selected background', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      final selectedColor = bg.resolve({WidgetState.selected});
      final unselectedColor = bg.resolve({});
      expect(selectedColor, const Color(0xFF61AFEF));
      expect(unselectedColor, const Color(0xFF21252B));
    });

    test('segmented button resolves selected foreground', () {
      final style = theme.segmentedButtonTheme.style!;
      final fg = style.foregroundColor!;
      final selectedColor = fg.resolve({WidgetState.selected});
      final unselectedColor = fg.resolve({});
      expect(selectedColor, const Color(0xFF282C34));
      expect(unselectedColor, const Color(0xFFABB2BF));
    });
  });

  group('AppTheme.folderColor', () {
    test('returns yellow for dark brightness', () {
      expect(AppTheme.folderColor(Brightness.dark), const Color(0xFFE5C07B));
    });

    test('returns light yellow for light brightness', () {
      expect(AppTheme.folderColor(Brightness.light), const Color(0xFFC18401));
    });
  });

  group('AppTheme — search highlight colors', () {
    test('searchHighlight is defined', () {
      expect(AppTheme.searchHighlight, const Color(0xFFFFFF2B));
    });

    test('searchHighlightLight is defined', () {
      expect(AppTheme.searchHighlightLight, const Color(0xFFFFD700));
    });
  });

  group('AppTheme — light theme variants', () {
    test('connectedLight is light green', () {
      expect(AppTheme.connectedLight, const Color(0xFF50A14F));
    });

    test('connectingLight is light yellow', () {
      expect(AppTheme.connectingLight, const Color(0xFFC18401));
    });

    test('disconnectedLight is light red', () {
      expect(AppTheme.disconnectedLight, const Color(0xFFE45649));
    });
  });
}
