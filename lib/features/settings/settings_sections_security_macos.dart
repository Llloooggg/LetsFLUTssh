part of 'settings_screen.dart';

/// macOS-only Keychain enable / remove flow — surfaces the bottom-of-
/// section UI block that drives the inside-out re-sign + cert
/// uninstall path. Lives as an extension on [_SecuritySectionState]
/// so the helpers reach `ref` / `mounted` / the `_enablingKeychain` /
/// `_removingKeychain` / `_macosHasIdentity` flags without going
/// through a public surface; `part of` joins the file into the same
/// library so library-private names stay reachable.
extension _MacosKeychain on _SecuritySectionState {
  Widget _buildMacosEnableBlock(S l10n) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: [
        Text(
          l10n.securityMacosEnableSecureTiersSubtitle,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.securityMacosEnableSecureTiersPrompt,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        AppButton.primary(
          label: l10n.securityMacosEnableSecureTiers,
          icon: Icons.vpn_key,
          loading: _enablingKeychain,
          dense: true,
          onTap: _enablingKeychain ? null : _enableMacosKeychain,
        ),
      ],
    ),
  );

  Widget _buildMacosRemoveBlock(S l10n) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: [
        Text(
          l10n.securityMacosRemoveIdentitySubtitle,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        AppButton.destructive(
          label: l10n.securityMacosRemoveIdentity,
          icon: Icons.vpn_key_off,
          loading: _removingKeychain,
          dense: true,
          onTap: _removingKeychain ? null : _removeMacosIdentity,
        ),
      ],
    ),
  );

  Future<void> _enableMacosKeychain() async {
    rebuild(() => _enablingKeychain = true);
    try {
      await rust_macos_resign.macosResignEnsureIdentity();
      // Bundle path math (walk three parents up from
      // `Platform.resolvedExecutable` to the `.app` root) lives
      // Rust-side in `subprocess_util::bundle_root_from_macos_executable`
      // and is exercised by cross-platform tests there.
      final outcome = await rust_macos_resign.macosResignBundle(
        executablePath: Platform.resolvedExecutable,
      );
      if (!mounted) return;
      if (!isResignAcceptable(outcome)) {
        Toast.show(
          context,
          message: S.of(context).securityMacosEnableSecureTiersFailed,
          level: ToastLevel.error,
        );
        return;
      }
      // Drop the persisted capability cache + invalidate providers so
      // the UI re-probes against the freshly re-signed bundle.
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWithSecurity(securityProbeCache: null));
      ref.invalidate(securityCapabilitiesProvider);
      ref.invalidate(hardwareProbeDetailProvider);
      ref.invalidate(keyringProbeDetailProvider);
      await ref.read(securityCapabilitiesProvider.future);
      if (!mounted) return;
      rebuild(() => _macosHasIdentity = true);
      Toast.show(
        context,
        message: S.of(context).securityMacosEnableSecureTiersSuccess,
        level: ToastLevel.success,
      );
    } catch (e) {
      if (!mounted) return;
      Toast.show(
        context,
        message: S.of(context).securityMacosEnableSecureTiersFailed,
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) rebuild(() => _enablingKeychain = false);
    }
  }

  /// Confirmation dialog + tier-switch wizard + cert uninstall. T1 /
  /// T2 secrets are tied to the cert's designated requirement — the
  /// user has to migrate to T0 or Paranoid *before* the cert is
  /// removed, otherwise every stored secret would become unreadable
  /// on the next keychain read. We show the wizard, apply the tier
  /// switch through the existing `onSelectTier` path (which rekeys
  /// the DB under a fresh key under the new tier), and only then
  /// uninstall the signing identity.
  Future<void> _removeMacosIdentity() async {
    rebuild(() => _removingKeychain = true);
    try {
      final confirmed = await AppDialog.show<bool>(
        context,
        builder: (d) => AppDialog(
          title: S.of(d).securityMacosRemoveIdentityConfirmTitle,
          content: Text(
            S.of(d).securityMacosRemoveIdentityConfirmBody,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          actions: [
            AppButton.cancel(onTap: () => Navigator.pop(d, false)),
            AppButton.destructive(
              label: S.of(d).securityMacosRemoveIdentity,
              onTap: () => Navigator.pop(d, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Show tier-switch wizard with keychain + hardware forced off
      // so the user can only pick T0 / Paranoid. Same reduced shape
      // as the first-launch decline path.
      final baseCaps = await probeCapabilities();
      if (!mounted) return;
      final forcedCaps = baseCaps.copyWith(
        keychainAvailable: false,
        hardwareVaultAvailable: false,
      );
      final result = await SecuritySetupDialog.show(
        context,
        currentTier: ref.read(configProvider).security?.tier,
        capabilitiesOverride: forcedCaps,
        dismissible: true,
      );
      if (!mounted) return;
      if (!isPostIdentityRemovalTierAccepted(result.tier)) {
        // User dismissed or wizard returned an unexpected tier —
        // treat as cancel, leave cert in place. The accept-set
        // (plaintext / paranoid) lives in
        // `security_section_logic.isPostIdentityRemovalTierAccepted`.
        return;
      }
      // Re-use `_applyTierChange` directly (not `onSelectTier`) so
      // we stay inside the remove-identity progress flow without
      // stacking another progress dialog / toast that `onSelectTier`
      // installs for the "Change Security Tier" entry point.
      await _applyTierChange(result);
      if (!mounted) return;
      // Tier switch succeeded → safe to drop the cert.
      await rust_macos_resign.macosResignUninstallIdentity();
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWithSecurity(securityProbeCache: null));
      ref.invalidate(securityCapabilitiesProvider);
      ref.invalidate(hardwareProbeDetailProvider);
      ref.invalidate(keyringProbeDetailProvider);
      if (!mounted) return;
      rebuild(() => _macosHasIdentity = false);
      Toast.show(
        context,
        message: S.of(context).securityMacosRemoveIdentitySuccess,
        level: ToastLevel.success,
      );
    } catch (_) {
      if (!mounted) return;
      Toast.show(
        context,
        message: S.of(context).securityMacosRemoveIdentityFailed,
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) rebuild(() => _removingKeychain = false);
    }
  }
}
