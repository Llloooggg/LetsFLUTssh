import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'hover_region.dart';

// ════════════════════════════════════════════════════════════════════
//  AppDialog — unified dialog shell
// ════════════════════════════════════════════════════════════════════

/// Standard dialog matching the app's visual language.
///
/// Provides:
/// * Dark background (`AppTheme.bg1`)
/// * Header bar with title and close button
/// * Scrollable content area
/// * Footer bar with action buttons
///
/// For complex dialogs (e.g. with tabs between header and content),
/// compose from [AppDialogHeader], [AppDialogFooter], and
/// [AppDialogAction] directly instead.
class AppDialog extends StatelessWidget {
  final String title;
  final double maxWidth;
  final Widget content;
  final List<Widget> actions;
  final EdgeInsets contentPadding;
  final bool scrollable;
  final bool dismissible;

  const AppDialog({
    super.key,
    required this.title,
    this.maxWidth = 460,
    required this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.all(16),
    this.scrollable = true,
    this.dismissible = true,
  });

  /// Convenience: show this dialog with standard options.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      animationStyle: AnimationStyle.noAnimation,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(padding: contentPadding, child: content);
    if (scrollable) {
      body = Flexible(child: SingleChildScrollView(child: body));
    }

    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogHeader(
              title: title,
              onClose: dismissible ? () => Navigator.of(context).pop() : null,
            ),
            body,
            if (actions.isNotEmpty) AppDialogFooter(actions: actions),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppDialogHeader
// ════════════════════════════════════════════════════════════════════

/// Header bar for dialogs: title on the left, close button on the right.
class AppDialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;

  const AppDialogHeader({super.key, required this.title, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.barHeightMd,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: AppTheme.borderBottom),
      child: Row(
        children: [
          Text(
            title,
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
          ),
          const Spacer(),
          if (onClose != null)
            AppIconButton(
              icon: Icons.close,
              onTap: onClose!,
              size: 13,
              boxSize: 22,
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppDialogFooter
// ════════════════════════════════════════════════════════════════════

/// Footer bar for dialogs: action buttons aligned to the right.
class AppDialogFooter extends StatelessWidget {
  final List<Widget> actions;

  const AppDialogFooter({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppTheme.barHeightMd),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(border: AppTheme.borderTop),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 6,
        children: actions,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppDialogAction — button for dialog footers
// ════════════════════════════════════════════════════════════════════

/// A compact button matching the session-edit dialog style.
///
/// Variants:
/// * **text** — no background, dim text (e.g. Cancel)
/// * **filled** — colored background (e.g. Save, Connect)
/// * **destructive** — red background (e.g. Delete)
class AppDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final bool enabled;

  const AppDialogAction({
    super.key,
    required this.label,
    this.onTap,
    this.background,
    this.foreground,
    this.enabled = true,
  });

  /// Cancel / dismiss button — no background, dim text.
  const factory AppDialogAction.cancel({Key? key, VoidCallback? onTap}) =
      _CancelAction;

  /// Primary action — accent background.
  factory AppDialogAction.primary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
  }) = _PrimaryAction;

  /// Secondary action — subtle background.
  factory AppDialogAction.secondary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
  }) = _SecondaryAction;

  /// Destructive action — red background.
  factory AppDialogAction.destructive({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
  }) = _DestructiveAction;

  @override
  Widget build(BuildContext context) {
    final hasBg = background != null;
    final effectiveBg = enabled ? background : AppTheme.bg4;
    final defaultFg = hasBg ? AppTheme.onAccent : AppTheme.fgDim;
    final effectiveFg = enabled ? (foreground ?? defaultFg) : AppTheme.fgFaint;

    return HoverRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onTap : null,
      builder: (hovered) => Container(
        height: AppTheme.controlHeightXs,
        padding: EdgeInsets.symmetric(horizontal: hasBg ? 16 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _buttonColor(hasBg, hovered, effectiveBg),
        ),
        child: Text(
          label,
          style: AppFonts.inter(
            fontSize: AppFonts.sm,
            fontWeight: hasBg ? FontWeight.w500 : null,
            color: effectiveFg,
          ),
        ),
      ),
    );
  }

  Color? _buttonColor(bool hasBg, bool hovered, Color? effectiveBg) {
    final isHoverActive = hovered && enabled;
    if (hasBg) {
      return isHoverActive ? _lighten(effectiveBg!) : effectiveBg;
    }
    return isHoverActive ? AppTheme.hover : null;
  }

  static Color _lighten(Color c) =>
      Color.lerp(c, const Color(0xFFFFFFFF), 0.08)!;
}

class _CancelAction extends AppDialogAction {
  const _CancelAction({super.key, super.onTap})
    : super(label: 'Cancel', enabled: true);
}

class _PrimaryAction extends AppDialogAction {
  _PrimaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.accent, foreground: AppTheme.onAccent);
}

class _SecondaryAction extends AppDialogAction {
  _SecondaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.bg4, foreground: AppTheme.fg);
}

class _DestructiveAction extends AppDialogAction {
  _DestructiveAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.disconnected, foreground: AppTheme.onAccent);
}

// ════════════════════════════════════════════════════════════════════
//  AppProgressDialog — non-dismissible loading spinner
// ════════════════════════════════════════════════════════════════════

/// Full-screen loading overlay with a centered spinner.
///
/// Non-dismissible — caller must pop it explicitly.
class AppProgressDialog extends StatelessWidget {
  const AppProgressDialog({super.key});

  /// Show a non-dismissible progress dialog and return its context
  /// so the caller can pop it later.
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const AppProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
