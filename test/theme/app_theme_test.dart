import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

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

  group('AppFonts platform-aware sizing', () {
    test('desktop sizes are default (tests run on desktop)', () {
      // Tests run on Linux — desktop is the default.
      expect(AppFonts.xs, 12.0);
      expect(AppFonts.sm, 13.0);
      expect(AppFonts.lg, 16.0);
      expect(AppFonts.xl, 19.0);
    });

    test('platform-invariant sizes stay the same', () {
      expect(AppFonts.tiny, 10.0);
      expect(AppFonts.xxs, 11.0);
      expect(AppFonts.md, 14.0);
    });

    test('all size tiers are in ascending order', () {
      final sizes = [
        AppFonts.tiny,
        AppFonts.xxs,
        AppFonts.xs,
        AppFonts.sm,
        AppFonts.md,
        AppFonts.lg,
        AppFonts.xl,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(
          sizes[i],
          greaterThanOrEqualTo(sizes[i - 1]),
          reason: 'size tier $i should be >= tier ${i - 1}',
        );
      }
    });
  });

  group('AppTheme.inputDecoration', () {
    test('returns filled decoration with themed borders', () {
      final dec = AppTheme.inputDecoration();
      expect(dec.filled, isTrue);
      expect(dec.fillColor, AppTheme.bg3);
      expect(dec.isDense, isTrue);
      expect(dec.border, isA<OutlineInputBorder>());
      expect(dec.enabledBorder, isA<OutlineInputBorder>());
      expect(dec.focusedBorder, isA<OutlineInputBorder>());
    });

    test('passes through labelText and hintText', () {
      final dec = AppTheme.inputDecoration(
        labelText: 'Label',
        hintText: 'Hint',
      );
      expect(dec.labelText, 'Label');
      expect(dec.hintText, 'Hint');
    });

    test('uses custom contentPadding when provided', () {
      const padding = EdgeInsets.all(20);
      final dec = AppTheme.inputDecoration(contentPadding: padding);
      expect(dec.contentPadding, padding);
    });

    test('enabled and normal borders share the same style', () {
      final dec = AppTheme.inputDecoration();
      expect(dec.border, equals(dec.enabledBorder));
    });

    test('focused border uses accent color', () {
      final dec = AppTheme.inputDecoration();
      final focused = dec.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, AppTheme.accent);
    });
  });

  group('AppTheme.terminalTheme', () {
    test('returns a valid TerminalTheme', () {
      final theme = AppTheme.terminalTheme;
      expect(theme, isA<TerminalTheme>());
      expect(theme.foreground, AppTheme.fg);
      expect(theme.background, AppTheme.bg2);
      expect(theme.cursor, AppTheme.termCursor);
    });

    test('search hit colors are set', () {
      final theme = AppTheme.terminalTheme;
      expect(theme.searchHitBackgroundCurrent, AppTheme.accent);
      expect(theme.searchHitForeground, AppTheme.searchHitFg);
    });
  });
}
