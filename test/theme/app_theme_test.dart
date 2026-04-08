import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  group('AppTheme.dark()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.dark();
    });

    test('uses Material 3 with dark brightness', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('scaffold background matches surface', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });

    test('segmented button resolves selected/unselected state', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      final fg = style.foregroundColor!;
      expect(bg.resolve({WidgetState.selected}), isNot(bg.resolve({})));
      expect(fg.resolve({WidgetState.selected}), isNot(fg.resolve({})));
    });
  });

  group('AppTheme.light()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.light();
    });

    test('uses Material 3 with light brightness', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('scaffold background matches surface', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });

    test('segmented button resolves selected/unselected state', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      final fg = style.foregroundColor!;
      expect(bg.resolve({WidgetState.selected}), isNot(bg.resolve({})));
      expect(fg.resolve({WidgetState.selected}), isNot(fg.resolve({})));
    });
  });

  group('AppFonts', () {
    test('inter and mono produce different font families', () {
      expect(AppFonts.inter().fontFamily, 'Inter');
      expect(AppFonts.mono().fontFamily, 'JetBrains Mono');
    });

    test('inter passes fontSize, color, fontWeight, height', () {
      final style = AppFonts.inter(
        fontSize: 12,
        color: const Color(0xFFABB2BF),
        fontWeight: FontWeight.w600,
        height: 1.5,
      );
      expect(style.fontSize, 12);
      expect(style.color, const Color(0xFFABB2BF));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.height, 1.5);
    });

    test('mono passes fontSize, color, fontWeight', () {
      final style = AppFonts.mono(
        fontSize: 11,
        color: const Color(0xFF7F848E),
        fontWeight: FontWeight.bold,
      );
      expect(style.fontSize, 11);
      expect(style.color, const Color(0xFF7F848E));
      expect(style.fontWeight, FontWeight.bold);
    });

    test('themes use Inter for body text', () {
      expect(AppTheme.dark().textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, 'Inter');
    });
  });

  group('semantic colors follow brightness', () {
    test('connected/disconnected/connecting differ between dark and light', () {
      AppTheme.setBrightness(Brightness.dark);
      final darkConnected = AppTheme.connected;
      final darkDisconnected = AppTheme.disconnected;
      final darkConnecting = AppTheme.connecting;

      AppTheme.setBrightness(Brightness.light);
      expect(AppTheme.connected, isNot(darkConnected));
      expect(AppTheme.disconnected, isNot(darkDisconnected));
      expect(AppTheme.connecting, isNot(darkConnecting));

      AppTheme.setBrightness(Brightness.dark);
    });

    test('folderIcon differs between dark and light', () {
      AppTheme.setBrightness(Brightness.dark);
      final darkFolder = AppTheme.folderIcon;
      AppTheme.setBrightness(Brightness.light);
      expect(AppTheme.folderIcon, isNot(darkFolder));
      AppTheme.setBrightness(Brightness.dark);
    });

    test('info differs between dark and light', () {
      AppTheme.setBrightness(Brightness.dark);
      final darkInfo = AppTheme.info;
      AppTheme.setBrightness(Brightness.light);
      expect(AppTheme.info, isNot(darkInfo));
      AppTheme.setBrightness(Brightness.dark);
    });
  });

  group('setBrightness switches dynamic getters', () {
    setUp(() => AppTheme.setBrightness(Brightness.light));
    tearDown(() => AppTheme.setBrightness(Brightness.dark));

    test('light mode returns different bg/fg/border values', () {
      // These getters return light-specific values after setBrightness(light)
      final lightBg0 = AppTheme.bg0;
      final lightBorder = AppTheme.border;
      final lightSelection = AppTheme.selection;
      final lightHover = AppTheme.hover;

      AppTheme.setBrightness(Brightness.dark);
      expect(lightBg0, isNot(AppTheme.bg0));
      expect(lightBorder, isNot(AppTheme.border));
      expect(lightSelection, isNot(AppTheme.selection));
      expect(lightHover, isNot(AppTheme.hover));
    });
  });
}
