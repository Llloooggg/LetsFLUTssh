import 'package:flutter/material.dart';

import '../core/security/password_strength.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Live coloured bar + label under a password field. Informational
/// only — never blocks Save. Subscribes to [controller]'s
/// [TextEditingController.text] so the widget rebuilds on every
/// keystroke without the parent having to route a `setState`.
///
/// Hides itself when the field is empty so the dialog reflow is
/// invisible until the user actually starts typing.
class PasswordStrengthMeter extends StatefulWidget {
  final TextEditingController controller;

  const PasswordStrengthMeter({super.key, required this.controller});

  @override
  State<PasswordStrengthMeter> createState() => _PasswordStrengthMeterState();
}

class _PasswordStrengthMeterState extends State<PasswordStrengthMeter> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant PasswordStrengthMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strength = assessPasswordStrength(widget.controller.text);
    if (strength == PasswordStrength.empty) {
      return const SizedBox.shrink();
    }
    final l10n = S.of(context);
    final (label, color, fill) = _render(strength, l10n);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.bg3,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: AppFonts.sm, color: color),
          ),
        ],
      ),
    );
  }

  (String label, Color color, double fill) _render(
    PasswordStrength strength,
    S l10n,
  ) {
    switch (strength) {
      case PasswordStrength.empty:
        return ('', AppTheme.fgFaint, 0);
      case PasswordStrength.weak:
        return (l10n.passwordStrengthWeak, AppTheme.red, 0.25);
      case PasswordStrength.moderate:
        return (l10n.passwordStrengthModerate, AppTheme.orange, 0.5);
      case PasswordStrength.strong:
        return (l10n.passwordStrengthStrong, AppTheme.green, 0.75);
      case PasswordStrength.veryStrong:
        return (l10n.passwordStrengthVeryStrong, AppTheme.green, 1.0);
    }
  }
}
