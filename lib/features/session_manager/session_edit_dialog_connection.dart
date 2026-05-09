part of 'session_edit_dialog.dart';

/// Connection-tab UI — host / port / user fields plus the ProxyJump
/// editor. Lives as an extension on the dialog state so the helpers
/// reach the per-field controllers (`_hostCtrl`, `_proxyHostCtrl`, …)
/// directly without going through a public surface; `part of`
/// joins the file into the same library so library-private names
/// stay reachable.
extension _ConnectionTab on _SessionEditDialogState {
  Widget _buildConnectionTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StyledFormField(
          label: S.of(context).sessionName,
          controller: _labelCtrl,
          hint: S.of(context).hintMyServer,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StyledFormField(
                label: S.of(context).hostRequired,
                controller: _hostCtrl,
                hint: S.of(context).hintHost,
                validator: _requiredValidator,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: StyledFormField(
                label: S.of(context).port,
                controller: _portCtrl,
                hint: S.of(context).hintPort,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final port = int.tryParse(v ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return S.of(context).portRange;
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StyledFormField(
          label: S.of(context).usernameRequired,
          controller: _userCtrl,
          hint: S.of(context).hintUsername,
          validator: _requiredValidator,
        ),
        const SizedBox(height: 16),
        _buildProxyJumpSection(),
      ],
    );
  }

  Widget _buildProxyJumpSection() {
    final l10n = S.of(context);
    final allSessions = ref.watch(sessionProvider);
    // Exclude the session being edited so it can't reference itself —
    // cycle detection at runtime would catch it but inline UI is the
    // friendlier guard.
    final myId = widget.session?.id;
    final candidates = [
      for (final s in allSessions)
        if (s.id != myId) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.proxyJump),
        const SizedBox(height: 4),
        Row(
          children: [
            _proxyModeChip(_ProxyMode.none, l10n.proxyJumpNone),
            const SizedBox(width: 6),
            _proxyModeChip(_ProxyMode.saved, l10n.proxyJumpSavedSession),
            const SizedBox(width: 6),
            _proxyModeChip(_ProxyMode.custom, l10n.proxyJumpCustom),
          ],
        ),
        if (_proxyMode == _ProxyMode.saved) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: candidates.any((s) => s.id == _proxyViaSessionId)
                ? _proxyViaSessionId
                : null,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppTheme.bg3,
              border: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
            items: [
              for (final s in candidates)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.label.isNotEmpty ? s.label : s.displayName,
                    style: TextStyle(
                      color: AppTheme.fg,
                      fontFamily: AppFonts.interFamily,
                      fontSize: AppFonts.sm,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => rebuild(() => _proxyViaSessionId = v),
          ),
        ],
        if (_proxyMode == _ProxyMode.custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StyledFormField(
                  label: l10n.hostRequired,
                  controller: _proxyHostCtrl,
                  hint: 'bastion.example.com',
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: StyledFormField(
                  label: l10n.port,
                  controller: _proxyPortCtrl,
                  hint: '22',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StyledFormField(
            label: l10n.usernameRequired,
            controller: _proxyUserCtrl,
            hint: l10n.hintUsername,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.proxyJumpCustomNote,
            style: TextStyle(
              color: AppTheme.fgFaint,
              fontFamily: AppFonts.interFamily,
              fontSize: AppFonts.xs,
            ),
          ),
        ],
      ],
    );
  }

  Widget _proxyModeChip(_ProxyMode mode, String label) {
    return AppPickerChip(
      active: _proxyMode == mode,
      label: label,
      onTap: () => rebuild(() => _proxyMode = mode),
    );
  }
}

/// ProxyJump editor mode for the Connection tab. Stored on the
/// dialog state so the user can flip between modes without losing
/// partially typed values in the others.
enum _ProxyMode { none, saved, custom }
