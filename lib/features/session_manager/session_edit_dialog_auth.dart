part of 'session_edit_dialog.dart';

/// Auth-tab UI — the system-ssh-agent toggle plus the password /
/// key-store / inline-PEM / passphrase fields and the picker +
/// drop-target helpers. Lives as an extension on the dialog state
/// so the helpers reach the per-field controllers (`_passwordCtrl`,
/// `_keyDataCtrl`, …) and the dirty-bit flags directly without
/// going through a public surface; `part of` joins the file into
/// the same library so library-private names stay reachable.
extension _AuthTab on _SessionEditDialogState {
  Widget _buildAuthTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_authError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _authError!,
                style: TextStyle(
                  fontFamily: AppFonts.interFamily,
                  fontSize: AppFonts.xs,
                  color: AppTheme.red,
                ),
              ),
            ),
          ),
        _buildAgentOption(),
        if (!_useAgent) ...[
          const SizedBox(height: 16),
          _buildPasswordField(),
          const SizedBox(height: 16),
          _buildOrDivider(),
          const SizedBox(height: 16),
          ..._buildKeyFields(),
        ],
      ],
    );
  }

  /// Renders the "Use system ssh-agent" toggle at the top of the
  /// Auth tab. Selecting it collapses every other auth field — the
  /// running agent (`$SSH_AUTH_SOCK` on Unix, OpenSSH named pipe /
  /// Pageant on Windows) owns every signature for the session.
  ///
  /// Mobile builds keep the toggle visible but disabled — the agent
  /// endpoint is desktop-only because Android / iOS have no system
  /// ssh-agent equivalent to dial. Disabling instead of hiding keeps
  /// configuration parity with the desktop UI so a session edited on
  /// mobile preserves the toggle state instead of silently dropping
  /// it.
  Widget _buildAgentOption() {
    final s = S.of(context);
    final disabled = !isDesktopPlatform;
    final tile = Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: HoverRegion(
        onTap: disabled ? null : () => rebuild(() => _useAgent = !_useAgent),
        builder: (hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _useAgent
                ? AppTheme.accent.withValues(alpha: 0.1)
                : (hovered ? AppTheme.hover : AppTheme.bg2),
            borderRadius: AppTheme.radiusSm,
            border: Border.all(
              color: _useAgent
                  ? AppTheme.accent.withValues(alpha: 0.4)
                  : AppTheme.borderLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _useAgent ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: _useAgent ? AppTheme.accent : AppTheme.fgFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.authMethodAgent,
                      style: AppFonts.inter(
                        fontSize: AppFonts.sm,
                        color: AppTheme.fg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.authMethodAgentSubtitle,
                      style: AppFonts.inter(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (disabled) {
      return Tooltip(message: s.authMethodAgentMobileUnsupported, child: tile);
    }
    return tile;
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.borderLight)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            S.of(context).authOrDivider,
            style: TextStyle(
              fontFamily: AppFonts.interFamily,
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.fgFaint,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.borderLight)),
      ],
    );
  }

  Widget _buildPasswordField() {
    final hasStored = widget.session?.auth.hasStoredPassword ?? false;
    return StyledFormField(
      label: S.of(context).password,
      controller: _passwordCtrl,
      hint: hasStored ? S.of(context).savedTypeToChange : '••••••••',
      obscure: _obscurePassword,
      suffixIcon: GestureDetector(
        onTap: () => rebuild(() => _obscurePassword = !_obscurePassword),
        child: Icon(
          _obscurePassword ? Icons.visibility : Icons.visibility_off,
          size: 12,
          color: AppTheme.fgFaint,
        ),
      ),
    );
  }

  List<Widget> _buildKeyFields() {
    return [
      _buildKeyStoreSelector(),
      const SizedBox(height: 12),
      if (!_hasStoreKey) ...[
        _buildKeyPathField(),
        const SizedBox(height: 8),
        _buildPemToggle(),
        if (_showKeyText) _buildPemTextField(),
        const SizedBox(height: 12),
      ],
      _buildPassphraseField(),
    ];
  }

  Widget _buildKeyStoreSelector() {
    final s = S.of(context);
    final keyList = ref.watch(sshKeysProvider);
    if (keyList.isEmpty && !_hasStoreKey) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _hasStoreKey
                  ? _buildSelectedKeyChip()
                  : _buildKeyPickerButton(s, keyList),
            ),
          ],
        ),
        if (_hasStoreKey)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _buildOrDividerLabel(),
                style: TextStyle(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _buildOrDividerLabel() =>
      '${S.of(context).selectFromKeyStore}: $_selectedKeyLabel';

  Widget _buildKeyPickerButton(S s, List<SshKeyEntry> keyList) {
    return DropdownSelectButton(
      icon: Icons.vpn_key,
      label: s.selectFromKeyStore,
      onTap: keyList.isEmpty ? null : () => _showKeyPicker(keyList),
    );
  }

  Widget _buildSelectedKeyChip() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_key, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedKeyLabel,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fg,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: () => rebuild(() {
              _selectedKeyId = '';
              _selectedKeyLabel = '';
            }),
            tooltip: S.of(context).clearKeyFile,
            size: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _showKeyPicker(List<SshKeyEntry> keys) async {
    // Pull metadata once on picker-open so each row can render the
    // matching backend badge (FIDO2 / PKCS#11 / Enclave / Hello /
    // TPM / Keystore). `SshKeyEntry` carries the user-facing label
    // + key type but drops the backend discriminator — the metadata
    // listing is the only source for the per-backend `is*` flags.
    // Software rows render no badge (the legacy default).
    Map<String, SshKeyMetadata> metadata = const {};
    try {
      metadata = await ref.read(sshKeysMutatorProvider).loadAllMetadata();
    } catch (_) {
      // Metadata lookup is decorative only — a transient FRB miss
      // degrades to the unbadged list shape rather than blocking
      // the picker. The selected id still routes through the same
      // save path so a software fallback never blocks a connect.
      metadata = const {};
    }
    if (!mounted) return;
    final selected = await showDialog<SshKeyEntry>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.of(context).selectFromKeyStore),
        children: keys
            .map((k) => _buildKeyPickerOption(ctx, k, metadata[k.id]))
            .toList(),
      ),
    );
    if (selected != null && mounted) {
      rebuild(() {
        _selectedKeyId = selected.id;
        _selectedKeyLabel = selected.label;
        // Clear manual key fields when selecting from store
        _keyPathCtrl.clear();
        _keyDataCtrl.clear();
        _showKeyText = false;
      });
    }
  }

  /// One row inside the "Select from key store" picker. Renders the
  /// row's hardware-backend badge inline so the user can tell which
  /// stored key is FIDO2 / PKCS#11 / Enclave / Hello / TPM / Keystore
  /// versus software-stored. The badge widgets are reused verbatim
  /// from the standalone key manager so the two surfaces stay
  /// visually identical.
  Widget _buildKeyPickerOption(
    BuildContext ctx,
    SshKeyEntry k,
    SshKeyMetadata? meta,
  ) {
    final s = S.of(context);
    // Stub rows are imported public-half-only stubs for device-bound
    // backends — the private side lives on the originating device.
    // Disable the picker option with a tooltip so the user notices
    // the row exists but understands why it cannot be picked.
    final isStub = meta?.importedAsStub ?? false;
    final tile = ListTile(
      leading: Icon(
        Icons.vpn_key,
        size: 16,
        color: k.isGenerated ? AppTheme.accent : AppTheme.fgDim,
      ),
      title: Text(k.label),
      subtitle: Text(
        isStub ? s.hardwareKeyStubSubtitle : k.keyType,
        style: TextStyle(fontSize: AppFonts.xs),
      ),
      trailing: _keyPickerBadge(s, meta),
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: !isStub,
    );
    if (isStub) {
      return Tooltip(
        message: s.hardwareKeyStubPickerTooltip,
        child: Opacity(opacity: 0.55, child: tile),
      );
    }
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, k),
      child: tile,
    );
  }

  /// Pick the matching badge widget for a manager-key metadata row.
  /// Returns `null` for software rows (no badge — same as the key
  /// manager list). Order matches the key manager: FIDO2 → PKCS#11 →
  /// Enclave → Hello → TPM → Keystore. The backend column is mutually
  /// exclusive so the priority chain only ever resolves one badge.
  Widget? _keyPickerBadge(S s, SshKeyMetadata? meta) {
    if (meta == null) return null;
    if (meta.isFido2) {
      return HardwareKeyBadge(label: s.hardwareKeyBadge);
    }
    if (meta.isPkcs11) {
      return Pkcs11Badge(
        label: s.pkcs11Badge,
        modulePath: meta.pkcs11ModulePath,
        tokenSerial: meta.pkcs11TokenSerial,
        objectLabel: meta.pkcs11ObjectLabel,
      );
    }
    if (meta.isEnclave) {
      return EnclaveBadge(label: s.sshKeyEnclaveBadge);
    }
    if (meta.isHello) {
      return HelloBadge(
        label: s.helloBadge,
        credentialName: meta.helloCredentialName,
      );
    }
    if (meta.isTpm) {
      return TpmBadge(
        label: s.tpmSshBadge,
        provider: meta.tpmProvider,
        persistentHandle: meta.tpmHandle,
        pinRequired: meta.tpmPinRequired,
        silent: meta.tpmProvider == 'cng-pcp',
      );
    }
    if (meta.isKeystore) {
      return KeystoreBadge(
        label: s.keystoreBadge,
        strongbox: meta.keystoreStrongBox,
        platform: meta.keystorePlatform,
      );
    }
    return null;
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: S.of(context).selectKeyFile,
      allowMultiple: false,
      type: FileType.any,
    );
    if (!mounted) return;
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final pemContent = await KeyFileHelper.tryReadPemKey(path);
    if (pemContent != null) {
      rebuild(() {
        _keyDataCtrl.text = pemContent;
        _showKeyText = true;
      });
    } else {
      rebuild(() => _keyPathCtrl.text = path);
    }
  }

  Widget _buildKeyPathField() {
    final hasKey = _keyPathCtrl.text.trim().isNotEmpty;
    final fileName = hasKey ? p.basename(_keyPathCtrl.text.trim()) : null;

    final button = DropdownSelectButton(
      icon: hasKey ? Icons.vpn_key : Icons.folder_open,
      label: fileName ?? S.of(context).selectKeyFile,
      onTap: _pickKeyFile,
      showChevron: false,
    );

    final row = Row(
      children: [
        Expanded(child: button),
        if (hasKey)
          AppIconButton(
            icon: Icons.close,
            onTap: () => rebuild(() => _keyPathCtrl.clear()),
            tooltip: S.of(context).clearKeyFile,
            size: 18,
          ),
      ],
    );

    if (!isDesktopPlatform) return row;

    return DropTarget(
      onDragEntered: (_) => rebuild(() => _keyDragging = true),
      onDragExited: (_) => rebuild(() => _keyDragging = false),
      onDragDone: (details) async {
        rebuild(() => _keyDragging = false);
        final files = details.files;
        if (files.isNotEmpty) {
          final path = files.first.path;
          final pemContent = await KeyFileHelper.tryReadPemKey(path);
          if (pemContent != null) {
            rebuild(() {
              _keyDataCtrl.text = pemContent;
              _showKeyText = true;
            });
            return;
          }
          rebuild(() => _keyPathCtrl.text = path);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: _keyDragging
              ? Border.all(color: AppTheme.accent, width: 2)
              : null,
          borderRadius: AppTheme.radiusSm,
        ),
        child: _keyDragging
            ? SizedBox(
                height: AppTheme.itemHeightLg,
                child: Center(
                  child: Text(
                    S.of(context).dropKeyFileHere,
                    style: TextStyle(color: AppTheme.accent),
                  ),
                ),
              )
            : row,
      ),
    );
  }

  Widget _buildPemToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        label: _showKeyText
            ? S.of(context).hidePemText
            : S.of(context).pastePemKeyText,
        icon: _showKeyText
            ? Icons.keyboard_arrow_up
            : Icons.keyboard_arrow_down,
        onTap: () => rebuild(() => _showKeyText = !_showKeyText),
        dense: true,
      ),
    );
  }

  Widget _buildPemTextField() {
    final hasStored = widget.session?.auth.hasStoredKeyData ?? false;
    return TextFormField(
      controller: _keyDataCtrl,
      decoration: InputDecoration(
        hintText: hasStored
            ? S.of(context).savedTypeToChange
            : S.of(context).hintPemKey,
        hintStyle: AppFonts.mono(
          fontSize: AppFonts.xs,
          color: AppTheme.fgFaint,
        ),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      ),
      maxLines: 5,
      // PEM body is a private key — force every IME "learn what
      // the user typed" knob off so pasted / typed key material
      // does not end up in the OS autocorrect / predictive-text /
      // spellcheck personalised-learning dictionary. Multi-line,
      // so `obscureText` is not an option; the hardening flags are.
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textCapitalization: TextCapitalization.none,
      style: AppFonts.mono(fontSize: AppFonts.xs),
    );
  }

  Widget _buildPassphraseField() {
    final hasStored = widget.session?.auth.hasStoredPassphrase ?? false;
    return StyledFormField(
      label: S.of(context).keyPassphrase,
      controller: _passphraseCtrl,
      hint: hasStored
          ? S.of(context).savedTypeToChange
          : S.of(context).hintOptional,
      obscure: _obscurePassphrase,
      suffixIcon: GestureDetector(
        onTap: () => rebuild(() => _obscurePassphrase = !_obscurePassphrase),
        child: Icon(
          _obscurePassphrase ? Icons.visibility : Icons.visibility_off,
          size: 12,
          color: AppTheme.fgFaint,
        ),
      ),
      validator: (v) {
        if (v != null && v.isNotEmpty) {
          final hasKey =
              _keyPathCtrl.text.trim().isNotEmpty ||
              _keyDataCtrl.text.trim().isNotEmpty;
          if (!hasKey) return S.of(context).provideKeyFirst;
        }
        return null;
      },
    );
  }
}
