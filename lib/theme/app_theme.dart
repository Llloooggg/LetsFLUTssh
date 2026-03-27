import 'package:flutter/material.dart';

/// OneDark-inspired color palette for the app.
///
/// Dark theme: Atom OneDark Pro colors.
/// Light theme: Atom One Light colors.
abstract final class AppTheme {
  // ── OneDark palette ──
  static const _bg = Color(0xFF282C34);
  static const _fg = Color(0xFFABB2BF);
  static const _blue = Color(0xFF61AFEF);
  static const _green = Color(0xFF98C379);
  static const _red = Color(0xFFE06C75);
  static const _yellow = Color(0xFFE5C07B);
  static const _cyan = Color(0xFF56B6C2);
  static const _purple = Color(0xFFC678DD);
  static const _gutter = Color(0xFF636D83);
  static const _selection = Color(0xFF3E4451);
  static const _cursorLine = Color(0xFF2C313A);
  static const _border = Color(0xFF3B4048);
  static const _darker = Color(0xFF21252B);
  static const _darkest = Color(0xFF1E2127);

  // ── One Light palette ──
  static const _lightBg = Color(0xFFFAFAFA);
  static const _lightFg = Color(0xFF383A42);
  static const _lightBlue = Color(0xFF4078F2);
  static const _lightGreen = Color(0xFF50A14F);
  static const _lightRed = Color(0xFFE45649);
  static const _lightYellow = Color(0xFFC18401);
  static const _lightPurple = Color(0xFFA626A4);
  static const _lightGutter = Color(0xFF9D9D9F);
  static const _lightSelection = Color(0xFFE5E5E6);
  static const _lightBorder = Color(0xFFD3D3D3);
  static const _lightSurface = Color(0xFFF0F0F0);

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _blue,
      onPrimary: _bg,
      primaryContainer: Color(0xFF2E4A6E),
      onPrimaryContainer: _blue,
      secondary: _green,
      onSecondary: _bg,
      secondaryContainer: Color(0xFF3A5028),
      onSecondaryContainer: _green,
      tertiary: _purple,
      onTertiary: _bg,
      tertiaryContainer: Color(0xFF5C3566),
      onTertiaryContainer: _purple,
      error: _red,
      onError: _bg,
      errorContainer: Color(0xFF6E2B30),
      onErrorContainer: _red,
      surface: _bg,
      onSurface: _fg,
      surfaceContainerLowest: _darkest,
      surfaceContainerLow: _darker,
      surfaceContainer: _bg,
      surfaceContainerHigh: _cursorLine,
      surfaceContainerHighest: _selection,
      onSurfaceVariant: _gutter,
      outline: _border,
      outlineVariant: _cursorLine,
      inverseSurface: _fg,
      onInverseSurface: _bg,
      inversePrimary: Color(0xFF3A6BA0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
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
        backgroundColor: _darker,
        foregroundColor: _fg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _darker,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darker,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
        hintStyle: const TextStyle(color: _gutter),
        labelStyle: const TextStyle(color: _gutter),
      ),
      iconTheme: const IconThemeData(color: _fg, size: 20),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _fg),
        bodyMedium: TextStyle(color: _fg),
        bodySmall: TextStyle(color: _gutter),
        titleSmall: TextStyle(color: _blue),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _fg,
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _blue),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _blue;
            return _darker;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return _bg;
            return _fg;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: _border)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _fg,
        textColor: _fg,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: _blue,
        thumbColor: _blue,
        inactiveTrackColor: _selection,
        overlayColor: Color(0x2261AFEF),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: _darker,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _border),
        ),
        textStyle: const TextStyle(color: _fg, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x66636D83)),
        radius: const Radius.circular(4),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _blue,
        linearTrackColor: _selection,
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
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _lightBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _lightBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _lightBlue, width: 1.5),
        ),
        hintStyle: const TextStyle(color: _lightGutter),
        labelStyle: const TextStyle(color: _lightGutter),
      ),
      iconTheme: const IconThemeData(color: _lightFg, size: 20),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _lightFg),
        bodyMedium: TextStyle(color: _lightFg),
        bodySmall: TextStyle(color: _lightGutter),
        titleSmall: TextStyle(color: _lightBlue),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lightBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightFg,
          side: const BorderSide(color: _lightBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _lightBlue),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _lightFg,
        textColor: _lightFg,
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
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _lightBorder),
        ),
        textStyle: const TextStyle(color: _lightBg, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x669D9D9F)),
        radius: const Radius.circular(4),
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
