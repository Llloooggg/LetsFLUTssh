part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings → Sync — WebDAV-backed push / pull section.
//
// Owns the persistent fields the user types (URL, username, auth
// method, remote path) plus the two buttons that trigger the
// orchestrator's verbs. Secrets are staged into the Rust-side
// SecretStore through `sync_secret_put`; the plaintext never lives
// in Riverpod state past the submit-from-form moment.
// ═══════════════════════════════════════════════════════════════════

class _SyncSection extends ConsumerStatefulWidget {
  const _SyncSection();

  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  final TextEditingController _passphraseCtrl = TextEditingController();
  final TextEditingController _remotePathCtrl = TextEditingController();

  /// Snapshot of the persisted [`SyncConfig`] read on init. The
  /// section re-reads after a successful save / push / pull so the
  /// timestamp rows reflect the canonical state.
  rust_sync.DbSyncConfig? _config;

  /// In-flight verb flag. Disables both buttons while a push / pull
  /// is hitting the network so a double-tap does not enqueue two
  /// transactions.
  bool _busy = false;

  bool _passwordStaged = false;
  bool _passphraseStaged = false;

  String _authMethod = 'basic';

  @override
  void initState() {
    super.initState();
    _refreshConfig();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _pwCtrl.dispose();
    _passphraseCtrl.dispose();
    _remotePathCtrl.dispose();
    super.dispose();
  }

  void _refreshConfig() {
    final c = rust_sync.syncConfigGet();
    _urlCtrl.text = c.webdavUrl;
    _userCtrl.text = c.webdavUsername;
    _remotePathCtrl.text = c.remotePath;
    _authMethod = c.webdavAuthMethod;
    setState(() {
      _config = c;
      _passwordStaged = rust_sync.syncSecretHas(id: c.webdavPasswordRef);
      _passphraseStaged = rust_sync.syncSecretHas(id: c.passphraseRef);
    });
  }

  Future<void> _saveConfig({bool? enabled}) async {
    final c = _config;
    if (c == null) return;
    final updated = rust_sync.DbSyncConfig(
      enabled: enabled ?? c.enabled,
      webdavUrl: _urlCtrl.text.trim(),
      webdavUsername: _userCtrl.text.trim(),
      webdavPasswordRef: c.webdavPasswordRef,
      webdavAuthMethod: _authMethod,
      passphraseRef: c.passphraseRef,
      remotePath: _remotePathCtrl.text.trim().isEmpty
          ? 'letsflutssh.lfs'
          : _remotePathCtrl.text.trim(),
      lastPushedAtMs: c.lastPushedAtMs,
      lastPulledAtMs: c.lastPulledAtMs,
      lastPushedSha256: c.lastPushedSha256,
      lastPushedEtag: c.lastPushedEtag,
      lastPulledEtag: c.lastPulledEtag,
      lastPulledSha256: c.lastPulledSha256,
    );
    try {
      await rust_sync.syncConfigSet(value: updated);
      _refreshConfig();
    } catch (e) {
      AppLogger.instance.log('sync_config_set failed', name: 'Sync', error: e);
      if (!mounted) return;
      final l10n = S.of(context);
      Toast.show(
        context,
        message: localizeError(l10n, e),
        level: ToastLevel.error,
      );
    }
  }

  /// Save the typed plaintext into the SecretStore under the
  /// canonical id and zero the in-memory controller. The
  /// `_passwordStaged` / `_passphraseStaged` flags re-read off
  /// `sync_secret_has` so the UI hint matches the actual store
  /// state, not the controller's transient buffer.
  Future<void> _saveSecret(String id, TextEditingController ctrl) async {
    final value = ctrl.text;
    if (value.isEmpty) {
      await rust_sync.syncSecretDrop(id: id);
    } else {
      await rust_sync.syncSecretPut(
        id: id,
        bytes: Uint8List.fromList(utf8.encode(value)),
      );
    }
    ctrl.clear();
    if (!mounted) return;
    setState(() {
      _passwordStaged = rust_sync.syncSecretHas(
        id: _config?.webdavPasswordRef ?? '',
      );
      _passphraseStaged = rust_sync.syncSecretHas(
        id: _config?.passphraseRef ?? '',
      );
    });
  }

  /// Verify the typed sync passphrase is not the master password.
  /// [`MasterPasswordManager.verifyAndDerive`] checks against the
  /// on-disk Argon2id verifier without re-exposing the master
  /// password's plaintext, so we can detect the collision without
  /// ever holding the master password in Dart memory. Returns
  /// `true` when the passphrase is safe to save, `false` when it
  /// matches the master password.
  Future<bool> _confirmPassphraseNotMaster() async {
    final typed = _passphraseCtrl.text;
    if (typed.isEmpty) return true;
    final manager = ref.read(masterPasswordProvider);
    try {
      if (!await manager.isEnabled()) return true;
      final bytes = Uint8List.fromList(utf8.encode(typed));
      final derived = await manager.verifyAndDerive(bytes);
      return derived == null;
    } catch (_) {
      // Verify is not load-bearing for the warning — fall through
      // on any error so the save still proceeds. The orchestrator
      // surfaces a typed error at push time if the passphrase is
      // genuinely wrong.
      return true;
    }
  }

  Future<void> _onPush() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = S.of(context);
    try {
      final result = await ref.read(syncStatusProvider.notifier).push();
      if (!mounted) return;
      _showResultToast(l10n, result);
    } catch (e) {
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(l10n, e),
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshConfig();
      }
    }
  }

  Future<void> _onPull() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = S.of(context);
    try {
      final result = await ref.read(syncStatusProvider.notifier).pull();
      if (!mounted) return;
      _showResultToast(l10n, result);
    } catch (e) {
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(l10n, e),
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshConfig();
      }
    }
  }

  void _showResultToast(S l10n, rust_sync.DbSyncResult result) {
    final String message;
    final ToastLevel level;
    switch (result.kind) {
      case 'pushed':
        message = l10n.syncPushedBytes(
          rust_format.formatSizeIec(bytes: result.bytes.toInt()),
        );
        level = ToastLevel.success;
        break;
      case 'pull_applied':
        final total =
            result.sessionsMerged +
            result.keysMerged +
            result.tagsMerged +
            result.snippetsMerged +
            result.bookmarksMerged;
        message = l10n.syncPullApplied(total);
        level = ToastLevel.success;
        break;
      case 'up_to_date':
        message = l10n.syncUpToDate;
        level = ToastLevel.info;
        break;
      case 'skipped':
        message = result.reason.isEmpty ? l10n.errSyncDisabled : result.reason;
        level = ToastLevel.info;
        break;
      default:
        message = result.kind;
        level = ToastLevel.info;
    }
    Toast.show(context, message: message, level: level);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final c = _config;
    if (c == null) {
      return const SizedBox.shrink();
    }
    // No inline `_SectionHeader` — the outer settings scaffold
    // (`_CollapsibleSection` on mobile, right-pane title on desktop)
    // already paints the section title from `_Section.title`.
    // Repeating it here doubles "Sync" on every render.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Toggle(
          label: l10n.syncEnable,
          value: c.enabled,
          onChanged: (v) => _saveConfig(enabled: v),
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          // Reuses the `webDavBaseUrl` + `webDavBaseUrlHint` ARB
          // keys from the session edit dialog — same input shape,
          // same protocol, same wire form. One translation source
          // for the same WebDAV base URL field across the app.
          label: l10n.webDavBaseUrl,
          controller: _urlCtrl,
          hint: l10n.webDavBaseUrlHint,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _saveConfig(),
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          label: l10n.webDavUsername,
          controller: _userCtrl,
          onSubmitted: (_) => _saveConfig(),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AuthMethodPicker(
          value: _authMethod,
          onChanged: (v) {
            setState(() => _authMethod = v);
            _saveConfig();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          // Same "Saved — type to change" pattern as the session
          // edit dialog: label stays constant, the hint switches to
          // `savedTypeToChange` when SecretStore already has bytes
          // for this slot so an empty save preserves them.
          label: l10n.password,
          controller: _pwCtrl,
          hint: _passwordStaged ? l10n.savedTypeToChange : '••••••••',
          obscure: true,
          onSubmitted: (_) => _saveSecret(c.webdavPasswordRef, _pwCtrl),
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          label: l10n.syncPassphrase,
          controller: _passphraseCtrl,
          obscure: true,
          hint: _passphraseStaged
              ? l10n.savedTypeToChange
              : l10n.syncPassphraseHint,
          onSubmitted: (_) async {
            // Block the save when the typed passphrase exactly
            // matches the master password — a leaked sync
            // passphrase must not double as the DB cipher key.
            final ok = await _confirmPassphraseNotMaster();
            if (!context.mounted) return;
            if (!ok) {
              Toast.show(
                context,
                message: l10n.syncPassphraseSameAsMasterError,
                level: ToastLevel.error,
              );
              return;
            }
            await _saveSecret(c.passphraseRef, _passphraseCtrl);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          label: l10n.syncRemotePath,
          controller: _remotePathCtrl,
          hint: l10n.syncRemotePathHint,
          onSubmitted: (_) => _saveConfig(),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            AppButton.primary(
              label: l10n.syncPushNow,
              icon: Icons.cloud_upload_outlined,
              onTap: _busy ? null : _onPush,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton.secondary(
              label: l10n.syncPullNow,
              icon: Icons.cloud_download_outlined,
              onTap: _busy ? null : _onPull,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SyncTimestampRow(
          label: l10n.syncLastPushed(
            c.lastPushedAtMs == 0
                ? l10n.syncNeverRun
                : _formatMs(c.lastPushedAtMs),
          ),
        ),
        _SyncTimestampRow(
          label: l10n.syncLastPulled(
            c.lastPulledAtMs == 0
                ? l10n.syncNeverRun
                : _formatMs(c.lastPulledAtMs),
          ),
        ),
        // Show an inline error banner when the last verb left a
        // hint that did not surface through the toast (rare —
        // typical flow is "verb throws → toast → banner stays
        // clean"). Reads off the orchestrator state, not the
        // Dart-side controller.
        Consumer(
          builder: (context, ref, _) {
            final status = ref.watch(syncStatusProvider);
            final err = status.lastError;
            if (err == null || err.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                err,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.red,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return dt.toLocal().toString().split('.').first;
  }
}

/// Auth method radio-style picker. Three values — basic / digest /
/// bearer — same wire shape `lfs_core::sync` accepts.
class _AuthMethodPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AuthMethodPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ExcludeSemantics(child: FieldLabel('Auth')),
        const SizedBox(width: AppSpacing.md),
        for (final m in const ['basic', 'digest', 'bearer'])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: HoverRegion(
              onTap: () => onChanged(m),
              builder: (hovered) {
                final selected = value == m;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.accent.withValues(alpha: 0.15)
                        : (hovered ? AppTheme.hover : Colors.transparent),
                    borderRadius: AppTheme.radiusSm,
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.fgFaint,
                    ),
                  ),
                  child: Text(
                    m,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: selected ? AppTheme.accent : AppTheme.fgDim,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SyncTimestampRow extends StatelessWidget {
  final String label;
  const _SyncTimestampRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        label,
        style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
      ),
    );
  }
}
