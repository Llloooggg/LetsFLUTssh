import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Horizontal divider for separating groups of items in lists, menus,
/// and dialogs.
///
/// Standardises height (1 px), thickness (1 px), and color
/// ([AppTheme.border]) so every separator in the app looks the same.
///
/// ```dart
/// // Full-width (default)
/// const AppDivider()
///
/// // Indented — for grouping items in context menus
/// const AppDivider.indented()
/// ```
class AppDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final Color? color;

  const AppDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  });

  /// Indented divider (8 px each side) for grouping items in menus.
  const AppDivider.indented({super.key, this.color})
    : indent = 8,
      endIndent = 8;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    endIndent: endIndent,
    color: color ?? AppTheme.border,
  );
}
