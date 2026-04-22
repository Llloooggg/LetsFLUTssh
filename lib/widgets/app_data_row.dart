import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared row for list / table style dialogs (snippets, tags, known
/// hosts, session list). Enforces consistent vertical height, paddings,
/// icon size, and font tokens so a dialog with single-line entries
/// (tags, hosts) doesn't visibly shrink against a dialog with
/// multi-line entries (snippets). The canonical 3-field snippet row
/// defined the ceiling, and every row — regardless of how many lines
/// the caller supplies — is rendered at least [minHeight] tall with
/// its content vertically centered.
///
/// Layout:
/// * [leading] (custom widget, e.g. a color swatch) *or* [icon] with
///   [iconColor], sized at [iconSize].
/// * Then [title] (primary text, `AppFonts.sm`) above an optional
///   [secondary] line (`AppFonts.xs`, `fgDim`, optionally mono-font
///   for shell commands) and an optional [tertiary] line
///   (`AppFonts.xs`, `fgFaint`).
/// * Trailing action widgets (icon buttons, chevrons) pinned to the
///   right.
///
/// The whole row is tappable when [onTap] is supplied. A hover
/// highlight is drawn via the ambient [InkWell] so selection UX
/// matches what the file browser already does.
class AppDataRow extends StatelessWidget {
  /// 8 vpad + ~3 lines of AppFonts text + inner gaps ≈ 64 — large
  /// enough to absorb a 3-field snippet without clipping while still
  /// being dense enough for a hosts list.
  static const double minHeight = 64;

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  static const double iconSize = 16;
  static const double iconGap = 10;
  static const double trailingGap = 4;

  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String title;
  final String? secondary;
  final bool secondaryMono;
  final String? tertiary;
  final List<Widget> trailing;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final String? tooltip;

  const AppDataRow({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.leading,
    this.secondary,
    this.secondaryMono = false,
    this.tertiary,
    this.trailing = const [],
    this.onTap,
    this.onDoubleTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            _buildLeading(),
            if (leading != null || icon != null) const SizedBox(width: iconGap),
            Expanded(child: _buildTextColumn()),
            for (final w in trailing) ...[
              const SizedBox(width: trailingGap),
              w,
            ],
          ],
        ),
      ),
    );
    if (tooltip != null) body = Tooltip(message: tooltip!, child: body);
    if (onTap != null || onDoubleTap != null) {
      // Clickable row — opt out of any ambient `SelectionArea`. Same
      // rule the `_ActionTile` / `HoverRegion` stack applies: when the
      // whole row dispatches on tap, neither the I-beam cursor nor
      // drag-select belong here.
      body = InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: SelectionContainer.disabled(child: body),
      );
    }
    return body;
  }

  Widget _buildLeading() {
    if (leading != null) return leading!;
    if (icon != null) {
      return Icon(icon, size: iconSize, color: iconColor ?? AppTheme.accent);
    }
    return const SizedBox.shrink();
  }

  Widget _buildTextColumn() {
    final children = <Widget>[
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.inter(
          fontSize: AppFonts.sm,
          color: AppTheme.fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    ];
    if (secondary != null && secondary!.isNotEmpty) {
      children.add(const SizedBox(height: 2));
      children.add(
        Text(
          secondary!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secondaryMono
              ? AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgDim)
              : AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
      );
    }
    if (tertiary != null && tertiary!.isNotEmpty) {
      children.add(const SizedBox(height: 2));
      children.add(
        Text(
          tertiary!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
