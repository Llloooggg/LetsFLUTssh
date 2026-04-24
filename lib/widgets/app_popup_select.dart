import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One option in an [AppPopupSelect]. [label] renders as the primary
/// text; [secondary] (optional) renders dim + right-aligned (used by
/// the language picker for English-name transliterations like
/// `Русский / Russian`).
class AppPopupSelectOption<T> {
  final T value;
  final String label;
  final String? secondary;

  const AppPopupSelectOption({
    required this.value,
    required this.label,
    this.secondary,
  });
}

/// Shared dropdown-style picker matching the language-selector look:
/// compact trigger with a leading icon + current label + down-arrow
/// that opens a `PopupMenuButton` with themed items.
///
/// Replaces ad-hoc `DropdownButton` / one-off `PopupMenuButton`
/// wrappers across settings surfaces so every picker reads the same
/// — same `bg3` fill, same `radiusSm`, same `bg2` menu background,
/// same `noAnimation` open behaviour the project-wide hard-off
/// requires.
///
/// The trigger is intentionally short (`controlHeightSm`) to fit
/// inside tight settings rows; host widgets are responsible for the
/// label + subtitle column to the left.
class AppPopupSelect<T> extends StatelessWidget {
  final T value;
  final List<AppPopupSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? leadingIcon;

  /// Max width of the popup. Defaults to 240 — wide enough for long
  /// native locale names like `Bahasa Indonesia` without wrapping.
  final double menuMinWidth;

  const AppPopupSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leadingIcon,
    this.menuMinWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere(
      (o) => o.value == value,
      orElse: () => options.first,
    );

    return PopupMenuButton<T>(
      onSelected: onChanged,
      tooltip: '',
      // `PopupMenuButton` owns its own `AnimationController` and
      // ignores the root `MediaQuery(disableAnimations: true)` —
      // opt out explicitly so the open matches the project-wide
      // hard-off and no element of the UI fades / scales.
      popUpAnimationStyle: AnimationStyle.noAnimation,
      offset: const Offset(0, AppTheme.controlHeightSm),
      constraints: BoxConstraints(
        minWidth: menuMinWidth,
        maxHeight: AppTheme.popupMaxHeight,
      ),
      color: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
      itemBuilder: (_) => options
          .map(
            (opt) => PopupMenuItem<T>(
              value: opt.value,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: AppFonts.sm,
                        color: opt.value == value
                            ? AppTheme.accent
                            : AppTheme.fg,
                      ),
                    ),
                  ),
                  if (opt.secondary != null && opt.secondary!.isNotEmpty)
                    Text(
                      opt.secondary!,
                      style: AppFonts.inter(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        height: AppTheme.controlHeightSm,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 16, color: AppTheme.fgDim),
              const SizedBox(width: 6),
            ],
            // Flexible + ellipsis so a long locale / level name shrinks
            // instead of overflowing the parent row by fractional
            // pixels (RenderFlex "overflowed by 5.2 px" on tight
            // settings columns).
            Flexible(
              child: Text(
                current.label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgDim),
          ],
        ),
      ),
    );
  }
}
