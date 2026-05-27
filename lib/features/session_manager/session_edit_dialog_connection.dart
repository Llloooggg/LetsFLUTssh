part of 'session_edit_dialog.dart';

/// Connection-section helpers for the single-form dialog. Build
/// the per-protocol transport block (SSH host/port/user/ProxyJump,
/// WebDAV base-URL/username, S3 access-key/region/endpoint/etc.).
/// Identity fields (name + kind picker) live in the top-of-form
/// composers in the main file.
///
/// Lives as an extension on the dialog state so the helpers reach
/// the per-field controllers (`_hostCtrl`, `_proxyHostCtrl`, …)
/// directly without going through a public surface; `part of`
/// joins the file into the same library so library-private names
/// stay reachable.
extension _ConnectionSection on _SessionEditDialogState {
  /// Identity block at the top of the single-form layout. The kind
  /// picker comes first because it shapes everything below it; the
  /// session-name field follows inline with an auto-derive
  /// placeholder so the user can leave it empty for a basic
  /// connection (save fills it from the kind-specific anchor —
  /// host for SSH, URL host for WebDAV, bucket for S3).
  Widget _buildIdentityBlock() {
    final l10n = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildKindPicker(l10n),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.sessionName,
          controller: _labelCtrl,
          hint: _autoLabelHint(l10n),
        ),
      ],
    );
  }

  /// Placeholder text for the label field — names the field the
  /// save path will auto-derive from when the user leaves the label
  /// empty. Re-evaluated on every build so flipping the kind picker
  /// reshapes the hint in place.
  String _autoLabelHint(S l10n) {
    switch (_kind) {
      case SessionKind.webdav:
        return l10n.sessionNameAutoFromUrl;
      case SessionKind.s3:
        return l10n.sessionNameAutoFromBucket;
      case SessionKind.ssh:
        return l10n.sessionNameAutoFromHost;
    }
  }

  /// Per-kind transport block, dispatched off `_kind`. The single-
  /// form layout calls this from inside the Connection section.
  Widget _buildConnectionBlock() {
    final l10n = S.of(context);
    if (_kind == SessionKind.ssh) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _buildSshFields(l10n),
      );
    }
    if (_kind == SessionKind.webdav) {
      return _buildWebDavSection(l10n);
    }
    return _buildS3Section(l10n);
  }

  /// Transport-kind picker — flipping the active chip swaps the
  /// Connection section between the SSH host/port/proxy block, the
  /// WebDAV base-URL/username block, and the S3
  /// access-key/region/endpoint/addressing block. The Authentication
  /// section right below also reshapes off the same `_kind`.
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
    final candidates = _proxyCandidates();
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
        if (_proxyMode == _ProxyMode.saved)
          _buildSavedSessionDropdown(candidates, l10n),
        if (_proxyMode == _ProxyMode.custom) _buildCustomProxyFields(l10n),
      ],
    );
  }

  /// Saved-session ProxyJump candidates: every session except a
  /// direct self-reference and any whose saved-session chain walks
  /// back to the seed. The Rust probe owns the decision so the dialog
  /// and the connect path share one cycle-detection truth (the
  /// connect path catches orphan loops at dial time — same algorithm,
  /// different entry point). Each session ships its `viaSessionId` so
  /// the probe can walk the chain forward without an extra DB
  /// roundtrip.
  List<Session> _proxyCandidates() {
    final allSessions = ref.watch(sessionProvider);
    final myId = widget.session?.id;
    final chain = [
      for (final s in allSessions)
        rust_sessions.DbSessionProxyRef(
          sessionId: s.id,
          viaSessionId: s.viaSessionId,
        ),
    ];
    return [
      for (final s in allSessions)
        if (s.id != myId &&
            !rust_sessions.sessionsDetectProxyCycle(
              seedId: myId,
              candidateId: s.id,
              chain: chain,
            ))
          s,
    ];
  }

  Widget _buildSavedSessionDropdown(List<Session> candidates, S l10n) {
    final selected = candidates.any((s) => s.id == _proxyViaSessionId)
        ? _proxyViaSessionId
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
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
        // The required-field check forces the user to either pick a
        // bastion or flip the mode to `None`.
        validator: (v) => v == null || v.isEmpty ? l10n.required : null,
      ),
    );
  }

  Widget _buildCustomProxyFields(S l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: StyledFormField(
                label: l10n.hostRequired,
                controller: _proxyHostCtrl,
                hint: 'bastion.example.com',
                // Match the main host field's required check — the
                // `Host *` label promises a required input, the form
                // must enforce it on Save.
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
                // Same 1..65535 envelope as the main SSH port — a
                // stray empty / out-of-range value would land in
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
          // Match the main username field — the label is starred, the
          // form must enforce.
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
