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

    test('primary is accent indigo', () {
      expect(theme.colorScheme.primary, const Color(0xFF4D78CC));
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

    test('segmented button resolves selected background', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      expect(bg.resolve({WidgetState.selected}), const Color(0xFF4D78CC));
      expect(bg.resolve({}), const Color(0xFF2C313A));
    });

    test('segmented button resolves selected foreground', () {
      final style = theme.segmentedButtonTheme.style!;
      final fg = style.foregroundColor!;
      expect(fg.resolve({WidgetState.selected}), Colors.white);
      expect(fg.resolve({}), const Color(0xFFABB2BF));
    });
  });

  group('AppTheme.light()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.light();
    });

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
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
      expect(theme.tooltipTheme.waitDuration,
          const Duration(milliseconds: 400));
    });

    test('progress indicator uses light blue', () {
      expect(theme.progressIndicatorTheme.color, const Color(0xFF4078F2));
    });

    test('segmented button resolves selected background', () {
      final style = theme.segmentedButtonTheme.style!;
      final bg = style.backgroundColor!;
      expect(bg.resolve({WidgetState.selected}), const Color(0xFF4078F2));
      expect(bg.resolve({}), Colors.white);
    });

    test('segmented button resolves selected foreground', () {
      final style = theme.segmentedButtonTheme.style!;
      final fg = style.foregroundColor!;
      expect(fg.resolve({WidgetState.selected}), Colors.white);
      expect(fg.resolve({}), const Color(0xFF383A42));
    });
  });

  group('chip theme', () {
    test('dark chip uses bg3 background', () {
      final theme = AppTheme.dark();
      expect(theme.chipTheme.backgroundColor, const Color(0xFF2C313A));
    });

    test('dark chip selected color uses accent with alpha', () {
      final theme = AppTheme.dark();
      expect(theme.chipTheme.selectedColor, isNotNull);
      // Selected color is accent-tinted
      expect(theme.chipTheme.selectedColor!.a, lessThan(1.0));
    });

    test('dark chip border matches bg0 border', () {
      final theme = AppTheme.dark();
      final side = theme.chipTheme.side as BorderSide;
      expect(side.color, const Color(0xFF1B1D23));
    });

    test('light chip uses white background', () {
      final theme = AppTheme.light();
      expect(theme.chipTheme.backgroundColor, Colors.white);
    });

    test('light chip border matches light border', () {
      final theme = AppTheme.light();
      final side = theme.chipTheme.side as BorderSide;
      expect(side.color, const Color(0xFFD3D3D3));
    });
  });

  group('border radius constants', () {
    test('radiusSm is 4px', () {
      expect(
        AppTheme.radiusSm,
        const BorderRadius.all(Radius.circular(4)),
      );
    });

    test('radiusMd is 6px', () {
      expect(
        AppTheme.radiusMd,
        const BorderRadius.all(Radius.circular(6)),
      );
    });

    test('radiusLg is 8px', () {
      expect(
        AppTheme.radiusLg,
        const BorderRadius.all(Radius.circular(8)),
      );
    });

    test('dark dialog shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.dialogTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light dialog shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.dialogTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark input decoration uses radiusSm', () {
      final theme = AppTheme.dark();
      final border = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(border.borderRadius, AppTheme.radiusSm);
    });

    test('light input decoration uses radiusSm', () {
      final theme = AppTheme.light();
      final border = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(border.borderRadius, AppTheme.radiusSm);
    });

    test('dark popup menu shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.popupMenuTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark chip shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.chipTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark text button shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.textButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light text button shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.textButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark icon button shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.iconButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light icon button shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.iconButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark checkbox shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.checkboxTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light checkbox shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.checkboxTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark card shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light card shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark snackBar shape uses radiusSm', () {
      final theme = AppTheme.dark();
      final shape = theme.snackBarTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('light snackBar shape uses radiusSm', () {
      final theme = AppTheme.light();
      final shape = theme.snackBarTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, AppTheme.radiusSm);
    });

    test('dark bottomSheet has rounded top corners', () {
      final theme = AppTheme.dark();
      final shape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, const BorderRadius.vertical(top: Radius.circular(8)));
    });

    test('light bottomSheet has rounded top corners', () {
      final theme = AppTheme.light();
      final shape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, const BorderRadius.vertical(top: Radius.circular(8)));
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

    test('connectedLight is light green', () {
      expect(AppTheme.connectedLight, const Color(0xFF50A14F));
    });

    test('connectingLight is light yellow', () {
      expect(AppTheme.connectingLight, const Color(0xFFC18401));
    });

    test('disconnectedLight is light red', () {
      expect(AppTheme.disconnectedLight, const Color(0xFFE45649));
    });

    test('searchHighlight is defined', () {
      expect(AppTheme.searchHighlight, const Color(0xFFFFFF2B));
    });

    test('searchHighlightLight is defined', () {
      expect(AppTheme.searchHighlightLight, const Color(0xFFFFD700));
    });
  });

  group('public color constants', () {
    test('accent is indigo', () {
      expect(AppTheme.accent, const Color(0xFF4D78CC));
    });

    test('bg0..bg4 are distinct dark layers', () {
      expect(AppTheme.bg0, const Color(0xFF1B1D23));
      expect(AppTheme.bg1, const Color(0xFF1E2127));
      expect(AppTheme.bg2, const Color(0xFF282C34));
      expect(AppTheme.bg3, const Color(0xFF2C313A));
      expect(AppTheme.bg4, const Color(0xFF333842));
    });

    test('border equals bg0', () {
      expect(AppTheme.border, AppTheme.bg0);
    });

    test('borderLight equals bg3', () {
      expect(AppTheme.borderLight, AppTheme.bg3);
    });

    test('selection has partial alpha', () {
      expect(AppTheme.selection, const Color(0x1F4D78CC));
    });

    test('hover has partial alpha', () {
      expect(AppTheme.hover, const Color(0x08FFFFFF));
    });

    test('active has partial alpha', () {
      expect(AppTheme.active, const Color(0x0FFFFFFF));
    });
  });

  group('AppFonts', () {
    test('inter fontFamily is Inter', () {
      expect(AppFonts.inter().fontFamily, 'Inter');
    });

    test('inter passes fontSize and color', () {
      final style = AppFonts.inter(fontSize: 12, color: const Color(0xFFABB2BF));
      expect(style.fontSize, 12);
      expect(style.color, const Color(0xFFABB2BF));
    });

    test('inter passes fontWeight and height', () {
      final style = AppFonts.inter(fontWeight: FontWeight.w600, height: 1.5);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.height, 1.5);
    });

    test('mono fontFamily is JetBrains Mono', () {
      expect(AppFonts.mono().fontFamily, 'JetBrains Mono');
    });

    test('mono passes fontSize and color', () {
      final style = AppFonts.mono(fontSize: 11, color: const Color(0xFF7F848E));
      expect(style.fontSize, 11);
      expect(style.color, const Color(0xFF7F848E));
    });

    test('mono passes fontWeight', () {
      final style = AppFonts.mono(fontWeight: FontWeight.bold);
      expect(style.fontWeight, FontWeight.bold);
    });

    test('inter and mono have different font families', () {
      expect(AppFonts.inter().fontFamily, isNot(AppFonts.mono().fontFamily));
    });

    test('dark textTheme uses Inter font family', () {
      final theme = AppTheme.dark();
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    });

    test('light textTheme uses Inter font family', () {
      final theme = AppTheme.light();
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    });
  });

  group('brightness-aware color resolvers', () {
    test('connectedColor dark', () {
      expect(AppTheme.connectedColor(Brightness.dark), AppTheme.connected);
    });

    test('connectedColor light', () {
      expect(
          AppTheme.connectedColor(Brightness.light), AppTheme.connectedLight);
    });

    test('disconnectedColor dark', () {
      expect(
          AppTheme.disconnectedColor(Brightness.dark), AppTheme.disconnected);
    });

    test('disconnectedColor light', () {
      expect(AppTheme.disconnectedColor(Brightness.light),
          AppTheme.disconnectedLight);
    });

    test('connectingColor dark', () {
      expect(AppTheme.connectingColor(Brightness.dark), AppTheme.connecting);
    });

    test('connectingColor light', () {
      expect(AppTheme.connectingColor(Brightness.light),
          AppTheme.connectingLight);
    });

    test('folderColor dark', () {
      expect(AppTheme.folderColor(Brightness.dark), const Color(0xFFE5C07B));
    });

    test('folderColor light', () {
      expect(AppTheme.folderColor(Brightness.light), const Color(0xFFC18401));
    });
  });

  group('light brightness-aware getters', () {
    setUp(() => AppTheme.setBrightness(Brightness.light));
    tearDown(() => AppTheme.setBrightness(Brightness.dark));

    test('bg0 is darker toolbar gray', () {
      expect(AppTheme.bg0, const Color(0xFFDCDCDD));
    });

    test('fgDim has good contrast against light bg', () {
      expect(AppTheme.fgDim, const Color(0xFF696C77));
    });

    test('fgFaint has readable contrast against light bg', () {
      expect(AppTheme.fgFaint, const Color(0xFF8C8F96));
    });

    test('border is visible on light surfaces', () {
      expect(AppTheme.border, const Color(0xFFC4C4C6));
    });

    test('borderLight uses light border for inputs', () {
      expect(AppTheme.borderLight, const Color(0xFFD3D3D3));
    });

    test('selection has higher alpha than dark', () {
      expect(AppTheme.selection, const Color(0x2A4078F2));
    });

    test('hover is perceptible on light background', () {
      expect(AppTheme.hover, const Color(0x12000000));
    });

    test('active is perceptible on light background', () {
      expect(AppTheme.active, const Color(0x1A000000));
    });
  });
}
