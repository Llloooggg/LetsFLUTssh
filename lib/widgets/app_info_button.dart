import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'app_info_dialog.dart';

/// Small `(i)` icon that opens an [AppInfoDialog] with caller-supplied
/// copy. Intended to sit inline next to any setting or tier row where
/// the user might want to know what they're turning on before they
/// flip the toggle — canonical use is the security-tier wizard and
/// the Settings → Security section, but it is deliberately generic.
///
/// Size matches the project's standard 20 px icon row so drop-in next
/// to a `_Toggle` or `_InfoTile` looks natural.
class AppInfoButton extends StatelessWidget {
  const AppInfoButton({
    super.key,
    required this.title,
    required this.protectsAgainst,
    required this.doesNotProtectAgainst,
    this.extraNotes,
    this.tooltip,
  });

  final String title;
  final List<String> protectsAgainst;
  final List<String> doesNotProtectAgainst;
  final String? extraNotes;

  /// Hover tooltip. Defaults to the [title] so readers hovering a row
  /// of information buttons can see which one they're about to click.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.info_outline,
      tooltip: tooltip ?? title,
      dense: true,
      color: AppTheme.fgDim,
      onTap: () => AppInfoDialog.show(
        context,
        title: title,
        protectsAgainst: protectsAgainst,
        doesNotProtectAgainst: doesNotProtectAgainst,
        extraNotes: extraNotes,
      ),
    );
  }
}
