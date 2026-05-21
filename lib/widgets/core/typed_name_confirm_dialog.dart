import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_dialog.dart';

/// Destructive confirmation that requires the user to type a magic
/// phrase verbatim before the Confirm button enables. Used for
/// catastrophic-irreversible flows where a single tap of the
/// standard [`ConfirmDialog`] is too easy to misfire (Reset All
/// Data wipes the SQLCipher store + every keychain entry + every
/// hardware-vault slot — recovery is impossible).
///
/// Pattern mirrors GitHub's "type the repo name to delete" guard
/// + Stripe's "type DELETE to confirm" pattern. The magic phrase
/// stays in English (the app name `LetsFLUTssh`) rather than
/// localised text — a translated phrase hides the keystroke
/// pattern from the muscle memory of a user who switched locales,
/// which is exactly the cohort who needs the guard most.
class TypedNameConfirmDialog extends StatefulWidget {
  final String title;
  final Widget body;
  final String magicPhrase;
  final String confirmLabel;
  final String typePromptHint;

  const TypedNameConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.magicPhrase,
    required this.confirmLabel,
    required this.typePromptHint,
  });

  /// Show the dialog and return `true` only when the user typed
  /// [magicPhrase] verbatim and tapped Confirm. Cancel / dismiss
  /// returns `false`.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required Widget body,
    required String magicPhrase,
    required String confirmLabel,
    required String typePromptHint,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      builder: (_) => TypedNameConfirmDialog(
        title: title,
        body: body,
        magicPhrase: magicPhrase,
        confirmLabel: confirmLabel,
        typePromptHint: typePromptHint,
      ),
    );
    return result == true;
  }

  @override
  State<TypedNameConfirmDialog> createState() => _TypedNameConfirmDialogState();
}

class _TypedNameConfirmDialogState extends State<TypedNameConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final next = _controller.text == widget.magicPhrase;
    if (next != _matches) {
      setState(() => _matches = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.body,
          const SizedBox(height: AppSpacing.lg),
          Text(
            widget.typePromptHint,
            style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: AppTheme.inputDecoration(hintText: widget.magicPhrase),
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop(false)),
        AppButton.destructive(
          label: widget.confirmLabel,
          enabled: _matches,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
