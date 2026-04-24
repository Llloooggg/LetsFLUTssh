import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable styled form field with uppercase label.
///
/// Combines [FieldLabel] + [StyledInput] into a single column.
/// Used across session dialogs, quick connect, and import dialogs.
class StyledFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool fixedHeight;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const StyledFormField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.fixedHeight = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        if (fixedHeight)
          SizedBox(height: AppTheme.controlHeightMd, child: _buildInput())
        else
          _buildInput(),
      ],
    );
  }

  Widget _buildInput() {
    return StyledInput(
      controller: controller,
      hint: hint,
      obscure: obscure,
      suffixIcon: suffixIcon,
      keyboardType: keyboardType,
      validator: validator,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      contentPadding: fixedHeight
          ? const EdgeInsets.symmetric(horizontal: 10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}

/// Uppercase field label used above form inputs.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: AppFonts.inter(
          fontSize: AppFonts.xs,
          fontWeight: FontWeight.w600,
          color: AppTheme.fgFaint,
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

/// Styled text input matching the app design system.
///
/// Provides consistent border, color, and font styling for all text fields.
class StyledInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final EdgeInsetsGeometry? contentPadding;
  final String? labelText;

  const StyledInput({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.autofocus = false,
    this.onSubmitted,
    this.contentPadding,
    this.labelText,
  });

  @override
  Widget build(BuildContext context) {
    // When the field is obscured it is a secret — force the IME
    // hardening knobs off so keystrokes never land in the OS's
    // predictive-text dictionary, spellcheck personalised-learning
    // set, smart-quote substitution history, or autocorrect cache.
    // Each of those knobs defaults to ON for a stock TextField /
    // TextFormField and every one of them routes characters
    // through a service that must not be trusted with an SSH
    // password, key passphrase, or master password.
    //
    // The non-secret path leaves the knobs at their Flutter
    // defaults — session labels / hostnames / usernames benefit
    // from normal autocorrect.
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType:
          keyboardType ?? (obscure ? TextInputType.visiblePassword : null),
      validator: validator,
      autofocus: autofocus,
      onFieldSubmitted: onSubmitted,
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      enableIMEPersonalizedLearning: !obscure,
      smartDashesType: obscure
          ? SmartDashesType.disabled
          : SmartDashesType.enabled,
      smartQuotesType: obscure
          ? SmartQuotesType.disabled
          : SmartQuotesType.enabled,
      textCapitalization: TextCapitalization.none,
      autofillHints: obscure ? const [AutofillHints.password] : null,
      style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
      decoration: InputDecoration(
        hintText: hint,
        labelText: labelText,
        hintStyle: AppFonts.mono(
          fontSize: AppFonts.sm,
          color: AppTheme.fgFaint,
        ),
        labelStyle: TextStyle(color: AppTheme.fgFaint),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.red),
        ),
        errorStyle: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: AppTheme.red,
          height: 1.2,
        ),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffixIcon,
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          maxHeight: AppTheme.controlHeightMd,
        ),
      ),
    );
  }
}
