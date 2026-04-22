import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/first_launch_banner_provider.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Post-setup notification for the first-launch auto-select path.
///
/// Replaces an earlier blocking first-launch dialog: on the
/// happy path (keychain reachable → T1 auto-selected) a modal that
/// pins the user to click Dismiss before touching anything else is
/// too heavy-handed for a choice the app already made. The toast
/// slides in from the top-right, carries the same copy (what we
/// picked + whether a hardware upgrade is within reach), auto-
/// dismisses after [_displayDuration], and never blocks input.
///
/// Dismiss routes: tap the close icon, tap [onOpenSettings] (which
/// routes into Settings and dismisses), or wait out the timer.
///
/// The reduced-wizard path (both keychain and hardware unreachable)
/// still shows the full [SecuritySetupDialog] modal — that branch is
/// a genuine choice the user has to make before the app can boot, so
/// a toast would be dishonest there.
class FirstLaunchSecurityToast {
  FirstLaunchSecurityToast._();

  /// How long the toast stays on screen before auto-dismissing.
  /// Long enough to read a three-line message plus skim the hint,
  /// short enough not to overstay its welcome.
  static const _displayDuration = Duration(seconds: 8);

  /// Insert the toast overlay. Returns immediately; the OverlayEntry
  /// lifecycle is managed internally — the caller does not need to
  /// track it. Invoking this while a previous toast is still visible
  /// replaces the previous one so the user never sees two stacked.
  static void show(
    BuildContext context, {
    required FirstLaunchBannerData data,
    required VoidCallback onOpenSettings,
    required VoidCallback onDismiss,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _currentEntry?.remove();
    _currentTimer?.cancel();
    final entry = OverlayEntry(
      builder: (overlayContext) => _ToastCard(
        data: data,
        onOpenSettings: () {
          _dismiss();
          onOpenSettings();
        },
        onDismiss: () {
          _dismiss();
          onDismiss();
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
    _currentTimer = Timer(_displayDuration, () {
      _dismiss();
      onDismiss();
    });
  }

  static OverlayEntry? _currentEntry;
  static Timer? _currentTimer;

  static void _dismiss() {
    _currentTimer?.cancel();
    _currentTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.data,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final FirstLaunchBannerData data;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final media = MediaQuery.of(context);
    // Top-right anchored. Width capped so a long German / Portuguese
    // translation doesn't blanket the whole viewport, but clamped
    // against small screens (mobile landscape) so it never exceeds
    // ~60 % of the viewport width.
    final width = media.size.width < 520
        ? media.size.width - 24
        : 380.0.clamp(320.0, media.size.width * 0.6);
    final topInset = media.padding.top + 12;
    final upgradeLine = data.hardwareUpgradeAvailable
        ? l10n.firstLaunchSecurityUpgradeAvailable
        : null;
    return Positioned(
      top: topInset,
      right: 12,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: AppTheme.radiusSm,
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: AppTheme.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.firstLaunchSecurityTitle,
                        style: TextStyle(
                          color: AppTheme.fg,
                          fontSize: AppFonts.sm,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppTheme.fgDim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 26, right: 4),
                  child: Text(
                    l10n.firstLaunchSecurityBody,
                    style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.xs),
                  ),
                ),
                if (upgradeLine != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 26, right: 4),
                    child: Text(
                      upgradeLine,
                      style: TextStyle(
                        color: AppTheme.fgDim,
                        fontSize: AppFonts.xs,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      label: l10n.firstLaunchSecurityOpenSettings,
                      dense: true,
                      onTap: onOpenSettings,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
