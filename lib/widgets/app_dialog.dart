import 'package:flutter/material.dart';

import '../core/shortcut_registry.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/platform.dart';
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

    Widget child = ConstrainedBox(
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
    );

    if (dismissible) {
      child = CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
        }),
        child: Focus(autofocus: true, child: child),
      );
    }

    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      child: child,
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
///
/// Desktop: horizontal [Row] with [Flexible] children — buttons shrink
/// proportionally instead of wrapping to a second line.
/// Mobile: vertical [Column] with full-width buttons in reversed order
/// (primary action on top, cancel at bottom).
class AppDialogFooter extends StatelessWidget {
  final List<Widget> actions;

  const AppDialogFooter({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobilePlatform;
    return Container(
      constraints: const BoxConstraints(minHeight: AppTheme.barHeightMd),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: mobile ? 12 : 7),
      decoration: BoxDecoration(border: AppTheme.borderTop),
      child: mobile ? _mobileLayout() : _desktopLayout(),
    );
  }

  Widget _desktopLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: _intersperse(
        const SizedBox(width: 8),
        actions.map((a) => Flexible(child: a)).toList(),
      ),
    );
  }

  Widget _mobileLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _intersperse(
        const SizedBox(height: 8),
        actions.reversed
            .map((a) => SizedBox(width: double.infinity, child: a))
            .toList(),
      ),
    );
  }

  static List<Widget> _intersperse(Widget spacer, List<Widget> items) {
    return [
      for (int i = 0; i < items.length; i++) ...[if (i > 0) spacer, items[i]],
    ];
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
    final mobile = isMobilePlatform;
    final hasBg = background != null;
    final effectiveBg = enabled ? background : AppTheme.bg4;
    final defaultFg = hasBg ? AppTheme.onAccent : AppTheme.fgDim;
    final effectiveFg = enabled ? (foreground ?? defaultFg) : AppTheme.fgFaint;

    final height = mobile ? AppTheme.barHeightLg : AppTheme.controlHeightXs;
    final hPad = _horizontalPadding(mobile: mobile, hasBg: hasBg);
    final fontSize = mobile ? AppFonts.md : AppFonts.sm;
    final radius = mobile ? AppTheme.radiusMd : BorderRadius.zero;

    return HoverRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onTap : null,
      builder: (hovered) => Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _buttonColor(hasBg, hovered, effectiveBg),
          borderRadius: radius,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: AppFonts.inter(
              fontSize: fontSize,
              fontWeight: hasBg ? FontWeight.w500 : null,
              color: effectiveFg,
            ),
          ),
        ),
      ),
    );
  }

  static double _horizontalPadding({
    required bool mobile,
    required bool hasBg,
  }) {
    if (mobile) return hasBg ? 20.0 : 16.0;
    return hasBg ? 16.0 : 12.0;
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
    : super(label: '', enabled: true);

  @override
  Widget build(BuildContext context) {
    return _CancelActionResolved(label: S.of(context).cancel, onTap: onTap);
  }
}

class _CancelActionResolved extends AppDialogAction {
  const _CancelActionResolved({required super.label, super.onTap})
    : super(enabled: true);
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
