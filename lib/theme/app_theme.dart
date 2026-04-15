import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

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
  static const _fg = Color(0xFFABB2BF); // mono-1, default text
  static const _fgDim = Color(0xFF7F848E); // comments (italic)
  static const _fgFaint = Color(0xFF5C6370); // comments, quote markup
  static const _fgBright = Color(0xFFD7DAE0); // activity-bar fg, highlights

  // ── Accent & syntax hues ──
  static const _accent = Color(0xFF4D78CC); // badge / status-bar-item
  static const _blue = Color(0xFF61AFEF); // hue-2: functions
  static const _green = Color(0xFF98C379); // hue-4: strings
  static const _red = Color(0xFFE06C75); // hue-5: variables / tags
  static const _yellow = Color(0xFFE5C07B); // hue-6-2: classes / types
  static const _orange = Color(0xFFD19A66); // hue-6: constants / numbers
  static const _cyan = Color(0xFF56B6C2); // hue-1: operators / support
  static const _purple = Color(0xFFC678DD); // hue-3: keywords / storage

  // ── Borders & interactive states ──
  static const _border = Color(0xFF181A1F); // editor group, tab borders
  static const _borderLight = Color(0xFF3E4452); // panel border, focus border
  static const _selectionColor = Color(0x1F4D78CC); // accent @ 12 %
  static const _hoverColor = Color(0x08FFFFFF); // white @ 3 %
  static const _activeColor = Color(0x0FFFFFFF); // white @ 6 %

  // ── On-accent (text on accent-colored backgrounds) ──
  static const _onAccent = Color(0xFFF8FAFD); // badge fg

  // ── Scrollbar ──
  static const _scrollThumb = Color(0x667F848E); // fgDim @ 40 %

  // ── Terminal cursor & selection ──
  static const _termCursorColor = Color(
    0xFF528BFF,
  ); // OneDark Pro syntax-accent
  static const _termSelectionColor = Color(
    0x60677696,
  ); // OneDark Pro editor.selectionBackground

  // ── Terminal ANSI (OneDark Pro terminal.*) ──
  static const _termBlack = Color(0xFF3F4451);
  static const _termRed = Color(0xFFE05561);
  static const _termGreen = Color(0xFF8CC265);
  static const _termYellow = Color(0xFFD18F52);
  static const _termBlue = Color(0xFF4AA5F0);
  static const _termMagenta = Color(0xFFC162DE);
  static const _termCyan = Color(0xFF42B3C2);
  static const _termWhite = Color(0xFFD7DAE0);
  static const _termBrightBlack = Color(0xFF4F5666);
  static const _termBrightRed = Color(0xFFFF616E);
  static const _termBrightGreen = Color(0xFFA5E075);
  static const _termBrightYellow = Color(0xFFF0A45D);
  static const _termBrightBlue = Color(0xFF4DC4FF);
  static const _termBrightMagenta = Color(0xFFDE73FF);
  static const _termBrightCyan = Color(0xFF4CD1E0);
  static const _termBrightWhite = Color(0xFFE6E6E6);

  // ══════════════════════════════════════════════════════════════════
  //  LIGHT — Atom One Light (official)
  // ══════════════════════════════════════════════════════════════════

  // ── Backgrounds ──
  static const _lightBg = Color(0xFFFAFAFA); // level-2, editor
  static const _lightSurface = Color(0xFFEAEBEB); // level-3, sidebar
  static const _lightBg0 = Color(0xFFDBDBDC); // bg-selected, deepest
  static const _lightSelection = Color(0xFFE5E5E6); // syntax selection

  // ── Foregrounds ──
  static const _lightFg = Color(0xFF383A42); // mono-1
  static const _lightFgDim = Color(
    0xFF525660,
  ); // mono-2 (darkened for contrast)
  static const _lightFgFaint = Color(
    0xFF7C7E86,
  ); // mono-3 (darkened for contrast)
  static const _lightFgBright = Color(0xFF232424); // text-highlight

  // ── Accent & syntax hues ──
  static const _lightBlue = Color(0xFF4078F2); // hue-2
  static const _lightGreen = Color(0xFF50A14F); // hue-4
  static const _lightRed = Color(0xFFE45649); // hue-5
  static const _lightYellow = Color(0xFFC18401); // hue-6-2
  static const _lightOrange = Color(0xFF986801); // hue-6
  static const _lightCyan = Color(0xFF0184BC); // hue-1
  static const _lightPurple = Color(0xFFA626A4); // hue-3

  // ── Borders & interactive states ──
  static const _lightBorder = Color(0xFFDBDBDC); // ui-border
  static const _lightGutter = Color(
    0xFF6B6E76,
  ); // gutter text (darkened for contrast)

  // ── Level-1 surface (inputs, cards, popups — lightest bg) ──
  static const _lightLevel1 = Color(0xFFFFFFFF);

  // ── On-accent ──
  static const _lightOnAccent = Color(0xFFFFFFFF);

  // ── Terminal cursor & selection ──
  static const _lightTermCursorColor = Color(
    0xFF526FFF,
  ); // One Light syntax-accent
  static const _lightTermSelectionColor = Color(0x604078F2); // lightBlue @ 38 %

  // ── Scrollbar ──
  static const _lightScrollThumb = Color(0x88525660); // fgDim @ 53 %

  // ── Terminal ANSI (derived from One Light syntax palette) ──
  static const _lightTermBlack = Color(0xFF383A42);
  static const _lightTermRed = Color(0xFFE45649);
  static const _lightTermGreen = Color(0xFF50A14F);
  static const _lightTermYellow = Color(0xFFC18401);
  static const _lightTermBlue = Color(0xFF4078F2);
  static const _lightTermMagenta = Color(0xFFA626A4);
  static const _lightTermCyan = Color(0xFF0184BC);
  static const _lightTermWhite = Color(0xFFFAFAFA);
  static const _lightTermBrightBlack = Color(0xFF696C77);
  static const _lightTermBrightRed = Color(0xFFE45649);
  static const _lightTermBrightGreen = Color(0xFF50A14F);
  static const _lightTermBrightYellow = Color(0xFFC18401);
  static const _lightTermBrightBlue = Color(0xFF4078F2);
  static const _lightTermBrightMagenta = Color(0xFFA626A4);
  static const _lightTermBrightCyan = Color(0xFF0184BC);
  static const _lightTermBrightWhite = Color(0xFFFFFFFF);

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
  static Color get fg => isDark ? _fg : _lightFg;
  static Color get fgDim => isDark ? _fgDim : _lightFgDim;
  static Color get fgFaint => isDark ? _fgFaint : _lightFgFaint;
  static Color get fgBright => isDark ? _fgBright : _lightFgBright;

  // Accent & hues
  static Color get accent => isDark ? _accent : _lightBlue;
  static Color get blue => isDark ? _blue : _lightBlue;
  static Color get green => isDark ? _green : _lightGreen;
  static Color get red => isDark ? _red : _lightRed;
  static Color get yellow => isDark ? _yellow : _lightYellow;
  static Color get orange => isDark ? _orange : _lightOrange;
  static Color get cyan => isDark ? _cyan : _lightCyan;
  static Color get purple => isDark ? _purple : _lightPurple;

  // Borders & interactive
  static Color get border => isDark ? _border : _lightBorder;
  static Color get borderLight => isDark ? _borderLight : _lightBorder;
  static Color get selection =>
      isDark ? _selectionColor : const Color(0x2A4078F2);
  static Color get hover => isDark ? _hoverColor : const Color(0x12000000);
  static Color get active => isDark ? _activeColor : const Color(0x1A000000);

  /// Text color for accent-colored backgrounds (buttons, badges, toggles).
  static Color get onAccent => isDark ? _onAccent : _lightOnAccent;

  // ── Terminal ANSI colors ──
  static Color get termBlack => isDark ? _termBlack : _lightTermBlack;
  static Color get termRed => isDark ? _termRed : _lightTermRed;
  static Color get termGreen => isDark ? _termGreen : _lightTermGreen;
  static Color get termYellow => isDark ? _termYellow : _lightTermYellow;
  static Color get termBlue => isDark ? _termBlue : _lightTermBlue;
  static Color get termMagenta => isDark ? _termMagenta : _lightTermMagenta;
  static Color get termCyan => isDark ? _termCyan : _lightTermCyan;
  static Color get termWhite => isDark ? _termWhite : _lightTermWhite;
  static Color get termBrightBlack =>
      isDark ? _termBrightBlack : _lightTermBrightBlack;
  static Color get termBrightRed =>
      isDark ? _termBrightRed : _lightTermBrightRed;
  static Color get termBrightGreen =>
      isDark ? _termBrightGreen : _lightTermBrightGreen;
  static Color get termBrightYellow =>
      isDark ? _termBrightYellow : _lightTermBrightYellow;
  static Color get termBrightBlue =>
      isDark ? _termBrightBlue : _lightTermBrightBlue;
  static Color get termBrightMagenta =>
      isDark ? _termBrightMagenta : _lightTermBrightMagenta;
  static Color get termBrightCyan =>
      isDark ? _termBrightCyan : _lightTermBrightCyan;
  static Color get termBrightWhite =>
      isDark ? _termBrightWhite : _lightTermBrightWhite;

  /// Terminal block-cursor color (semi-transparent so text shows through).
  static Color get termCursor =>
      isDark ? _termCursorColor : _lightTermCursorColor;

  /// Terminal mouse-selection highlight.
  static Color get termSelection =>
      isDark ? _termSelectionColor : _lightTermSelectionColor;

  // ── Section border helpers ──
  // Brightness-aware single-side borders for container edges (headers,
  // footers, toolbars). Use in BoxDecoration.border.
  static BorderSide get borderSide => BorderSide(color: border);
  static Border get borderTop => Border(top: borderSide);
  static Border get borderBottom => Border(bottom: borderSide);

  // ── Bar height scale ──
  /// 34 px — standard bar: toolbars, headers, footers, status bars.
  static const double barHeightSm = 34;

  /// 40 px — dialog title bars, mobile breadcrumbs.
  static const double barHeightMd = 40;

  /// 44 px — mobile app bars, selection toolbars.
  static const double barHeightLg = 44;

  // ── Control height scale ──
  /// 26 px — compact buttons, file rows, settings items.
  static const double controlHeightXs = 26;

  /// 28 px — context menu items, search inputs, small buttons.
  static const double controlHeightSm = 28;

  /// 30 px — input fields, auth-type selectors.
  static const double controlHeightMd = 30;

  /// 32 px — tab selectors, mode selectors, mobile tab items.
  static const double controlHeightLg = 32;

  /// 38 px — dialog action buttons (Cancel, Connect, etc.).
  static const double controlHeightXl = 38;

  // ── Item height scale ──
  /// 22 px — compact rows: path editors, transfer detail items.
  static const double itemHeightXs = 22;

  /// 24 px — small items: resize handles, transfer list entries.
  static const double itemHeightSm = 24;

  /// 48 px — large containers: icon boxes, mobile list items, drag targets.
  static const double itemHeightLg = 48;

  /// 56 px — mobile bottom navigation bar.
  static const double itemHeightXl = 56;

  // ── Popup constraints ──
  /// 400 px — max height for popup menus (scrolls when content exceeds).
  static const double popupMaxHeight = 400;

  // ── Border radius scale ──
  /// 4 px — inputs, buttons, small elements.
  static const radiusSm = BorderRadius.all(Radius.circular(4));

  /// 6 px — cards, containers, default rounding.
  static const radiusMd = BorderRadius.all(Radius.circular(6));

  /// 8 px — toasts, mobile elements, larger containers.
  static const radiusLg = BorderRadius.all(Radius.circular(8));

  static ThemeData dark() => _buildTheme(
    scheme: const ColorScheme(
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
    ),
    extras: _ThemeExtras(
      popupColor: _bg1,
      inputFill: _bg3,
      borderColor: _borderLight,
      hintColor: _fgFaint,
      popupPadding: const EdgeInsets.symmetric(vertical: 4),
      inactiveTrack: _bg4,
      sliderOverlay: _selectionColor,
      tooltipBg: _bg0,
      tooltipFg: _fg,
      tooltipFontSize: AppFonts.xs,
      chipSelectedColor: _accent.withValues(alpha: 0.25),
      scrollThumb: _scrollThumb,
      snackBg: _bg3,
      snackFg: _fg,
    ),
  );

  static ThemeData light() => _buildTheme(
    scheme: const ColorScheme(
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
    ),
    extras: _ThemeExtras(
      popupColor: _lightLevel1,
      inputFill: _lightLevel1,
      borderColor: _lightBorder,
      hintColor: _lightGutter,
      popupPadding: null,
      inactiveTrack: _lightSelection,
      sliderOverlay: const Color(0x2A4078F2),
      tooltipBg: _lightFg,
      tooltipFg: _lightBg,
      tooltipFontSize: AppFonts.md,
      chipSelectedColor: _lightBlue.withValues(alpha: 0.2),
      scrollThumb: _lightScrollThumb,
      snackBg: _lightFg,
      snackFg: _lightBg,
    ),
  );

  /// Shared theme builder — all structural decisions live here.
  /// [scheme] carries the core Material color roles; [extras] covers
  /// colors that don't map cleanly to any scheme role.
  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required _ThemeExtras extras,
  }) {
    final popupColor = extras.popupColor;
    final inputFill = extras.inputFill;
    final borderColor = extras.borderColor;
    final hintColor = extras.hintColor;
    final popupPadding = extras.popupPadding;
    final inactiveTrack = extras.inactiveTrack;
    final sliderOverlay = extras.sliderOverlay;
    final tooltipBg = extras.tooltipBg;
    final tooltipFg = extras.tooltipFg;
    final tooltipFontSize = extras.tooltipFontSize;
    final chipSelectedColor = extras.chipSelectedColor;
    final scrollThumb = extras.scrollThumb;
    final snackBg = extras.snackBg;
    final snackFg = extras.snackFg;
    final accent = scheme.primary;
    final onAccent = scheme.onPrimary;
    final fg = scheme.onSurface;
    final surface = scheme.surface;
    final surfaceLow = scheme.surfaceContainerLow;
    final fgDim = scheme.onSurfaceVariant;
    final divider = scheme.outline;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      dividerColor: divider,
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
      dividerTheme: DividerThemeData(color: divider, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLow,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: popupColor,
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: borderColor),
        ),
        menuPadding: popupPadding,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: radiusSm,
          side: BorderSide(color: borderColor),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.lg,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.sm,
          color: fg,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.3),
        selectionHandleColor: accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        // Global opt-out of Material's floating label animation — the label
        // stays in place instead of sliding up to the top border on focus.
        // Our dialogs treat labels as field titles, so the movement is noisy.
        floatingLabelBehavior: FloatingLabelBehavior.never,
        border: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSm,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: hintColor),
        labelStyle: TextStyle(color: fgDim),
      ),
      iconTheme: IconThemeData(color: fg, size: 20),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: fg),
        bodyMedium: TextStyle(color: fg),
        bodySmall: TextStyle(color: fgDim),
        titleSmall: TextStyle(color: accent),
      ).apply(fontFamily: 'Inter'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: borderColor),
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return inputFill;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onAccent;
            return fg;
          }),
          side: WidgetStateProperty.all(BorderSide(color: borderColor)),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: radiusSm),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: ListTileThemeData(iconColor: fg, textColor: fg),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLow,
        indicatorColor: accent.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent);
          }
          return IconThemeData(color: fgDim);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: accent, fontSize: AppFonts.md);
          }
          return TextStyle(color: fgDim, fontSize: AppFonts.md);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: inactiveTrack,
        overlayColor: sliderOverlay,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: tooltipBg,
          border: Border.all(color: borderColor),
          borderRadius: radiusSm,
        ),
        textStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: tooltipFontSize,
          color: tooltipFg,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inputFill,
        selectedColor: chipSelectedColor,
        labelStyle: TextStyle(color: fg),
        secondaryLabelStyle: TextStyle(color: accent),
        side: BorderSide(color: divider),
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        deleteIconColor: fgDim,
        checkmarkColor: accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(scrollThumb),
        radius: Radius.zero,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        side: BorderSide(color: fgDim),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onAccent),
      ),
      cardTheme: CardThemeData(
        color: inputFill,
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snackBg,
        contentTextStyle: TextStyle(color: snackFg),
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: inactiveTrack,
      ),
    );
  }

  // ── Semantic colors (brightness-aware) ──

  /// Green — connected, success.
  static Color get connected => isDark ? _green : _lightGreen;

  /// Yellow/orange — connecting, warning.
  static Color get connecting => isDark ? _yellow : _lightYellow;

  /// Red — disconnected, error.
  static Color get disconnected => isDark ? _red : _lightRed;

  /// Cyan — info, accents.
  static Color get info => isDark ? _cyan : _lightCyan;

  /// Folder icon color.
  static Color get folderIcon => isDark ? _yellow : _lightYellow;

  /// Terminal search highlight backgrounds.
  static const Color _searchHighlightDark = Color(0xFFFFFF2B);
  static const Color _searchHighlightLight = Color(0xFFFFD700);
  static Color get searchHighlight =>
      isDark ? _searchHighlightDark : _searchHighlightLight;

  /// Terminal search hit foreground — high-contrast text on colored bg.
  static Color get searchHitFg => isDark ? _termBrightWhite : _lightFgBright;

  /// Shared terminal color theme for xterm views.
  static TerminalTheme get terminalTheme => TerminalTheme(
    cursor: termCursor,
    selection: termSelection,
    foreground: fg,
    background: bg2,
    black: termBlack,
    red: termRed,
    green: termGreen,
    yellow: termYellow,
    blue: termBlue,
    magenta: termMagenta,
    cyan: termCyan,
    white: termWhite,
    brightBlack: termBrightBlack,
    brightRed: termBrightRed,
    brightGreen: termBrightGreen,
    brightYellow: termBrightYellow,
    brightBlue: termBrightBlue,
    brightMagenta: termBrightMagenta,
    brightCyan: termBrightCyan,
    brightWhite: termBrightWhite,
    searchHitBackground: accent.withValues(alpha: 0.3),
    searchHitBackgroundCurrent: accent,
    searchHitForeground: searchHitFg,
  );

  /// Standard input decoration used across dialogs.
  ///
  /// Provides consistent filled input styling with themed borders.
  /// Pass [labelText], [hintText], or [hintStyle] to customize per-use.
  static InputDecoration inputDecoration({
    String? labelText,
    String? hintText,
    TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 10,
    ),
  }) {
    final normalBorder = OutlineInputBorder(
      borderRadius: radiusSm,
      borderSide: BorderSide(color: borderLight),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: TextStyle(color: fgFaint),
      hintStyle: hintStyle ?? TextStyle(color: fgFaint),
      // Keep the label where the user placed it — don't animate it up into
      // the top border when the field gets focus or text. Material's float
      // is noisy here since labels double as field titles and sit outside
      // the box in most of our dialogs.
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: bg3,
      isDense: true,
      contentPadding: contentPadding,
      border: normalBorder,
      enabledBorder: normalBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusSm,
        borderSide: BorderSide(color: accent),
      ),
    );
  }
}

/// Colors that don't map to a [ColorScheme] role, passed to [AppTheme._buildTheme].
class _ThemeExtras {
  final Color popupColor;
  final Color inputFill;
  final Color borderColor;
  final Color hintColor;
  final EdgeInsetsGeometry? popupPadding;
  final Color inactiveTrack;
  final Color sliderOverlay;
  final Color tooltipBg;
  final Color tooltipFg;
  final double tooltipFontSize;
  final Color chipSelectedColor;
  final Color scrollThumb;
  final Color snackBg;
  final Color snackFg;

  const _ThemeExtras({
    required this.popupColor,
    required this.inputFill,
    required this.borderColor,
    required this.hintColor,
    required this.popupPadding,
    required this.inactiveTrack,
    required this.sliderOverlay,
    required this.tooltipBg,
    required this.tooltipFg,
    required this.tooltipFontSize,
    required this.chipSelectedColor,
    required this.scrollThumb,
    required this.snackBg,
    required this.snackFg,
  });
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
  }) => TextStyle(
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
  }) => TextStyle(
    fontFamily: _mono,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}
