part of 'key_manager_dialog.dart';

// ── Generate Key Dialog ─────────────────────────────────────────────

class _GenerateKeyDialog extends StatefulWidget {
  const _GenerateKeyDialog();

  static Future<SshKeyEntry?> show(BuildContext context) {
    return AppDialog.show<SshKeyEntry>(
      context,
      builder: (_) => const _GenerateKeyDialog(),
    );
  }

  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  final _labelCtrl = TextEditingController();
  SshKeyType _type = SshKeyType.ed25519;
  bool _generating = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.generateKey,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: s.keyLabel,
              hintText: s.keyLabelHint,
            ),
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(s.selectKeyType, style: TextStyle(fontSize: AppFonts.sm)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            // Hardware-bound sk-* variants are generated on the
            // device by `ssh-keygen -t ed25519-sk` / `-t ecdsa-sk`,
            // not by the app. The key-manager toolbar exposes a
            // separate "Import hardware key" action for those.
            //
            // `AppPickerChip` (not Material's `ChoiceChip`) paints
            // the active state synchronously from theme colors —
            // ChoiceChip cross-fades over Material's selection
            // animation, so the previously-selected chip's tint
            // briefly appeared on the just-tapped one before the
            // accent overrode it. The picker chip is also our
            // shared design-system shape.
            children: SshKeyType.values.where((t) => !t.isHardwareBound).map((
              t,
            ) {
              final selected = t == _type;
              return AppPickerChip(
                active: selected,
                label: t.label,
                expand: false,
                onTap: _generating ? null : () => setState(() => _type = t),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        AppButton.cancel(
          onTap: _generating ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: _generating ? s.generating : s.generateKey,
          onTap: _generating ? null : _doGenerate,
        ),
      ],
    );
  }

  Future<void> _doGenerate() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;

    setState(() => _generating = true);
    try {
      // Run in microtask to let UI update for RSA
      final entry = await Future.microtask(
        () => generateSshKeyPair(_type, label),
      );
      if (mounted) Navigator.pop(context, entry);
    } catch (e) {
      AppLogger.instance.log('Key generation failed: $e', name: 'KeyManager');
      if (mounted) {
        setState(() => _generating = false);
        Toast.show(
          context,
          message: localizeError(S.of(context), e),
          level: ToastLevel.error,
        );
      }
    }
  }
}

// ── Add / Import Key Dialog ────────────────────────────────────────
//
// Shared label + PEM textarea dialog. The Add toolbar action opens
// it empty so the user types from scratch; the Import action reads a
// file first and opens this dialog with the PEM pre-filled and the
// label pre-seeded from the filename, so the user can rename before
// saving. No file picker lives in here anymore — picking files is
// entirely the responsibility of the Import handler in the panel.

class _AddKeyDialog extends StatefulWidget {
  final String initialLabel;
  final String initialPem;

  const _AddKeyDialog({this.initialLabel = '', this.initialPem = ''});

  static Future<({String label, String pem})?> show(
    BuildContext context, {
    String initialLabel = '',
    String initialPem = '',
  }) {
    return AppDialog.show<({String label, String pem})>(
      context,
      builder: (_) =>
          _AddKeyDialog(initialLabel: initialLabel, initialPem: initialPem),
    );
  }

  @override
  State<_AddKeyDialog> createState() => _AddKeyDialogState();
}

class _AddKeyDialogState extends State<_AddKeyDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _pemCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _pemCtrl = TextEditingController(text: widget.initialPem);
  }

  @override
  void dispose() {
    // PEM body is a private key — zero the buffer before dropping
    // the controller so the typed/pasted key material does not sit
    // on the Dart heap waiting for GC.
    _pemCtrl.wipeAndClear();
    _labelCtrl.dispose();
    _pemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isImport = widget.initialPem.isNotEmpty;
    return AppDialog(
      // Same dialog, two modes: title reflects whether the user got
      // here via Add (paste) or Import (pre-filled from file).
      title: isImport ? s.importKey : s.addKey,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: s.keyLabel,
              hintText: s.keyLabelHint,
            ),
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _pemCtrl,
            maxLines: 5,
            // Private-key PEM — force every IME "learn what the
            // user typed" knob off so pasted / typed key material
            // does not end up in the OS autocorrect / predictive-
            // text / spellcheck personalised-learning dictionary.
            // Multi-line field, so `obscureText` is not an option.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textCapitalization: TextCapitalization.none,
            style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
            decoration: InputDecoration(
              labelText: s.pastePrivateKey,
              hintText: s.pemHint,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        AppButton.primary(
          label: isImport ? s.importKey : s.addKey,
          onTap: _doSubmit,
        ),
      ],
    );
  }

  void _doSubmit() {
    final label = _labelCtrl.text.trim();
    final pem = _pemCtrl.text.trim();
    if (label.isEmpty || pem.isEmpty) return;
    Navigator.pop(context, (label: label, pem: pem));
  }
}

// ── Add-key menu ────────────────────────────────────────────────────

/// One row of the `+ Add ▾` popup menu. Used by [_dispatchAddAction]
/// to route the chosen entry to the matching wizard / dialog handler.
enum _AddKeyAction {
  pastePem,
  importFile,
  generate,
  hwEnclave,
  hwHello,
  hwTpm,
  hwTpmImport,
  hwKeystore,
  hwFido2,
  pkcs11,
}

/// Trigger surface for the `+ Add ▾` [PopupMenuButton]. Visually
/// matches `AppButton.secondary(dense: true)` — same `bg4` fill,
/// `radiusSm` corner, compact `controlHeightXs` height — so it
/// reads as part of the same toolbar vocabulary the other
/// collection dialogs (snippets, tags, known hosts) use. The
/// trailing `arrow_drop_down` chevron signals the popup affordance
/// that distinguishes it from a one-shot action button.
class _AddMenuTrigger extends StatelessWidget {
  final String label;
  const _AddMenuTrigger({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.controlHeightXs,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bg4,
        borderRadius: AppTheme.radiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: AppFonts.sm + 2, color: AppTheme.fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fg),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgDim),
        ],
      ),
    );
  }
}
