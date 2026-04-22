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
/// Direct construction (no factory) is reserved for overrides that
/// don't fit any standard variant, e.g. custom foreground/background
/// pair. Prefer a factory where possible.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final bool enabled;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.background,
    this.foreground,
    this.enabled = true,
  });

  /// Cancel / dismiss button — no background, dim text.
  const factory AppButton.cancel({Key? key, VoidCallback? onTap}) =
      _CancelAction;

  /// Primary action — accent background.
  factory AppButton.primary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
  }) = _PrimaryAction;

  /// Secondary action — subtle background.
  factory AppButton.secondary({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool enabled,
  }) = _SecondaryAction;

  /// Destructive action — red background.
  factory AppButton.destructive({
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
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _buttonColor(hasBg, hovered, effectiveBg),
          borderRadius: radius,
        ),
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
        child: Text(
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

class _CancelAction extends AppButton {
  const _CancelAction({super.key, super.onTap})
    : super(label: '', enabled: true);

  @override
  Widget build(BuildContext context) {
    return _CancelActionResolved(label: S.of(context).cancel, onTap: onTap);
  }
}

class _CancelActionResolved extends AppButton {
  const _CancelActionResolved({required super.label, super.onTap})
    : super(enabled: true);
}

class _PrimaryAction extends AppButton {
  _PrimaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.accent, foreground: AppTheme.onAccent);
}

class _SecondaryAction extends AppButton {
  _SecondaryAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.bg4, foreground: AppTheme.fg);
}

class _DestructiveAction extends AppButton {
  _DestructiveAction({
    super.key,
    required super.label,
    super.onTap,
    super.enabled = true,
  }) : super(background: AppTheme.disconnected, foreground: AppTheme.onAccent);
}
