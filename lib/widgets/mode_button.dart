import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pill-shaped toggle button used for import mode selection.
///
/// Displays an [icon] and [label] with accent styling when [selected].
class ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const ModeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: AppTheme.controlHeightLg,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.bg3,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.borderLight,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.onAccent : AppTheme.fgDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected ? AppTheme.onAccent : AppTheme.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
