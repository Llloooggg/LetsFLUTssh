part of 'session_edit_dialog.dart';

/// Connection-tab UI — host / port / user fields plus the ProxyJump
/// editor. Lives as an extension on the dialog state so the helpers
/// reach the per-field controllers (`_hostCtrl`, `_proxyHostCtrl`, …)
/// directly without going through a public surface; `part of`
/// joins the file into the same library so library-private names
/// stay reachable.
extension _ConnectionTab on _SessionEditDialogState {
  Widget _buildConnectionTab() {
    final l10n = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StyledFormField(
          label: l10n.sessionName,
          controller: _labelCtrl,
          hint: l10n.hintMyServer,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildKindPicker(l10n),
        const SizedBox(height: AppSpacing.lg),
        if (_kind == SessionKind.ssh)
          ..._buildSshFields(l10n)
        else if (_kind == SessionKind.webdav)
          _buildWebDavSection(l10n)
        else
          _buildS3Section(l10n),
      ],
    );
  }

  /// Transport-kind picker — flipping the active chip swaps the
  /// rest of the Connection tab between the SSH host/port/proxy
  /// block, the WebDAV base-URL / auth-method / pin block, and the
  /// S3 access-key / region / endpoint / addressing block.
  Widget _buildKindPicker(S l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(l10n.sessionKindLabel),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // `expand: false` — `Wrap` rejects `FlexParentData`, so
            // the chip must hug its content rather than fill a flex
            // slot. The pickers stay readable side-by-side without
            // the equal-width stretch.
            AppPickerChip(
              active: _kind == SessionKind.ssh,
              label: l10n.sessionKindSsh,
              onTap: () => _switchKind(SessionKind.ssh),
              expand: false,
            ),
            AppPickerChip(
              active: _kind == SessionKind.webdav,
              label: l10n.sessionKindWebDav,
              onTap: () => _switchKind(SessionKind.webdav),
              expand: false,
            ),
            AppPickerChip(
              active: _kind == SessionKind.s3,
              label: l10n.sessionKindS3,
              onTap: () => _switchKind(SessionKind.s3),
              expand: false,
            ),
          ],
        ),
      ],
    );
  }

  /// S3 transport-config block. Access-key id + region + endpoint +
  /// addressing-style toggle + default bucket / prefix. The secret
  /// access key lives on the Auth tab next to the SSH password
  /// field — same widget, kind-aware contract on save.
  Widget _buildS3Section(S l10n) {
    if (_loadingS3) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StyledFormField(
          label: '${l10n.s3AccessKeyId} *',
          controller: _accessKeyIdCtrl,
          hint: 'AKIA…',
          validator: _requiredValidator,
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.s3Region,
          controller: _regionCtrl,
          hint: l10n.s3RegionHint,
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.s3Endpoint,
          controller: _endpointCtrl,
          hint: l10n.s3EndpointHint,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Switch(
              value: _s3PathStyleEnabled,
              onChanged: (v) => rebuild(() => _s3PathStyleEnabled = v),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.s3PathStyle,
                    style: TextStyle(
                      color: AppTheme.fg,
                      fontFamily: AppFonts.interFamily,
                      fontSize: AppFonts.sm,
                    ),
                  ),
                  Text(
                    l10n.s3PathStyleHint,
                    style: TextStyle(
                      color: AppTheme.fgFaint,
                      fontFamily: AppFonts.interFamily,
                      fontSize: AppFonts.xs,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.s3DefaultBucket,
          controller: _defaultBucketCtrl,
          hint: 'my-bucket',
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.s3DefaultPrefix,
          controller: _defaultPrefixCtrl,
          hint: 'logs/',
        ),
      ],
    );
  }

  List<Widget> _buildSshFields(S l10n) {
    return [
      Row(
        children: [
          Expanded(
            child: StyledFormField(
              label: l10n.hostRequired,
              controller: _hostCtrl,
              hint: l10n.hintHost,
              validator: _requiredValidator,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 80,
            child: StyledFormField(
              label: l10n.port,
              controller: _portCtrl,
              hint: l10n.hintPort,
              keyboardType: TextInputType.number,
              validator: (v) =>
                  isValidConnectionPort(v) ? null : l10n.portRange,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      StyledFormField(
        label: l10n.usernameRequired,
        controller: _userCtrl,
        hint: l10n.hintUsername,
        validator: _requiredValidator,
      ),
      const SizedBox(height: AppSpacing.lg),
      _buildProxyJumpSection(),
    ];
  }

  /// WebDAV transport-config block. Base URL + username only — the
  /// auth method picker + credential field + self-signed-cert
  /// fingerprint live on the Auth tab next to the SSH credential
  /// block. Connection answers "where are we connecting"; Auth
  /// answers "how do we prove it" — fingerprint pin is a trust
  /// anchor, so it belongs in Auth.
  Widget _buildWebDavSection(S l10n) {
    if (_loadingWebDav) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StyledFormField(
          label: '${l10n.webDavBaseUrl} *',
          controller: _baseUrlCtrl,
          hint: l10n.webDavBaseUrlHint,
          validator: _webDavBaseUrlValidator,
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: '${l10n.webDavUsername} *',
          controller: _userCtrl,
          hint: l10n.hintUsername,
          validator: _requiredValidator,
        ),
      ],
    );
  }

  Widget _webDavAuthChip(String wire, String label) {
    return AppPickerChip(
      active: _webdavAuthMethod == wire,
      label: label,
      onTap: () => rebuild(() => _webdavAuthMethod = wire),
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
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            _proxyModeChip(_ProxyMode.none, l10n.proxyJumpNone),
            const SizedBox(width: AppSpacing.xxs),
            _proxyModeChip(_ProxyMode.saved, l10n.proxyJumpSavedSession),
            const SizedBox(width: AppSpacing.xxs),
            _proxyModeChip(_ProxyMode.custom, l10n.proxyJumpCustom),
          ],
        ),
        if (_proxyMode == _ProxyMode.saved) ...[
          const SizedBox(height: AppSpacing.sm),
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
            // "Saved session" mode without a selection would silently
            // collapse to no-ProxyJump on save (`viaSessionId = null`).
            // The required-field check forces the user to either pick
            // a bastion or flip the mode to `None`.
            validator: (v) => v == null || v.isEmpty ? l10n.required : null,
          ),
        ],
        if (_proxyMode == _ProxyMode.custom) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: StyledFormField(
                  label: l10n.hostRequired,
                  controller: _proxyHostCtrl,
                  hint: 'bastion.example.com',
                  // Match the main host field's required check —
                  // the `Host *` label promises a required input,
                  // the form must enforce it on Save.
                  validator: _requiredValidator,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 80,
                child: StyledFormField(
                  label: l10n.port,
                  controller: _proxyPortCtrl,
                  hint: '22',
                  keyboardType: TextInputType.number,
                  // Same 1..65535 envelope as the main SSH port —
                  // a stray empty / out-of-range value would land in
                  // `via_port` and surface as a russh handshake error
                  // long after Save.
                  validator: (v) =>
                      isValidConnectionPort(v) ? null : l10n.portRange,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          StyledFormField(
            label: l10n.usernameRequired,
            controller: _proxyUserCtrl,
            hint: l10n.hintUsername,
            // Match the main username field — the label is starred,
            // the form must enforce.
            validator: _requiredValidator,
          ),
          const SizedBox(height: AppSpacing.xxs),
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
