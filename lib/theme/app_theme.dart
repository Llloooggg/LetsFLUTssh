import 'package:flutter/material.dart';

/// OneDark-inspired color palette for the app.
///
/// Dark theme: Atom OneDark Pro colors with indigo accent.
/// Light theme: Atom One Light colors.
abstract final class AppTheme {
  // ── Dark palette (private) ──
  static const _bg0 = Color(0xFF1B1D23); // toolbar, status bar, drag handles
  static const _bg1 = Color(0xFF1E2127); // sidebar, dialogs, app bar
  static const _bg2 = Color(0xFF282C34); // main content area
  static const _bg3 = Color(0xFF2C313A); // inputs, rows, badges
  static const _bg4 = Color(0xFF333842); // toggle-off, hover on bg3

  static const _fg      = Color(0xFFABB2BF);
  static const _fgDim   = Color(0xFF7F848E);
  static const _fgFaint = Color(0xFF5C6370);
  static const _fgBright = Color(0xFFCDD3DE);

  static const _accent = Color(0xFF4D78CC);
  static const _blue   = Color(0xFF61AFEF);
  static const _green  = Color(0xFF98C379);
  static const _red    = Color(0xFFE06C75);
  static const _yellow = Color(0xFFE5C07B);
  static const _orange = Color(0xFFD19A66);
  static const _cyan   = Color(0xFF56B6C2);
  static const _purple = Color(0xFFC678DD);

  static const _border      = Color(0xFF1B1D23); // = bg0, main dividers
  static const _borderLight = Color(0xFF2C313A); // = bg3, inputs, cards
  static const _selectionColor = Color(0x1F4D78CC); // rgba(77,120,204,0.12)
  static const _hoverColor     = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
  static const _activeColor    = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)

  // ── One Light palette (private) ──
  static const _lightBg        = Color(0xFFFAFAFA);
  static const _lightFg        = Color(0xFF383A42);
  static const _lightBlue      = Color(0xFF4078F2);
  static const _lightGreen     = Color(0xFF50A14F);
  static const _lightRed       = Color(0xFFE45649);
  static const _lightYellow    = Color(0xFFC18401);
  static const _lightPurple    = Color(0xFFA626A4);
  static const _lightGutter    = Color(0xFF9D9D9F);
  static const _lightSelection = Color(0xFFE5E5E6);
  static const _lightBorder    = Color(0xFFD3D3D3);
  static const _lightSurface   = Color(0xFFF0F0F0);

  // ── Brightness-aware state ──
  // Set by the app root widget when the theme mode changes.
  static Brightness _brightness = Brightness.dark;

  /// Call from the app root to sync with the current theme brightness.
  static void setBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get isDark => _brightness == Brightness.dark;

  // ── Public brightness-aware colors ──
  static Color get bg0 => isDark ? _bg0 : const Color(0xFFE8E8E8);
  static Color get bg1 => isDark ? _bg1 : _lightSurface;
  static Color get bg2 => isDark ? _bg2 : _lightBg;
  static Color get bg3 => isDark ? _bg3 : _lightSelection;
  static Color get bg4 => isDark ? _bg4 : _lightBorder;

  static Color get fg       => isDark ? _fg : _lightFg;
  static Color get fgDim    => isDark ? _fgDim : _lightGutter;
  static Color get fgFaint  => isDark ? _fgFaint : const Color(0xFFB0B0B4);
  static Color get fgBright => isDark ? _fgBright : const Color(0xFF232529);

  static Color get accent => isDark ? _accent : _lightBlue;
  static Color get blue   => isDark ? _blue : _lightBlue;
  static Color get green  => isDark ? _green : _lightGreen;
  static Color get red    => isDark ? _red : _lightRed;
  static Color get yellow => isDark ? _yellow : _lightYellow;
  static Color get orange => isDark ? _orange : const Color(0xFFA06B2C);
  static Color get cyan   => isDark ? _cyan : const Color(0xFF0184BC);
  static Color get purple => isDark ? _purple : _lightPurple;

  static Color get border      => isDark ? _border : _lightBorder;
  static Color get borderLight => isDark ? _borderLight : _lightSelection;
  static Color get selection   => isDark ? _selectionColor : const Color(0x1F4078F2);
  static Color get hover       => isDark ? _hoverColor : const Color(0x08000000);
  static Color get active      => isDark ? _activeColor : const Color(0x0F000000);

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _accent,
      onPrimary: Colors.white,
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
          side: BorderSide(color: _borderLight),
        ),
        menuPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: _bg2,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _borderLight),
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
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
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
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _fg,
          side: const BorderSide(color: _borderLight),
          shape: const RoundedRectangleBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _accent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _accent;
            return _bg3;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return _fg;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _borderLight)),
          shape: WidgetStateProperty.all(const RoundedRectangleBorder()),
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
            return const TextStyle(color: _accent, fontSize: 12);
          }
          return const TextStyle(color: _fgDim, fontSize: 12);
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
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          color: _fg,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _bg3,
        selectedColor: _accent.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: _fg),
        secondaryLabelStyle: const TextStyle(color: _accent),
        side: const BorderSide(color: _border),
        shape: const RoundedRectangleBorder(),
        deleteIconColor: _fgDim,
        checkmarkColor: _accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x667F848E)),
        radius: Radius.zero,
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
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD4E4FF),
      onPrimaryContainer: _lightBlue,
      secondary: _lightGreen,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD4F0D4),
      onSecondaryContainer: _lightGreen,
      tertiary: _lightPurple,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF0D4F0),
      onTertiaryContainer: _lightPurple,
      error: _lightRed,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: _lightRed,
      surface: _lightBg,
      onSurface: _lightFg,
      surfaceContainerLowest: Colors.white,
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
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _lightBorder),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: _lightBg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _lightBorder),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _lightBlue,
        selectionColor: _lightBlue.withValues(alpha: 0.3),
        selectionHandleColor: _lightBlue,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
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
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightFg,
          side: const BorderSide(color: _lightBorder),
          shape: const RoundedRectangleBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _lightBlue),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightBlue,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _lightBlue;
            return Colors.white;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return _lightFg;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _lightBorder)),
          shape: WidgetStateProperty.all(const RoundedRectangleBorder()),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _lightFg,
        textColor: _lightFg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: _lightBlue.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _lightBlue);
          }
          return const IconThemeData(color: _lightGutter);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: _lightBlue, fontSize: 12);
          }
          return const TextStyle(color: _lightGutter, fontSize: 12);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: _lightBlue,
        thumbColor: _lightBlue,
        inactiveTrackColor: _lightSelection,
        overlayColor: Color(0x224078F2),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: _lightFg,
          border: Border.all(color: _lightBorder),
        ),
        textStyle: const TextStyle(color: _lightBg, fontSize: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: _lightBlue.withValues(alpha: 0.15),
        labelStyle: const TextStyle(color: _lightFg),
        secondaryLabelStyle: const TextStyle(color: _lightBlue),
        side: const BorderSide(color: _lightBorder),
        shape: const RoundedRectangleBorder(),
        deleteIconColor: _lightGutter,
        checkmarkColor: _lightBlue,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x669D9D9F)),
        radius: Radius.zero,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lightBlue,
        linearTrackColor: _lightSelection,
      ),
    );
  }

  // ── Semantic colors for use across the app ──

  /// OneDark green — connected, success.
  static const Color connected = _green;

  /// OneDark yellow/orange — connecting, warning.
  static const Color connecting = _yellow;

  /// OneDark red — disconnected, error.
  static const Color disconnected = _red;

  /// OneDark cyan — info, accents.
  static const Color info = _cyan;

  /// Folder icon color.
  static const Color folderIcon = _yellow;

  /// Terminal search highlight.
  static const Color searchHighlight = Color(0xFFFFFF2B);
  static const Color searchHighlightLight = Color(0xFFFFD700);

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
abstract final class AppFonts {
  static const _inter = 'Inter';
  static const _mono = 'JetBrains Mono';

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
