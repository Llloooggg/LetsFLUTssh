part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings dialogs — export password, import data
// ═══════════════════════════════════════════════════════════════════

/// Mutable holder for passing state by reference into extracted helper methods.
class _ValueHolder<T> {
  T value;
  _ValueHolder(this.value);
}

// ── Export password dialog ──

class _ExportPasswordDialog extends StatelessWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _ExportPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).exportData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.of(context).setMasterPasswordHint,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          _styledPasswordField(passwordCtrl, S.of(context).masterPassword),
          const SizedBox(height: 8),
          _styledPasswordField(confirmCtrl, S.of(context).confirmPassword),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).export_,
          onTap: () {
            if (passwordCtrl.text.isEmpty) return;
            if (passwordCtrl.text != confirmCtrl.text) {
              Toast.show(
                context,
                message: S.of(context).passwordsDoNotMatch,
                level: ToastLevel.warning,
              );
              return;
            }
            Navigator.pop(context, passwordCtrl.text);
          },
        ),
      ],
    );
  }

  static Widget _styledPasswordField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label),
    );
  }
}

// ── Import data dialog ──

class _ImportDataDialog extends StatefulWidget {
  final TextEditingController pathCtrl;
  final TextEditingController passwordCtrl;
  final _ValueHolder<ImportMode> modeHolder;

  const _ImportDataDialog({
    required this.pathCtrl,
    required this.passwordCtrl,
    required this.modeHolder,
  });

  @override
  State<_ImportDataDialog> createState() => _ImportDataDialogState();
}

class _ImportDataDialogState extends State<_ImportDataDialog> {
  Future<void> _pickFile() async {
    final title = S.of(context).pathToLfsFile;
    final initDir = await _defaultDirectory();
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: initDir,
      type: FileType.custom,
      allowedExtensions: ['lfs'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      widget.pathCtrl.text = path;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _styledTextField(
                  widget.pathCtrl,
                  S.of(context).pathToLfsFile,
                  hint: S.of(context).hintLfsPath,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: AppTheme.controlHeightLg,
                child: TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(S.of(context).browse),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    textStyle: AppFonts.inter(fontSize: AppFonts.sm),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.passwordCtrl,
            obscureText: true,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            decoration: AppTheme.inputDecoration(
              labelText: S.of(context).masterPassword,
            ),
          ),
          const SizedBox(height: 12),
          _buildModeSelector(),
          const SizedBox(height: 4),
          Text(
            widget.modeHolder.value == ImportMode.merge
                ? S.of(context).importModeMergeDescription
                : S.of(context).importModeReplaceDescription,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).import_,
          onTap: () {
            if (widget.pathCtrl.text.isEmpty ||
                widget.passwordCtrl.text.isEmpty) {
              return;
            }
            Navigator.pop(context, (
              path: widget.pathCtrl.text,
              password: widget.passwordCtrl.text,
              mode: widget.modeHolder.value,
            ));
          },
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        ModeButton(
          label: S.of(context).merge,
          icon: Icons.merge,
          selected: widget.modeHolder.value == ImportMode.merge,
          onTap: () =>
              setState(() => widget.modeHolder.value = ImportMode.merge),
        ),
        const SizedBox(width: 8),
        ModeButton(
          label: S.of(context).replace,
          icon: Icons.swap_horiz,
          selected: widget.modeHolder.value == ImportMode.replace,
          onTap: () =>
              setState(() => widget.modeHolder.value = ImportMode.replace),
        ),
      ],
    );
  }

  static Widget _styledTextField(
    TextEditingController ctrl,
    String label, {
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label, hintText: hint),
    );
  }
}
