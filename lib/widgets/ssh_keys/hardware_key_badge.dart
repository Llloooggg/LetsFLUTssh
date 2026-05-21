import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_selection_area.dart';

/// Text style of one line in a [HardwareKeyBadge] info popover.
/// `dim` = body prose; `warn` = an orange caution note; `mono` = a
/// captured identifier (module path, credential name, handle).
enum HardwareKeyInfoStyle { dim, warn, mono }

/// One row in a hardware-key badge's tap-to-reveal popover.
class HardwareKeyInfoLine {
  final String text;
  final HardwareKeyInfoStyle style;
  const HardwareKeyInfoLine(this.text, {this.style = HardwareKeyInfoStyle.dim});
  const HardwareKeyInfoLine.warn(this.text) : style = HardwareKeyInfoStyle.warn;
  const HardwareKeyInfoLine.mono(this.text) : style = HardwareKeyInfoStyle.mono;
}

/// Tap-to-reveal detail shown when a badge pill is clicked: a titled
/// [AppDialog] listing the captured metadata for that key (device-bound
/// warning, algorithm, module path, …).
class HardwareKeyBadgeInfo {
  final String title;
  final List<HardwareKeyInfoLine> lines;
  const HardwareKeyBadgeInfo({required this.title, required this.lines});
}

/// Hardware-bound key pill rendered next to SSH key rows so corp users
/// with mixed software / hardware key stores can tell at a glance which
/// row is which. One widget covers every backend's tail badge — FIDO2
/// sk-* (the default USB/accent styling, no popover), PKCS#11, Secure
/// Enclave, Windows Hello, Android Keystore, and TPM — varying only by
/// [color] / [icon] and the optional tap-to-reveal [info].
class HardwareKeyBadge extends StatelessWidget {
  final String label;

  /// Pill colour. `null` falls back to [AppTheme.accent] (the FIDO2
  /// sk-* default) — `AppTheme.accent` is not a `const`, so it cannot
  /// sit in the parameter list.
  final Color? color;
  final IconData icon;

  /// Tap affordance. `null` renders a static pill (the FIDO2 sk-* row
  /// has no captured metadata to show).
  final HardwareKeyBadgeInfo? info;

  const HardwareKeyBadge({
    super.key,
    required this.label,
    this.color,
    this.icon = Icons.usb,
    this.info,
  });

  void _showInfo(BuildContext context) {
    final detail = info;
    if (detail == null) return;
    AppDialog.show<void>(
      context,
      builder: (ctx) => AppDialog(
        title: detail.title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < detail.lines.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              AppSelectionArea(child: _line(detail.lines[i])),
            ],
          ],
        ),
        actions: [AppButton.cancel(onTap: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  Text _line(HardwareKeyInfoLine line) {
    final style = switch (line.style) {
      HardwareKeyInfoStyle.dim => AppFonts.inter(
        fontSize: AppFonts.sm,
        color: AppTheme.fgDim,
      ),
      HardwareKeyInfoStyle.warn => AppFonts.inter(
        fontSize: AppFonts.xs,
        color: AppTheme.orange,
      ),
      HardwareKeyInfoStyle.mono => AppFonts.mono(
        fontSize: AppFonts.xs,
        color: AppTheme.fgDim,
      ),
    };
    return Text(line.text, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accent;
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppFonts.inter(
              fontSize: AppFonts.xxs,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (info == null) return pill;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => _showInfo(context),
        borderRadius: AppTheme.radiusSm,
        child: pill,
      ),
    );
  }
}
