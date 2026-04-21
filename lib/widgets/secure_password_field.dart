import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/secret_controller.dart';

/// A [TextField] pre-configured for secret entry: master password,
/// SSH key passphrase, API token. Drops every IME convenience that
/// would otherwise leak the typed secret into a system service
/// (spellchecker dictionary, predictive-text history, auto-correct
/// learning set, cloud-sync clipboard), and wipes the controller
/// on dispose.
///
/// *Residency trade-off (read before reaching for this widget as a
/// silver bullet):* Dart `String` is immutable and GC-relocatable —
/// there is no hook in Flutter's stock `TextField` path to keep the
/// typed characters out of a Dart-heap `String`. The IME delivers a
/// full [TextEditingValue] each keystroke, the framework stores
/// `.text` on the controller, and the engine renders it. We *can*
/// immediately mirror each change into a page-locked `SecretBuffer`
/// and wipe the controller on dispose (both done here), but the
/// short-lived interim `String`s that the framework created still
/// live on the Dart heap until the GC runs. Closing that window
/// fully would require a native text widget owning a
/// native-memory-backed buffer end-to-end — a large change that
/// trades the entire Flutter text-editing / accessibility / IME
/// stack for marginal benefit against a privileged same-user
/// attacker who already has process-memory access.
///
/// What this widget does buy:
///
/// * **Predictable wipe point.** The caller's controller is cleared
///   to a same-length null-byte string and then emptied when this
///   widget's `State` disposes, *before* the parent state drops
///   its reference. The `String` on the Dart heap is still GC's to
///   collect, but it no longer has any listenable / widget / render
///   pipeline reference — the GC gets to it on the next cycle.
/// * **IME hardening.** Every "make typing more convenient" knob on
///   a `TextField` defaults to on, and every one of them routes
///   keystrokes through an OS service that the app does not trust
///   with a secret (autocorrect dictionary, predictive-text
///   history, IME personalised learning, smart-quote substitution,
///   text-capitalisation hinting, autofill prompts). This widget
///   forces every such knob *off*, so a typed master password does
///   not end up in the user's next spellcheck suggestion list.
/// * **No clipboard suggestions.** `autofillHints:
///   [AutofillHints.password]` keeps the field inside the
///   platform's password-autofill surface; that surface routinely
///   suppresses the dictation / share / lookup context-menu items
///   that a plain text field would expose.
///
/// The widget does not own the controller — the caller is
/// responsible for constructing it and ultimately calling
/// `.dispose()`. Wiping in this widget's `dispose` is safe because
/// [SecretController.wipeAndClear] is idempotent.
class SecurePasswordField extends StatefulWidget {
  const SecurePasswordField({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.decoration,
    this.autofocus = false,
    this.obscureText = true,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;
  final bool autofocus;

  /// Exposed so the caller can flip between masked and revealed —
  /// `obscureText: false` for "show password" toggles. The default
  /// is `true`; keep it that way unless the UI has an explicit
  /// reveal affordance.
  final bool obscureText;

  final TextInputAction? textInputAction;

  /// Overrides the default `TextInputType.visiblePassword` for
  /// cases like PIN entry that need `TextInputType.number`. The
  /// hardening flags (no autocorrect, no suggestions, no IME
  /// personalised learning, etc.) still apply.
  final TextInputType? keyboardType;

  /// Passed through to the underlying TextField — e.g. a numeric
  /// PIN field supplies `[FilteringTextInputFormatter.digitsOnly]`.
  final List<TextInputFormatter>? inputFormatters;

  /// Caps input length. `null` keeps the TextField default
  /// (unlimited). Useful for fixed-length PINs.
  final int? maxLength;

  @override
  State<SecurePasswordField> createState() => _SecurePasswordFieldState();
}

class _SecurePasswordFieldState extends State<SecurePasswordField> {
  @override
  void dispose() {
    // Wipe BEFORE parent state drops its reference to the
    // controller. Idempotent — the caller's own dispose() is
    // welcome to wipeAndClear again.
    widget.controller.wipeAndClear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      // Hardening knobs. Each of these defaults to on for a plain
      // TextField; each one routes the typed secret through an OS
      // service we do not want to share with.
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textCapitalization: TextCapitalization.none,
      // visiblePassword is the Android "password" IME that already
      // disables dictionary learning at the OS level. iOS collapses
      // this onto the default keyboard but honours the autofill
      // hint for the same effect.
      keyboardType: widget.keyboardType ?? TextInputType.visiblePassword,
      inputFormatters: widget.inputFormatters,
      maxLength: widget.maxLength,
      autofillHints: const [AutofillHints.password],
      // Strip paste / cut / replace / share from the long-press
      // menu when the field is obscured — leaves only "select" and
      // the mask-safe actions. This is the same menu the platform's
      // native password fields expose.
      contextMenuBuilder: widget.obscureText ? _noContextMenu : null,
    );
  }

  static Widget _noContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return const SizedBox.shrink();
  }
}
