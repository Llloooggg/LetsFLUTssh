import 'package:flutter/material.dart';

import '../utils/platform.dart' as plat;

/// Centralized color palette for the app.
///
/// Dark theme: **OneDark Pro** (VS Code) — exact hex values.
/// Light theme: **Atom One Light** — exact hex values.
///
/// Every color in the UI MUST come from this class.  No hardcoded
/// `Color(0x…)`, `Colors.*` or hex literals outside of this file.
abstract final class AppTheme {
  // ══════════════════════════════════════════════════════════════════
  //  DARK — OneDark Pro (binaryify/OneDark-Pro)
  // ══════════════════════════════════════════════════════════════════

  // ── Backgrounds (darkest → lightest) ──
  static const _bg0 = Color(0xFF1B1D23); // peek view, deepest surface
  static const _bg1 = Color(0xFF21252B); // sidebar, status bar, widgets
  static const _bg2 = Color(0xFF282C34); // editor / main content
  static const _bg3 = Color(0xFF2C313A); // active selection, inputs
  static const _bg4 = Color(0xFF323842); // hover, inactive selection

  // ── Foregrounds ──
  static const _fg       = Color(0xFFABB2BF); // mono-1, default text
  static const _fgDim    = Color(0xFF7F848E); // comments (italic)
  static const _fgFaint  = Color(0xFF5C6370); // comments, quote markup
  static const _fgBright = Color(0xFFD7DAE0); // activity-bar fg, highlights

  // ── Accent & syntax hues ──
  static const _accent = Color(0xFF4D78CC); // badge / status-bar-item
  static const _blue   = Color(0xFF61AFEF); // hue-2: functions
  static const _green  = Color(0xFF98C379); // hue-4: strings
  static const _red    = Color(0xFFE06C75); // hue-5: variables / tags
  static const _yellow = Color(0xFFE5C07B); // hue-6-2: classes / types
  static const _orange = Color(0xFFD19A66); // hue-6: constants / numbers
  static const _cyan   = Color(0xFF56B6C2); // hue-1: operators / support
  static const _purple = Color(0xFFC678DD); // hue-3: keywords / storage

  // ── Borders & interactive states ──
  static const _border      = Color(0xFF181A1F); // editor group, tab borders
  static const _borderLight = Color(0xFF3E4452); // panel border, focus border
  static const _selectionColor = Color(0x1F4D78CC); // accent @ 12 %
  static const _hoverColor     = Color(0x08FFFFFF); // white @ 3 %
  static const _activeColor    = Color(0x0FFFFFFF); // white @ 6 %

  // ── On-accent (text on accent-colored backgrounds) ──
  static const _onAccent = Color(0xFFF8FAFD); // badge fg

  // ── Scrollbar ──
  static const _scrollThumb = Color(0x667F848E); // fgDim @ 40 %

  // ── Terminal cursor & selection ──
  static const _termCursorColor     = Color(0xFF528BFF); // OneDark Pro syntax-accent
  static const _termSelectionColor  = Color(0x60677696); // OneDark Pro editor.selectionBackground

  // ── Terminal ANSI (OneDark Pro terminal.*) ──
  static const _termBlack       = Color(0xFF3F4451);
  static const _termRed         = Color(0xFFE05561);
  static const _termGreen       = Color(0xFF8CC265);
  static const _termYellow      = Color(0xFFD18F52);
  static const _termBlue        = Color(0xFF4AA5F0);
  static const _termMagenta     = Color(0xFFC162DE);
  static const _termCyan        = Color(0xFF42B3C2);
  static const _termWhite       = Color(0xFFD7DAE0);
  static const _termBrightBlack = Color(0xFF4F5666);
  static const _termBrightRed   = Color(0xFFFF616E);
  static const _termBrightGreen = Color(0xFFA5E075);
  static const _termBrightYellow  = Color(0xFFF0A45D);
  static const _termBrightBlue   = Color(0xFF4DC4FF);
  static const _termBrightMagenta = Color(0xFFDE73FF);
  static const _termBrightCyan   = Color(0xFF4CD1E0);
  static const _termBrightWhite  = Color(0xFFE6E6E6);

  // ══════════════════════════════════════════════════════════════════
  //  LIGHT — Atom One Light (official)
  // ══════════════════════════════════════════════════════════════════

  // ── Backgrounds ──
  static const _lightBg        = Color(0xFFFAFAFA); // level-2, editor
  static const _lightSurface   = Color(0xFFEAEBEB); // level-3, sidebar
  static const _lightBg0       = Color(0xFFDBDBDC); // bg-selected, deepest
  static const _lightSelection = Color(0xFFE5E5E6); // syntax selection

  // ── Foregrounds ──
  static const _lightFg        = Color(0xFF383A42); // mono-1
  static const _lightFgDim     = Color(0xFF696C77); // mono-2
  static const _lightFgFaint   = Color(0xFFA0A1A7); // mono-3
  static const _lightFgBright  = Color(0xFF232424); // text-highlight

  // ── Accent & syntax hues ──
  static const _lightBlue      = Color(0xFF4078F2); // hue-2
  static const _lightGreen     = Color(0xFF50A14F); // hue-4
  static const _lightRed       = Color(0xFFE45649); // hue-5
  static const _lightYellow    = Color(0xFFC18401); // hue-6-2
  static const _lightOrange    = Color(0xFF986801); // hue-6
  static const _lightCyan      = Color(0xFF0184BC); // hue-1
  static const _lightPurple    = Color(0xFFA626A4); // hue-3

  // ── Borders & interactive states ──
  static const _lightBorder    = Color(0xFFDBDBDC); // ui-border
  static const _lightGutter    = Color(0xFF9D9D9F); // gutter text

  // ── Level-1 surface (inputs, cards, popups — lightest bg) ──
  static const _lightLevel1    = Color(0xFFFFFFFF);

  // ── On-accent ──
  static const _lightOnAccent  = Color(0xFFFFFFFF);

  // ── Terminal cursor & selection ──
  static const _lightTermCursorColor    = Color(0xFF526FFF); // One Light syntax-accent
  static const _lightTermSelectionColor = Color(0x604078F2); // lightBlue @ 38 %

  // ── Scrollbar ──
  static const _lightScrollThumb = Color(0x88696C77); // fgDim @ 53 %

  // ── Terminal ANSI (derived from One Light syntax palette) ──
  static const _lightTermBlack       = Color(0xFF383A42);
  static const _lightTermRed         = Color(0xFFE45649);
  static const _lightTermGreen       = Color(0xFF50A14F);
  static const _lightTermYellow      = Color(0xFFC18401);
  static const _lightTermBlue        = Color(0xFF4078F2);
  static const _lightTermMagenta     = Color(0xFFA626A4);
  static const _lightTermCyan        = Color(0xFF0184BC);
  static const _lightTermWhite       = Color(0xFFFAFAFA);
  static const _lightTermBrightBlack = Color(0xFF696C77);
  static const _lightTermBrightRed   = Color(0xFFE45649);
  static const _lightTermBrightGreen = Color(0xFF50A14F);
  static const _lightTermBrightYellow  = Color(0xFFC18401);
  static const _lightTermBrightBlue   = Color(0xFF4078F2);
  static const _lightTermBrightMagenta = Color(0xFFA626A4);
  static const _lightTermBrightCyan   = Color(0xFF0184BC);
  static const _lightTermBrightWhite  = Color(0xFFFFFFFF);

  // ── Brightness-aware state ──
  // Set by the app root widget when the theme mode changes.
  static Brightness _brightness = Brightness.dark;

  /// Call from the app root to sync with the current theme brightness.
  static void setBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get isDark => _brightness == Brightness.dark;

  // ── Public brightness-aware colors ──

  // Backgrounds
  static Color get bg0 => isDark ? _bg0 : _lightBg0;
  static Color get bg1 => isDark ? _bg1 : _lightSurface;
  static Color get bg2 => isDark ? _bg2 : _lightBg;
  static Color get bg3 => isDark ? _bg3 : _lightSelection;
  static Color get bg4 => isDark ? _bg4 : _lightBorder;

  // Foregrounds
  static Color get fg       => isDark ? _fg : _lightFg;
  static Color get fgDim    => isDark ? _fgDim : _lightFgDim;
  static Color get fgFaint  => isDark ? _fgFaint : _lightFgFaint;
  static Color get fgBright => isDark ? _fgBright : _lightFgBright;

  // Accent & hues
  static Color get accent => isDark ? _accent : _lightBlue;
  static Color get blue   => isDark ? _blue : _lightBlue;
  static Color get green  => isDark ? _green : _lightGreen;
  static Color get red    => isDark ? _red : _lightRed;
  static Color get yellow => isDark ? _yellow : _lightYellow;
  static Color get orange => isDark ? _orange : _lightOrange;
  static Color get cyan   => isDark ? _cyan : _lightCyan;
  static Color get purple => isDark ? _purple : _lightPurple;

  // Borders & interactive
  static Color get border      => isDark ? _border : _lightBorder;
  static Color get borderLight => isDark ? _borderLight : _lightBorder;
  static Color get selection   => isDark ? _selectionColor : const Color(0x2A4078F2);
  static Color get hover       => isDark ? _hoverColor : const Color(0x12000000);
  static Color get active      => isDark ? _activeColor : const Color(0x1A000000);

  /// Text color for accent-colored backgrounds (buttons, badges, toggles).
  static Color get onAccent => isDark ? _onAccent : _lightOnAccent;

  // ── Terminal ANSI colors ──
  static Color get termBlack       => isDark ? _termBlack : _lightTermBlack;
  static Color get termRed         => isDark ? _termRed : _lightTermRed;
  static Color get termGreen       => isDark ? _termGreen : _lightTermGreen;
  static Color get termYellow      => isDark ? _termYellow : _lightTermYellow;
  static Color get termBlue        => isDark ? _termBlue : _lightTermBlue;
  static Color get termMagenta     => isDark ? _termMagenta : _lightTermMagenta;
  static Color get termCyan        => isDark ? _termCyan : _lightTermCyan;
  static Color get termWhite       => isDark ? _termWhite : _lightTermWhite;
  static Color get termBrightBlack => isDark ? _termBrightBlack : _lightTermBrightBlack;
  static Color get termBrightRed   => isDark ? _termBrightRed : _lightTermBrightRed;
  static Color get termBrightGreen => isDark ? _termBrightGreen : _lightTermBrightGreen;
  static Color get termBrightYellow  => isDark ? _termBrightYellow : _lightTermBrightYellow;
  static Color get termBrightBlue   => isDark ? _termBrightBlue : _lightTermBrightBlue;
  static Color get termBrightMagenta => isDark ? _termBrightMagenta : _lightTermBrightMagenta;
  static Color get termBrightCyan   => isDark ? _termBrightCyan : _lightTermBrightCyan;
  static Color get termBrightWhite  => isDark ? _termBrightWhite : _lightTermBrightWhite;

  /// Terminal block-cursor color (semi-transparent so text shows through).
  static Color get termCursor    => isDark ? _termCursorColor : _lightTermCursorColor;

  /// Terminal mouse-selection highlight.
  static Color get termSelection => isDark ? _termSelectionColor : _lightTermSelectionColor;

  // ── Section border helpers ──
  // Brightness-aware single-side borders for container edges (headers,
  // footers, toolbars). Use in BoxDecoration.border.
  static BorderSide get borderSide => BorderSide(color: border);
  static Border get borderTop => Border(top: borderSide);
  static Border get borderBottom => Border(bottom: borderSide);

  // ── Border radius scale ──
  /// 4 px — inputs, buttons, small elements.
  static const radiusSm = BorderRadius.all(Radius.circular(4));
  /// 6 px — cards, containers, default rounding.
  static const radiusMd = BorderRadius.all(Radius.circular(6));
  /// 8 px — toasts, mobile elements, larger containers.
  static const radiusLg = BorderRadius.all(Radius.circular(8));

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _accent,
      onPrimary: _onAccent,
      primaryContainer: Color(0xFF1C3566),
      onPrimaryContainer: _accent,
      secondary: _green,
      onSecondary: _bg2,
      secondaryContainer: Color(0xFF1E3A1E),
      onSecondaryContainer: _green,
      tertiary: _purple,
      onTertiary: _bg2,
      tertiaryContainer: Color(0xFF3A1E3A),
      onTertiaryContainer: _purple,
      error: _red,
      onError: _bg2,
      errorContainer: Color(0xFF4A1A1E),
      onErrorContainer: _red,
      surface: _bg2,
      onSurface: _fg,
      surfaceContainerLowest: _bg0,
      surfaceContainerLow: _bg1,
      surfaceContainer: _bg2,
      surfaceContainerHigh: _bg3,
      surfaceContainerHighest: _bg4,
      onSurfaceVariant: _fgDim,
      outline: _border,
      outlineVariant: _borderLight,
      inverseSurface: _fg,
      onInverseSurface: _bg2,
      inversePrimary: Color(0xFF2D4A8C),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg2,
      dividerColor: _border,
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(color: _border, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg1,
        foregroundColor: _fg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: _bg1,
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: _borderLight),
        ),
        menuPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _bg2,
        shape: const RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: _borderLight),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.lg,
          fontWeight: FontWeight.w600,
          color: _fg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.sm,
          color: _fg,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.3),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: _bg3,
        border: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: _fgFaint),
        labelStyle: TextStyle(color: _fgDim),
      ),
      iconTheme: const IconThemeData(color: _fg, size: 20),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _fg),
        bodyMedium: TextStyle(color: _fg),
        bodySmall: TextStyle(color: _fgDim),
        titleSmall: TextStyle(color: _accent),
      ).apply(fontFamily: 'Inter'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _onAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _fg,
          side: const BorderSide(color: _borderLight),
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _onAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _accent;
            return _bg3;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _onAccent;
            return _fg;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _borderLight)),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: radiusSm),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _fg,
        textColor: _fg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _bg1,
        indicatorColor: _accent.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accent);
          }
          return const IconThemeData(color: _fgDim);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: _accent, fontSize: AppFonts.md);
          }
          return TextStyle(color: _fgDim, fontSize: AppFonts.md);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: _accent,
        thumbColor: _accent,
        inactiveTrackColor: _bg4,
        overlayColor: _selectionColor,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: _bg0,
          border: Border.all(color: _borderLight),
          borderRadius: radiusSm,
        ),
        textStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.xs,
          color: _fg,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _bg3,
        selectedColor: _accent.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: _fg),
        secondaryLabelStyle: const TextStyle(color: _accent),
        side: const BorderSide(color: _border),
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        deleteIconColor: _fgDim,
        checkmarkColor: _accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(_scrollThumb),
        radius: Radius.zero,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        side: const BorderSide(color: _fgDim),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(_onAccent),
      ),
      cardTheme: const CardThemeData(
        color: _bg3,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _bg3,
        contentTextStyle: TextStyle(color: _fg),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: _bg4,
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: _lightBlue,
      onPrimary: _lightOnAccent,
      primaryContainer: Color(0xFFD4E4FF),
      onPrimaryContainer: _lightBlue,
      secondary: _lightGreen,
      onSecondary: _lightOnAccent,
      secondaryContainer: Color(0xFFD4F0D4),
      onSecondaryContainer: _lightGreen,
      tertiary: _lightPurple,
      onTertiary: _lightOnAccent,
      tertiaryContainer: Color(0xFFF0D4F0),
      onTertiaryContainer: _lightPurple,
      error: _lightRed,
      onError: _lightOnAccent,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: _lightRed,
      surface: _lightBg,
      onSurface: _lightFg,
      surfaceContainerLowest: _lightLevel1,
      surfaceContainerLow: _lightSurface,
      surfaceContainer: _lightBg,
      surfaceContainerHigh: _lightSelection,
      surfaceContainerHighest: _lightBorder,
      onSurfaceVariant: _lightGutter,
      outline: _lightBorder,
      outlineVariant: _lightSelection,
      inverseSurface: _lightFg,
      onInverseSurface: _lightBg,
      inversePrimary: Color(0xFF82B1FF),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _lightBg,
      dividerColor: _lightBorder,
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(color: _lightBorder, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightSurface,
        foregroundColor: _lightFg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: _lightLevel1,
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: _lightBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightBg,
        shape: const RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: _lightBorder),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.lg,
          fontWeight: FontWeight.w600,
          color: _lightFg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.sm,
          color: _lightFg,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _lightBlue,
        selectionColor: _lightBlue.withValues(alpha: 0.3),
        selectionHandleColor: _lightBlue,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: _lightLevel1,
        border: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: _lightBlue, width: 1.5),
        ),
        hintStyle: TextStyle(color: _lightGutter),
        labelStyle: TextStyle(color: _lightGutter),
      ),
      iconTheme: const IconThemeData(color: _lightFg, size: 20),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _lightFg),
        bodyMedium: TextStyle(color: _lightFg),
        bodySmall: TextStyle(color: _lightGutter),
        titleSmall: TextStyle(color: _lightBlue),
      ).apply(fontFamily: 'Inter'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lightBlue,
          foregroundColor: _lightOnAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightFg,
          side: const BorderSide(color: _lightBorder),
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _lightBlue,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightBlue,
          foregroundColor: _lightOnAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _lightBlue;
            return _lightLevel1;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _lightOnAccent;
            return _lightFg;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _lightBorder)),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: radiusSm),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _lightFg,
        textColor: _lightFg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: _lightBlue.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _lightBlue);
          }
          return const IconThemeData(color: _lightGutter);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: _lightBlue, fontSize: AppFonts.md);
          }
          return TextStyle(color: _lightGutter, fontSize: AppFonts.md);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: _lightBlue,
        thumbColor: _lightBlue,
        inactiveTrackColor: _lightSelection,
        overlayColor: Color(0x2A4078F2), // lightBlue @ 16 %
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: _lightFg,
          border: Border.all(color: _lightBorder),
          borderRadius: radiusSm,
        ),
        textStyle: TextStyle(color: _lightBg, fontSize: AppFonts.md),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightLevel1,
        selectedColor: _lightBlue.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: _lightFg),
        secondaryLabelStyle: const TextStyle(color: _lightBlue),
        side: const BorderSide(color: _lightBorder),
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        deleteIconColor: _lightGutter,
        checkmarkColor: _lightBlue,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(_lightScrollThumb),
        radius: Radius.zero,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        side: const BorderSide(color: _lightGutter),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _lightBlue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(_lightOnAccent),
      ),
      cardTheme: const CardThemeData(
        color: _lightLevel1,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _lightFg,
        contentTextStyle: TextStyle(color: _lightBg),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lightBlue,
        linearTrackColor: _lightSelection,
      ),
    );
  }

  // ── Semantic colors for use across the app ──

  /// Green — connected, success.
  static const Color connected = _green;

  /// Yellow/orange — connecting, warning.
  static const Color connecting = _yellow;

  /// Red — disconnected, error.
  static const Color disconnected = _red;

  /// Cyan — info, accents.
  static const Color info = _cyan;

  /// Folder icon color.
  static const Color folderIcon = _yellow;

  /// Terminal search highlight backgrounds.
  static const Color _searchHighlightDark  = Color(0xFFFFFF2B);
  static const Color _searchHighlightLight = Color(0xFFFFD700);
  static Color get searchHighlight => isDark ? _searchHighlightDark : _searchHighlightLight;

  /// Terminal search hit foreground — high-contrast text on colored bg.
  static Color get searchHitFg => isDark ? _termBrightWhite : _lightFgBright;

  /// Light-theme variants.
  static const Color connectedLight = _lightGreen;
  static const Color connectingLight = _lightYellow;
  static const Color disconnectedLight = _lightRed;

  /// Resolve semantic color based on brightness.
  static Color connectedColor(Brightness brightness) =>
      brightness == Brightness.dark ? connected : connectedLight;

  static Color connectingColor(Brightness brightness) =>
      brightness == Brightness.dark ? connecting : connectingLight;

  static Color disconnectedColor(Brightness brightness) =>
      brightness == Brightness.dark ? disconnected : disconnectedLight;

  static Color folderColor(Brightness brightness) =>
      brightness == Brightness.dark ? _yellow : _lightYellow;
}

/// Font helpers — Inter for UI, JetBrains Mono for technical data.
///
/// Returns plain [TextStyle] objects with [fontFamily] set.
/// Fonts are bundled as assets in `assets/fonts/`.
///
/// Platform-aware size constants: mobile gets +2 px for touch readability.
/// Use [tiny]–[xl] instead of hardcoded fontSize values.
abstract final class AppFonts {
  static const _inter = 'Inter';
  static const _mono = 'JetBrains Mono';

  static final bool _mobile = plat.isMobilePlatform;

  // ── Platform-aware size scale (desktop / mobile) ──

  /// 10 / 10 — transfer errors, smallest fine print.
  static double get tiny => 10.0;

  /// 11 / 11 — keyboard shortcuts, status badges.
  static double get xxs => 11.0;

  /// 12 / 13 — captions, subtitles, metadata, file details.
  static double get xs => _mobile ? 13.0 : 12.0;

  /// 13 / 14 — body text, inputs, default UI text.
  static double get sm => _mobile ? 14.0 : 13.0;

  /// 14 / 14 — section headers, form labels.
  static double get md => 14.0;

  /// 16 / 15 — dialog titles, sub-headings, toasts.
  static double get lg => _mobile ? 15.0 : 16.0;

  /// 19 / 18 — page headings.
  static double get xl => _mobile ? 18.0 : 19.0;

  static TextStyle inter({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _inter,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: _mono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
}
