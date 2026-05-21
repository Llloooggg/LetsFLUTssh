part of 'key_manager_dialog.dart';

// ── Expired badge ───────────────────────────────────────────────────

/// Red dot + "Expired" pill rendered in the row's trailing slot
/// when a paired certificate's `valid_before` has passed. Kept as
/// a tiny private widget rather than a one-off `Container` chain so
/// the shape stays consistent if another expired surface (host
/// key, session credential) needs the same affordance.
class _ExpiredBadge extends StatelessWidget {
  final String label;
  const _ExpiredBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.16),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppFonts.inter(
              fontSize: AppFonts.xxs,
              color: AppTheme.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill rendered in a stub row's trailing slot. Sits alongside the
/// backend badge (Apple Secure Enclave / Windows Hello / TPM /
/// Android Keystore) to mark a row whose private half lives on
/// another device. Muted colour intentionally — the row already
/// renders at reduced opacity; the badge is a label, not an alarm.
class _StubBadge extends StatelessWidget {
  final String label;
  const _StubBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.fgDim.withValues(alpha: 0.16),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.fgDim.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppFonts.inter(
          fontSize: AppFonts.xxs,
          color: AppTheme.fgDim,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Row badges + actions ────────────────────────────────────────────

/// Return true when [entry] represents a FIDO2 sk-* hardware key.
/// The v9 schema bumps the `backend` column to authoritative
/// `fido2`; rows that landed before the migration carried only the
/// OpenSSH wire-format keyType tag, so the predicate also matches
/// `sk-ed25519`, `sk-ecdsa-p256`, `sk-ssh-*@*`, and `sk-ecdsa-sha2-*`
/// prefixes. The badge picker and the row icon share this rule.
bool _isFido2Row(SshKeyMetadata entry) =>
    entry.isFido2 ||
    entry.keyType == 'sk-ed25519' ||
    entry.keyType == 'sk-ecdsa-p256' ||
    entry.keyType.startsWith('sk-ssh-') ||
    entry.keyType.startsWith('sk-ecdsa-sha2-');

/// Right-side badge cluster for a key-manager row. Renders the
/// backend pill (FIDO2 / PKCS#11 / Enclave / Hello / TPM / Keystore),
/// the "Stub" pill when the row's private half lives elsewhere, and
/// the red "Expired" pill when a paired cert is past its
/// `valid_before`. Multiple badges stack horizontally with the
/// canonical `AppSpacing.xs` gutter; the widget collapses to a
/// zero-sized box when none of the conditions hit so the row never
/// renders a stray empty Padding.
class _KeyRowBadges extends StatelessWidget {
  final S s;
  final SshKeyMetadata entry;

  const _KeyRowBadges({required this.s, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isFido2 = _isFido2Row(entry);
    final isStub = entry.importedAsStub;
    final expired = entry.validity?.isExpired ?? false;
    final badges = <Widget>[];
    if (isFido2) {
      badges.add(HardwareKeyBadge(label: s.hardwareKeyBadge));
    }
    if (entry.isPkcs11) {
      badges.add(
        Pkcs11Badge(
          label: s.pkcs11Badge,
          modulePath: entry.pkcs11ModulePath,
          tokenSerial: entry.pkcs11TokenSerial,
          objectLabel: entry.pkcs11ObjectLabel,
        ),
      );
    }
    if (entry.isEnclave) {
      badges.add(EnclaveBadge(label: s.sshKeyEnclaveBadge));
    }
    if (entry.isHello) {
      badges.add(
        HelloBadge(
          label: s.helloBadge,
          credentialName: entry.helloCredentialName,
        ),
      );
    }
    if (entry.isTpm) {
      badges.add(
        TpmBadge(
          label: s.tpmSshBadge,
          provider: entry.tpmProvider,
          persistentHandle: entry.tpmHandle,
          pinRequired: entry.tpmPinRequired,
          // Windows-side TPM rows route through the PCP silent
          // path — surface the silent-warning copy in the badge
          // popover. Linux rows do not have a Hello-prompt analogue
          // so the warning is Windows-specific.
          silent: entry.tpmProvider == 'cng-pcp',
        ),
      );
    }
    if (entry.isKeystore) {
      badges.add(
        KeystoreBadge(
          label: s.keystoreBadge,
          strongbox: entry.keystoreStrongBox,
          platform: entry.keystorePlatform,
        ),
      );
    }
    if (isStub) {
      badges.add(_StubBadge(label: s.hardwareKeyStubBadge));
    }
    if (expired) {
      badges.add(_ExpiredBadge(label: s.certExpired));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in badges)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: b,
          ),
      ],
    );
  }
}

/// Right-side action cluster for a key-manager row. Stub rows expose
/// `[Re-generate, Remove]` because the private half lives on another
/// device; non-stub rows expose `[Copy public key, Import/Remove
/// cert, Delete]`. The callback shape keeps the widget free of any
/// reference to `_KeyManagerPanelState`, which makes the row easy to
/// reuse inside a session-edit "Key from manager" surface if that
/// ever needs the same affordance.
class _KeyRowActions extends StatelessWidget {
  final S s;
  final SshKeyMetadata entry;
  final VoidCallback onRegenerateStub;
  final VoidCallback onCopyPublicKey;
  final VoidCallback onImportCertificate;
  final VoidCallback onRemoveCertificate;
  final VoidCallback onDelete;

  const _KeyRowActions({
    required this.s,
    required this.entry,
    required this.onRegenerateStub,
    required this.onCopyPublicKey,
    required this.onImportCertificate,
    required this.onRemoveCertificate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (entry.importedAsStub) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: Icons.autorenew,
            tooltip: s.hardwareKeyStubRegenerateAction,
            dense: true,
            color: AppTheme.accent,
            onTap: onRegenerateStub,
          ),
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: s.hardwareKeyStubRemoveAction,
            dense: true,
            color: AppTheme.red,
            onTap: onDelete,
          ),
        ],
      );
    }
    final hasCert = entry.hasCertificate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: Icons.content_copy,
          tooltip: s.publicKey,
          dense: true,
          onTap: onCopyPublicKey,
        ),
        if (hasCert)
          AppIconButton(
            icon: Icons.workspace_premium_outlined,
            tooltip: s.certRemove,
            dense: true,
            color: AppTheme.orange,
            onTap: onRemoveCertificate,
          )
        else
          AppIconButton(
            icon: Icons.workspace_premium_outlined,
            tooltip: s.certImportTooltip,
            dense: true,
            onTap: onImportCertificate,
          ),
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: s.deleteKey,
          dense: true,
          color: AppTheme.red,
          onTap: onDelete,
        ),
      ],
    );
  }
}
