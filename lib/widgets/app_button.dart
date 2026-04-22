import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/platform.dart';
import 'hover_region.dart';

// ════════════════════════════════════════════════════════════════════
//  AppButton — app-wide themed button
// ════════════════════════════════════════════════════════════════════

/// A compact button matching the app's visual language.
///
/// Used anywhere in the UI that needs a themed button: dialog
/// footers, settings rows, toasts, wizard steps. Re-exported from
/// `app_dialog.dart` so existing dialog callsites continue importing
/// just the dialog shell.
///
/// Variants (factory constructors):
/// * `.cancel()` — no background, dim text, label auto-localised
/// * `.primary()` — accent background, on-accent text
/// * `.secondary()` — subtle `bg4` background, neutral text
/// * `.destructive()` — red background, on-accent text
///
/// Modifiers available on every factory + the default constructor:
/// * `icon: IconData` — prepends a leading icon sized to the label's
///   font-size and tinted to the foreground colour. Replaces every
///   `FilledButton.icon` / `OutlinedButton.icon` / `TextButton.icon`
///   callsite across the app. The icon is hidden under `loading:
///   true` so the progress indicator owns the leading slot.
/// * `loading: true` — swaps the label for a CircularProgressIndicator
///   sized to the label's font size and disables tap handling. Used
///   while an async action the button triggered is still in flight;
///   the caller must flip it back once the future completes.
/// * `dense: true` — drops the vertical padding and uses the compact
///   desktop height on every platform. For inline/toolbar use where
///   the mobile 48-px tap target would create awkward row gaps.
/// * `fullWidth: true` — wraps the button in a full-width `SizedBox`
///   so it expands to the host constraint width. Used by unlock /
///   passphrase dialogs where the primary action fills the form.
///
/// Direct construction (no factory) is reserved for overrides that
/// don't fit any standard variant, e.g. custom foreground/background
/// pair. Prefer a factory where possible.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final bool enabled;
  final bool loading;
  final bool dense;
  final bool fullWidth;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.background,
    this.foreground,
    this.enabled = true,
    this.loading = false,
    this.dense = false,
    this.fullWidth = false,
    this.icon,
  });

  /// Cancel / dismiss button — no background, dim text.
  const factory AppButton.cancel({
    Key? key,
    VoidCallback? onTap,
    bool loading,
    bool dense,
    bool fullWidth,
    IconData? icon,
  }) = _CancelAction;

  /// Primary action — accent background.
  factory AppButton.primary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
    bool loading,
    bool dense,
    bool fullWidth,
    IconData? icon,
  }) = _PrimaryAction;

  /// Secondary action — subtle background.
  factory AppButton.secondary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
    bool loading,
    bool dense,
    bool fullWidth,
    IconData? icon,
  }) = _SecondaryAction;

  /// Destructive action — red background.
  factory AppButton.destructive({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
    bool loading,
    bool dense,
    bool fullWidth,
    IconData? icon,
  }) = _DestructiveAction;

  @override
  Widget build(BuildContext context) {
    final mobile = isMobilePlatform;
    final hasBg = background != null;
    final effectiveBg = enabled ? background : AppTheme.bg4;
    final defaultFg = hasBg ? AppTheme.onAccent : AppTheme.fgDim;
    final effectiveFg = enabled ? (foreground ?? defaultFg) : AppTheme.fgFaint;

    // Dense mode shrinks the touch target on every platform to the
    // desktop-compact height — mobile's default 48-px target is the
    // right choice for primary surfaces but reads as "too big" in
    // toolbars / inline dense lists.
    final height = dense
        ? AppTheme.controlHeightXs
        : (mobile ? AppTheme.barHeightLg : AppTheme.controlHeightXs);
    final hPad = _horizontalPadding(mobile: mobile, hasBg: hasBg, dense: dense);
    final vPad = dense ? 4.0 : 6.0;
    final fontSize = (mobile && !dense) ? AppFonts.md : AppFonts.sm;
    final radius = (mobile && !dense) ? AppTheme.radiusMd : BorderRadius.zero;

    final bool tapActive = enabled && !loading;

    // `softWrap: true` + `maxLines: 2` so extreme translations
    // (e.g. Russian "Сгенерировать ключ" on a 320-px mobile
    // button) break to a second line instead of scale-shrinking
    // to barely-readable 10-pt. The prior `FittedBox(scaleDown)`
    // + `maxLines: 1` layout shrank every long label down until
    // the Cyrillic / German captions were unreadable on narrow
    // modals; swapping to a wrap-first button keeps the native
    // font size and grows the button vertically when needed.
    // `ellipsis` caps the worst outlier at two lines rather
    // than letting the button unbounded-grow the footer.
    final Widget label0 = Text(
      label,
      textAlign: TextAlign.center,
      softWrap: true,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppFonts.inter(
        fontSize: fontSize,
        fontWeight: hasBg ? FontWeight.w500 : null,
        color: effectiveFg,
      ),
    );

    // Loading state takes over the leading icon slot — the label
    // itself stays visible so the user keeps reading "Checking…"
    // while the spinner animates. Matches the Material
    // `FilledButton.icon(icon: CircularProgressIndicator)` pattern we
    // replaced across the app, and avoids the jitter that a
    // "spinner → spinner+label" swap would create when the async
    // flow resolves a few hundred ms later.
    final Widget spinner = SizedBox(
      width: fontSize,
      height: fontSize,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(effectiveFg),
      ),
    );
    final Widget child;
    if (loading) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          spinner,
          SizedBox(width: dense ? 4 : 6),
          Flexible(child: label0),
        ],
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: fontSize + 2, color: effectiveFg),
          SizedBox(width: dense ? 4 : 6),
          Flexible(child: label0),
        ],
      );
    } else {
      child = label0;
    }

    Widget button = HoverRegion(
      cursor: tapActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: tapActive ? onTap : null,
      builder: (hovered) => Container(
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _buttonColor(hasBg, hovered, effectiveBg, tapActive),
          borderRadius: radius,
        ),
        child: child,
      ),
    );

    if (fullWidth) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  static double _horizontalPadding({
    required bool mobile,
    required bool hasBg,
    required bool dense,
  }) {
    if (dense) return hasBg ? 12.0 : 8.0;
    if (mobile) return hasBg ? 20.0 : 16.0;
    return hasBg ? 16.0 : 12.0;
  }

  Color? _buttonColor(
    bool hasBg,
    bool hovered,
    Color? effectiveBg,
    bool tapActive,
  ) {
    final isHoverActive = hovered && tapActive;
    if (hasBg) {
      return isHoverActive ? _lighten(effectiveBg!) : effectiveBg;
    }
    return isHoverActive ? AppTheme.hover : null;
  }

  static Color _lighten(Color c) =>
      Color.lerp(c, const Color(0xFFFFFFFF), 0.08)!;
}

class _CancelAction extends AppButton {
  const _CancelAction({
    super.key,
    super.onTap,
    super.loading = false,
    super.dense = false,
    super.fullWidth = false,
    super.icon,
  }) : super(label: '', enabled: true);

  @override
  Widget build(BuildContext context) {
    return _CancelActionResolved(
      label: S.of(context).cancel,
      onTap: onTap,
      loading: loading,
      dense: dense,
      fullWidth: fullWidth,
      icon: icon,
    );
  }
}

class _CancelActionResolved extends AppButton {
  const _CancelActionResolved({
    required super.label,
    super.onTap,
    super.loading = false,
    super.dense = false,
    super.fullWidth = false,
    super.icon,
  }) : super(enabled: true);
}

class _PrimaryAction extends AppButton {
  _PrimaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
    super.loading = false,
    super.dense = false,
    super.fullWidth = false,
    super.icon,
  }) : super(background: AppTheme.accent, foreground: AppTheme.onAccent);
}

class _SecondaryAction extends AppButton {
  _SecondaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
    super.loading = false,
    super.dense = false,
    super.fullWidth = false,
    super.icon,
  }) : super(background: AppTheme.bg4, foreground: AppTheme.fg);
}

class _DestructiveAction extends AppButton {
  _DestructiveAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
    super.loading = false,
    super.dense = false,
    super.fullWidth = false,
    super.icon,
  }) : super(background: AppTheme.disconnected, foreground: AppTheme.onAccent);
}
