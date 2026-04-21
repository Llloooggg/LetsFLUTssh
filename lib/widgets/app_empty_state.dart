import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Standardised empty-state panel for collection dialogs + list
/// screens (snippet manager, key manager, tag manager, session
/// picker, etc.).
///
/// Every caller previously rolled its own `Center(child: Text(...))`
/// with slightly different padding / alignment rules, which meant:
///
///  * on mobile with long-locale strings (Russian / German) the text
///    wrapped but stayed left-aligned because the inner `Text` did
///    not set `textAlign`, and the resulting visual looked like the
///    text was glued to the left edge;
///  * horizontal padding was inconsistent between dialogs — some
///    had 24 px gutters, others 0, so the rendered label sat at
///    different positions relative to the surrounding toolbar;
///  * no shared hook for adding an "optional illustration" / CTA
///    later without touching every caller.
///
/// This widget owns the alignment + padding + typography contract so
/// every empty state renders identically. Callers pass only the
/// localised message and, optionally, a leading [icon] or trailing
/// [action] slot. Both optional slots render with the same centered +
/// horizontally-padded layout.
class AppEmptyState extends StatelessWidget {
  /// The empty-state copy, already localised. Expected to be a short
  /// sentence (one or two lines on mobile). Text wraps on overflow.
  final String message;

  /// Optional leading icon rendered above the message in `fgDim`.
  /// Use sparingly — dialogs that already carry a title icon in the
  /// header do not need another one here.
  final IconData? icon;

  /// Optional trailing widget (usually a `TextButton`) rendered
  /// below the message. Callers own the localisation + tap handler.
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // Gutter mirrors the 24 px `AppDialog` content padding so the
        // text column width matches the rest of the modal. On very
        // narrow mobile dialogs this still leaves room for a 2-line
        // message before the system font scales it down.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: AppTheme.fgDim),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
