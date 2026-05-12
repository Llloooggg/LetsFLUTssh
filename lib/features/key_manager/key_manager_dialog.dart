import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/import/key_file_helper.dart';
import '../../core/security/ssh_key.dart';
import 'key_manager_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/fido2.dart' as rust_fido2;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/keys.dart' as rust_keys;
import '../../src/rust/api/pkcs11.dart' as rust_pkcs11;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/platform.dart';
import '../../widgets/app_collection_toolbar.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/secret_controller.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/enclave_ssh_dialog.dart';
import '../../widgets/hello_ssh_dialog.dart';
import '../../widgets/keystore_ssh_dialog.dart';
import '../../widgets/pkcs11_import_dialog.dart';
import '../../widgets/toast.dart';
import '../../widgets/tpm_ssh_dialog.dart';

/// Embeddable SSH key manager — toolbar + list with CRUD.
///
/// Used standalone inside [KeyManagerDialog] (mobile) and embedded in
/// the desktop Tools dialog.
class KeyManagerPanel extends ConsumerStatefulWidget {
  const KeyManagerPanel({super.key});

  @override
  ConsumerState<KeyManagerPanel> createState() => _KeyManagerPanelState();
}

class _KeyManagerPanelState extends ConsumerState<KeyManagerPanel> {
  // Listing carries metadata only — id, label, publicKey, keyType,
  // createdAt, fingerprints. The PEM bytes never enter the dialog;
  // `Copy public key`, `Delete`, and the search filter all work
  // off [SshKeyMetadata].
  List<SshKeyMetadata> _keys = [];
  bool _loading = true;
  String _filter = '';

  /// FIDO2 hardware-key direct-CTAP2 probe — captured once at build
  /// time. `false` in flutter_test contexts where FRB is not loaded
  /// (the probe throws `StateError`) and on platforms / builds where
  /// the `fido2` feature is off. The hardware-import action gates
  /// off this flag.
  bool get _fido2Available {
    try {
      return rust_fido2.fido2IsAvailable();
    } catch (_) {
      return false;
    }
  }

  /// PKCS#11 desktop-only probe. Mobile (Android / iOS) returns
  /// `false` because the sandbox / vendor-ABI mismatch makes the
  /// path impossible — capability ladder rung 4 ("honestly hide").
  /// `false` also in flutter_test contexts without FRB.
  bool get _pkcs11Available {
    if (isMobilePlatform) return false;
    try {
      return rust_pkcs11.pkcs11IsAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final store = ref.read(sshKeysProvider.notifier);
    try {
      final keys = await store.loadAllMetadata();
      if (mounted) {
        setState(() {
          _keys = keys.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _keys = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      children: [
        _buildToolbar(s),
        const Divider(height: 1),
        Expanded(child: _buildBody(s)),
      ],
    );
  }

  Widget _buildToolbar(S s) {
    // Three discrete actions in the order the user expects to reach
    // for them:
    //   1. Add Key     — paste-and-label dialog. Fastest path when
    //                    the user already has the PEM in the
    //                    clipboard.
    //   2. Import Key  — native file picker. On systems where the
    //                    picker is unavailable (WSL without an
    //                    explorer package, some hardened Linux
    //                    containers) this degrades to a toast;
    //                    the user can still use Add Key.
    //   3. Generate    — fresh in-app key.
    // Earlier builds folded Add + Import into a single "Import"
    // dialog with a file-picker button on top of the paste
    // textarea. That put the file picker and paste flows one indent
    // apart from each other and made the picker failure mode read
    // as "this key is invalid" instead of "no picker available".
    return AppCollectionToolbar(
      hasItems: _keys.isNotEmpty,
      // Search + count mirror the snippet / tag manager toolbars so
      // every collection dialog reads the same way. Without the search
      // field the key list layout drifted visually from snippets even
      // though both use AppCollectionToolbar.
      search: AppDataSearchBar(
        onChanged: (v) => setState(() => _filter = v),
        hintText: s.search,
      ),
      countLabel: s.keyCount(_keys.length),
      actions: [
        _ToolbarButton(
          icon: Icons.edit_outlined,
          label: s.addKey,
          onTap: _addKey,
        ),
        _ToolbarButton(
          icon: Icons.file_download_outlined,
          label: s.importKey,
          onTap: _importKey,
        ),
        // Hardware-key (sk-*) import. Gated on the direct CTAP2 HID
        // path being reachable; disabled with a tap-toast reason
        // when not (Linux without udev rules, mobile / macOS without
        // the Apple entitlement). The `try` guards flutter_test
        // contexts where FRB is not loaded — the probe falls back
        // to "not available" rather than throwing through the build.
        _ToolbarButton(
          icon: Icons.usb,
          label: s.hardwareKeyImport,
          tooltip: _fido2Available
              ? s.hardwareKeyImport
              : s.hardwareKeyUnsupported,
          onTap: _fido2Available ? _importHardwareKey : null,
        ),
        // PKCS#11 smart-card / token import. Capability-ladder rung 3
        // on desktop (native Cryptoki via `dlopen`); rung 4 on mobile
        // (disabled with `pkcs11HwUnavailableMobile` tooltip — Android
        // has no compatible vendor `.so` ABI, iOS sandbox forbids
        // `dlopen` of arbitrary `.dylib`).
        _ToolbarButton(
          icon: Icons.memory,
          label: s.pkcs11AddTitle,
          tooltip: _pkcs11Available
              ? s.pkcs11AddTitle
              : s.pkcs11HwUnavailableMobile,
          onTap: _pkcs11Available ? _importPkcs11Key : null,
        ),
        // Apple Secure Enclave generate. Capability-ladder rung 3 on
        // macOS / iOS (native `SecKeyCreateRandomKey`); rung 4 elsewhere
        // (toolbar action hidden — the underlying chip doesn't exist
        // on Linux / Windows / Android). On ad-hoc-signed dev builds
        // the action stays enabled but the wizard's probe step routes
        // the user at the code-signing reason.
        if (isApplePlatform)
          _ToolbarButton(
            icon: Icons.shield_outlined,
            label: s.sshKeyAddHardwareBound,
            tooltip: s.sshKeyAddHardwareBound,
            onTap: _generateEnclaveKey,
          ),
        // Windows Hello (NCrypt / PCP) generate. Capability-ladder
        // rung 3 on Windows (native `NCryptCreatePersistedKey` against
        // the Microsoft Platform Crypto Provider); rung 4 elsewhere
        // (toolbar action hidden — the underlying provider only
        // exists on Windows). On hosts without Hello configured the
        // wizard probe step routes the user at the "configure first"
        // reason.
        if (isWindowsPlatform)
          _ToolbarButton(
            icon: Icons.shield_outlined,
            label: s.helloWizardTitle,
            tooltip: s.helloWizardTitle,
            onTap: _generateHelloKey,
          ),
        // TPM 2.0 SSH generate — Linux (`tss-esapi` driver) and
        // Windows (PCP silent variant, no UI policy). Apple
        // platforms route to the Secure Enclave wizard instead;
        // mobile platforms hide the entry (rung 4).
        if (Platform.isLinux || isWindowsPlatform) ...[
          _ToolbarButton(
            icon: Icons.memory,
            label: s.tpmSshTitle,
            tooltip: s.tpmSshTitle,
            onTap: _generateTpmKey,
          ),
          if (Platform.isLinux)
            _ToolbarButton(
              icon: Icons.file_download_outlined,
              label: s.tpmSshImportTitle,
              tooltip: s.tpmSshImportTitle,
              onTap: _importTpmBlob,
            ),
        ],
        // Android Hardware Keystore / StrongBox generate.
        // Capability-ladder rung 3 on Android (native AndroidKeyStore
        // JNI); rung 4 elsewhere — the underlying KeyStore provider
        // exists only on Android and the toolbar entry stays hidden
        // on every other platform.
        if (Platform.isAndroid)
          _ToolbarButton(
            icon: Icons.security,
            label: s.keystoreWizardTitle,
            tooltip: s.keystoreWizardTitle,
            onTap: _generateKeystoreKey,
          ),
        _ToolbarButton(
          icon: Icons.add,
          label: s.generateKey,
          onTap: _generateKey,
        ),
      ],
    );
  }

  List<SshKeyMetadata> _filtered() => filterSshKeys(_keys, _filter);

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_keys.isEmpty) {
      return AppEmptyState(message: s.noKeys);
    }
    final visible = _filtered();
    if (visible.isEmpty) {
      return AppEmptyState(message: s.noResults);
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildKeyEntry(s, visible[index]),
    );
  }

  Widget _buildKeyEntry(S s, SshKeyMetadata entry) {
    final hasCert = entry.hasCertificate;
    final expired = entry.validity?.isExpired ?? false;
    // FIDO2 sk-* rows: the v9 backend column is authoritative, but
    // we also fall back to the OpenSSH wire-format tag for rows
    // written before the migration filled the discriminator.
    final isFido2 =
        entry.isFido2 ||
        entry.keyType == 'sk-ed25519' ||
        entry.keyType == 'sk-ecdsa-p256' ||
        entry.keyType.startsWith('sk-ssh-') ||
        entry.keyType.startsWith('sk-ecdsa-sha2-');
    final isPkcs11 = entry.isPkcs11;
    final isEnclave = entry.isEnclave;
    final isHello = entry.isHello;
    final isTpm = entry.isTpm;
    final isKeystore = entry.isKeystore;
    final iconData = isFido2
        ? Icons.usb
        : (isPkcs11
              ? Icons.memory
              : (isEnclave
                    ? Icons.shield_outlined
                    : (isHello
                          ? Icons.shield_outlined
                          : (isTpm
                                ? Icons.memory
                                : (isKeystore
                                      ? Icons.security
                                      : Icons.vpn_key)))));
    return AppDataRow(
      icon: iconData,
      iconColor: entry.isGenerated ? AppTheme.accent : AppTheme.fgDim,
      title: entry.label,
      secondary:
          '${entry.keyType}  •  ${_formatDate(entry.createdAt)}'
          '${entry.isGenerated ? '  •  ${s.generated}' : ''}',
      secondaryMono: true,
      tertiary: hasCert ? _certTertiary(s, entry) : null,
      trailing: [
        if (isFido2)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _HardwareBadge(label: s.hardwareKeyBadge),
          ),
        if (isPkcs11)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Pkcs11Badge(
              label: s.pkcs11Badge,
              modulePath: entry.pkcs11ModulePath,
              tokenSerial: entry.pkcs11TokenSerial,
              objectLabel: entry.pkcs11ObjectLabel,
            ),
          ),
        if (isEnclave)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: EnclaveBadge(label: s.sshKeyEnclaveBadge),
          ),
        if (isHello)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: HelloBadge(
              label: s.helloBadge,
              credentialName: entry.helloCredentialName,
            ),
          ),
        if (isTpm)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TpmBadge(
              label: s.tpmSshBadge,
              provider: entry.tpmProvider,
              persistentHandle: entry.tpmHandle,
              pinRequired: entry.tpmPinRequired,
              // Windows-side TPM rows route through the PCP silent
              // path — surface the silent-warning copy in the badge
              // popover. Linux rows do not have a Hello-prompt
              // analogue so the warning is Windows-specific.
              silent: entry.tpmProvider == 'cng-pcp',
            ),
          ),
        if (isKeystore)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: KeystoreBadge(
              label: s.keystoreBadge,
              strongbox: entry.keystoreStrongBox,
              platform: entry.keystorePlatform,
            ),
          ),
        if (expired)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _ExpiredBadge(label: s.certExpired),
          ),
        AppIconButton(
          icon: Icons.content_copy,
          tooltip: s.publicKey,
          dense: true,
          onTap: () => _copyPublicKey(entry),
        ),
        if (hasCert)
          AppIconButton(
            icon: Icons.workspace_premium_outlined,
            tooltip: s.certRemove,
            dense: true,
            color: AppTheme.orange,
            onTap: () => _removeCertificate(entry),
          )
        else
          AppIconButton(
            icon: Icons.workspace_premium_outlined,
            tooltip: s.certImport,
            dense: true,
            onTap: () => _importCertificate(entry),
          ),
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: s.deleteKey,
          dense: true,
          color: AppTheme.red,
          onTap: () => _deleteKey(entry),
        ),
      ],
    );
  }

  /// Compose the cert tertiary line via the pure helper in
  /// `key_manager_logic.dart`. The localization labels + the
  /// localized `validity.to` date are resolved here so the helper
  /// stays Flutter-free for unit testing.
  String? _certTertiary(S s, SshKeyMetadata entry) {
    final to = entry.validity?.to;
    return buildCertTertiary(
      entry,
      CertRowLabels(
        principals: s.certPrincipals,
        validTo: s.certValidTo,
        criticalOptions: s.certCriticalOptions,
        localizedDate: to != null ? _formatDate(to.toLocal()) : '',
      ),
    );
  }

  void _copyPublicKey(SshKeyMetadata entry) {
    Clipboard.setData(ClipboardData(text: entry.publicKey));
    Toast.show(
      context,
      message: S.of(context).publicKeyCopied,
      level: ToastLevel.info,
    );
  }

  Future<void> _deleteKey(SshKeyMetadata entry) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.deleteKey,
        content: Text(s.deleteKeyConfirm(entry.label)),
        actions: [
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
            label: s.delete,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final store = ref.read(sshKeysProvider.notifier);
    await store.delete(entry.id);
    ref.invalidate(sshKeysProvider);
    // DB cascades `Sessions.keyId → NULL` on key deletion, but the in-memory
    // session list still holds the stale id. Reload so the tree picks up the
    // cleared keyId (and the invalid-session warning icon appears without
    // needing a second interaction).
    await ref.read(sessionProvider.notifier).load();
    await _loadKeys();
    if (mounted) {
      Toast.show(context, message: s.keyDeleted(entry.label));
    }
  }

  /// Pair an OpenSSH certificate to [entry]. Opens the file picker,
  /// parses the cert Rust-side via `keys_parse_openssh_cert`, then
  /// upserts the join row through `db_ssh_key_certificate_upsert`.
  /// The fingerprint pairing check (cert's `signature_key`
  /// fingerprint vs the stored key's public-key fingerprint) is
  /// **not** enforced here — russh validates the pairing server-
  /// side at userauth time. A mismatched cert would simply fail the
  /// next connect attempt with an auth error.
  Future<void> _importCertificate(SshKeyMetadata entry) async {
    final s = S.of(context);
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: s.certImportPickerTitle,
        allowMultiple: false,
        type: FileType.any,
      );
    } on MissingPluginException catch (e) {
      AppLogger.instance.log(
        'File picker missing on ${Platform.operatingSystem}: $e',
        name: 'KeyManager',
      );
      if (mounted) {
        Toast.show(
          context,
          message: s.filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    } catch (e) {
      AppLogger.instance.log('File picker failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: s.filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    }
    if (!mounted || picked == null) return;
    final path = picked.files.single.path;
    if (path == null) return;

    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      AppLogger.instance.log(
        'Cert read failed for <label>',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: s.errCertParse(e.toString()),
        level: ToastLevel.error,
      );
      return;
    }

    rust_keys.DbCertSummary summary;
    try {
      summary = rust_keys.keysParseOpensshCert(bytes: bytes);
    } catch (e) {
      AppLogger.instance.log(
        'Cert parse failed for <label>',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: s.errCertParse(e.toString()),
        level: ToastLevel.error,
      );
      return;
    }

    // Cert/key pair gate — server would surface a mismatch as a
    // generic auth failure at connect-time. Catching it on import
    // produces a tailored "wrong key" toast and avoids persisting
    // a cert that can never authenticate. Parse failure on either
    // side falls through to the generic `errCertParse` branch.
    bool matches;
    try {
      matches = rust_keys.keysCertMatchesKey(
        certBytes: bytes,
        pubkeyOpenssh: entry.publicKey,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Cert pair check failed for <label>',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: s.errCertParse(e.toString()),
        level: ToastLevel.error,
      );
      return;
    }
    if (!matches) {
      if (!mounted) return;
      Toast.show(
        context,
        message: s.errCertPairFingerprintMismatch,
        level: ToastLevel.error,
      );
      return;
    }

    final principalsJson = jsonEncode(summary.principals);
    final criticalJson = jsonEncode(summary.criticalOptions);
    try {
      await rust_db.dbSshKeyCertificateUpsert(
        rec: rust_db.DbSshKeyCertificate(
          keyId: entry.id,
          certificate: bytes,
          validAfter: summary.validAfterUnix,
          validBefore: summary.validBeforeUnix,
          principals: principalsJson,
          criticalOptions: criticalJson,
          fingerprint: summary.fingerprint,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Cert upsert failed for <label>',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: s.errCertParse(e.toString()),
        level: ToastLevel.error,
      );
      return;
    }

    ref.invalidate(sshKeysProvider);
    await _loadKeys();
  }

  Future<void> _removeCertificate(SshKeyMetadata entry) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.certRemoveConfirmTitle,
        content: Text(s.certRemoveConfirmBody),
        actions: [
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
            label: s.certRemove,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await rust_db.dbSshKeyCertificateDelete(keyId: entry.id);
    } catch (e) {
      AppLogger.instance.log(
        'Cert delete failed for <label>',
        name: 'KeyManager',
        error: e,
      );
    }
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
  }

  Future<void> _generateKey() async {
    final result = await _GenerateKeyDialog.show(context);
    if (result == null || !mounted) return;

    final store = ref.read(sshKeysProvider.notifier);
    await store.save(result);
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (mounted) {
      Toast.show(
        context,
        message: S.of(context).keyGenerated(result.label),
        level: ToastLevel.success,
      );
    }
  }

  /// Paste-and-label path. Opens a plain dialog with a label input
  /// and a PEM textarea; nothing reaches the filesystem.
  Future<void> _addKey() async {
    final result = await _AddKeyDialog.show(context);
    if (result == null || !mounted) return;
    await _persistImportedKey(result.label, result.pem);
  }

  /// File-picker path. Opens the platform native picker, reads the
  /// file via `KeyFileHelper.tryReadPemKey`, then pops an edit
  /// dialog pre-filled with the filename so the user can rename the
  /// entry before saving. Errors that come from the picker itself
  /// (MissingPluginException on WSL, PlatformException on hardened
  /// sandboxes) are classified as "file picker unavailable" instead
  /// of the misleading "invalid PEM" copy the earlier implementation
  /// surfaced.
  Future<void> _importKey() async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: S.of(context).selectKeyFile,
        allowMultiple: false,
        type: FileType.any,
      );
    } on MissingPluginException catch (e) {
      AppLogger.instance.log(
        'File picker missing on ${Platform.operatingSystem}: $e',
        name: 'KeyManager',
      );
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    } catch (e) {
      AppLogger.instance.log('File picker failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    }
    if (!mounted || picked == null) return;
    final path = picked.files.single.path;
    if (path == null) return;
    String pem;
    try {
      final extracted = await KeyFileHelper.tryReadPemKey(path);
      pem =
          extracted ?? await rust_keys.keysReadTextForManualImport(path: path);
    } catch (e) {
      AppLogger.instance.log('Key file read failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).invalidPem,
          level: ToastLevel.error,
        );
      }
      return;
    }
    if (!mounted) return;
    // Prefill the label with the file name so the user can accept
    // the default with one click. The `_AddKeyDialog` shape is
    // reused for the label confirmation — same layout, same
    // validation, but the PEM is already filled in.
    final fileName = path.split(Platform.pathSeparator).last;
    final result = await _AddKeyDialog.show(
      context,
      initialLabel: fileName,
      initialPem: pem,
    );
    if (result == null || !mounted) return;
    await _persistImportedKey(result.label, result.pem);
  }

  /// File-picker path for FIDO2 hardware-bound (`sk-*`) keys. The
  /// file the user picks is the OpenSSH-armored `id_*_sk` private
  /// key produced by `ssh-keygen -t ed25519-sk` / `-t ecdsa-sk` —
  /// despite the "private" suffix, the file carries no signing
  /// material (the device keeps it). It carries the credential id +
  /// application + user-verification flag the connect path needs to
  /// route through `lfs_core::fido2::get_assertion`.
  Future<void> _importHardwareKey() async {
    final s = S.of(context);
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: s.hardwareKeyImport,
        allowMultiple: false,
        type: FileType.any,
      );
    } on MissingPluginException catch (e) {
      AppLogger.instance.log(
        'File picker missing on ${Platform.operatingSystem}: $e',
        name: 'KeyManager',
      );
      if (mounted) {
        Toast.show(
          context,
          message: s.filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    } catch (e) {
      AppLogger.instance.log('File picker failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: s.filePickerUnavailable,
          level: ToastLevel.error,
        );
      }
      return;
    }
    if (!mounted || picked == null) return;
    final path = picked.files.single.path;
    if (path == null) return;

    String pem;
    try {
      pem = await rust_keys.keysReadTextForManualImport(path: path);
    } catch (e) {
      AppLogger.instance.log(
        'Hardware key read failed: $e',
        name: 'KeyManager',
      );
      if (mounted) {
        Toast.show(context, message: s.invalidPem, level: ToastLevel.error);
      }
      return;
    }

    final rust_keys.DbSkKeyMetadata meta;
    try {
      meta = rust_keys.keysParseSkPrivateKey(pem: pem);
    } catch (e) {
      AppLogger.instance.log('sk-* parse failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: localizeError(s, e),
          level: ToastLevel.error,
        );
      }
      return;
    }
    if (!mounted) return;

    final fileName = path.split(Platform.pathSeparator).last;
    final entry = SshKeyEntry(
      id: const Uuid().v4(),
      label: fileName,
      // The "private" file carries no signing material — store it
      // verbatim so the row round-trips through .lfs export / import,
      // but the connect path never reads it back: the credential id +
      // application + UV flag are what drive `fido2_get_assertion`.
      privateKey: pem,
      publicKey: meta.publicOpenssh,
      keyType: meta.keyType,
      createdAt: DateTime.now(),
      credentialId: Uint8List.fromList(meta.credentialId),
      applicationString: meta.application,
      hasUserVerification: meta.hasUserVerification,
    );
    try {
      final store = ref.read(sshKeysProvider.notifier);
      await store.save(entry);
      ref.invalidate(sshKeysProvider);
      await _loadKeys();
      if (mounted) {
        Toast.show(
          context,
          message: s.keyImported(entry.label),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'Hardware key save failed: $e',
        name: 'KeyManager',
      );
      if (mounted) {
        Toast.show(
          context,
          message: localizeError(s, e),
          level: ToastLevel.error,
        );
      }
    }
  }

  /// PKCS#11 smart-card / token import. Opens the wizard dialog
  /// (`Pkcs11ImportDialog`) which walks the user through module →
  /// token → PIN → key picker → save. The row lands Rust-side as
  /// part of `pkcs11_import_key`; we only refresh the listing and
  /// surface the success toast.
  Future<void> _importPkcs11Key() async {
    final s = S.of(context);
    final Pkcs11ImportResult? result;
    try {
      result = await Pkcs11ImportDialog.show(context);
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 wizard failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
      return;
    }
    if (result == null || !mounted) return;
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (!mounted) return;
    Toast.show(
      context,
      message: s.pkcs11SaveSuccess,
      level: ToastLevel.success,
    );
  }

  /// Apple Secure Enclave key generation. Opens the wizard dialog
  /// ([EnclaveSshDialog]) which probes the chip, captures the auth-
  /// policy choice, fires `enclaveSshGenerate`, and surfaces the
  /// authorized_keys-shaped public-key line for the user to paste on
  /// the server. The row lands Rust-side inside the generate call;
  /// we only refresh the listing and surface the success toast.
  Future<void> _generateEnclaveKey() async {
    final s = S.of(context);
    final EnclaveSshResult? result;
    try {
      result = await EnclaveSshDialog.show(context);
    } catch (e) {
      AppLogger.instance.log(
        'enclave wizard failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
      return;
    }
    if (result == null || !mounted) return;
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (!mounted) return;
    Toast.show(
      context,
      message: s.keyImported(result.label),
      level: ToastLevel.success,
    );
  }

  /// Windows Hello (NCrypt / PCP) key generation. Opens the wizard
  /// dialog ([HelloSshDialog]) which probes the provider, captures
  /// the algorithm radio choice, fires `helloSshGenerate`, and
  /// surfaces the authorized_keys-shaped public-key line. The row
  /// lands Rust-side inside the generate call; we only refresh the
  /// listing and surface the success toast.
  Future<void> _generateHelloKey() async {
    final s = S.of(context);
    final HelloSshResult? result;
    try {
      result = await HelloSshDialog.show(context);
    } catch (e) {
      AppLogger.instance.log(
        'hello wizard failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
      return;
    }
    if (result == null || !mounted) return;
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (!mounted) return;
    Toast.show(
      context,
      message: s.keyImported(result.label),
      level: ToastLevel.success,
    );
  }

  /// TPM 2.0 (Linux ESAPI / Windows PCP silent) key generation.
  /// Opens [TpmSshDialog] which probes the chip, captures the
  /// algorithm + storage radio + optional PIN, fires
  /// `tpmSshGenerate`, and surfaces the `authorized_keys`-shaped
  /// public-key line. The row lands Rust-side inside the generate
  /// call; we only refresh the listing.
  Future<void> _generateTpmKey() async {
    final s = S.of(context);
    final TpmSshResult? result;
    try {
      result = await TpmSshDialog.show(context);
    } catch (e) {
      AppLogger.instance.log(
        'tpm wizard failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
      return;
    }
    if (result == null || !mounted) return;
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (!mounted) return;
    Toast.show(
      context,
      message: s.keyImported(result.label),
      level: ToastLevel.success,
    );
  }

  /// Opens [KeystoreSshDialog] which probes biometric / StrongBox
  /// capability, mints a fresh AndroidKeyStore-bound SSH key, and
  /// surfaces the `authorized_keys` line for paste. Android only —
  /// the toolbar entry hides on every other platform.
  Future<void> _generateKeystoreKey() async {
    final s = S.of(context);
    final KeystoreSshResult? result;
    try {
      result = await KeystoreSshDialog.show(context);
    } catch (e) {
      AppLogger.instance.log(
        'keystore wizard failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
      return;
    }
    if (result == null || !mounted) return;
    ref.invalidate(sshKeysProvider);
    await _loadKeys();
    if (!mounted) return;
    Toast.show(
      context,
      message: s.keyImported(result.label),
      level: ToastLevel.success,
    );
  }

  /// Import a wrapped `.tpm` file. Linux only — Windows CNG owns
  /// its own keystore and has no portable import shape.
  Future<void> _importTpmBlob() async {
    final s = S.of(context);
    try {
      final id = await const TpmImportHelper().pickAndImport(context);
      if (id == null || !mounted) return;
      ref.invalidate(sshKeysProvider);
      await _loadKeys();
      if (!mounted) return;
      Toast.show(
        context,
        message: s.keyImported(id),
        level: ToastLevel.success,
      );
    } catch (e) {
      AppLogger.instance.log(
        'tpm import failed: $e',
        name: 'KeyManager',
        error: e,
      );
      if (!mounted) return;
      Toast.show(
        context,
        message: localizeError(s, e),
        level: ToastLevel.error,
      );
    }
  }

  Future<void> _persistImportedKey(String label, String pem) async {
    try {
      final store = ref.read(sshKeysProvider.notifier);
      final entry = await store.importKey(pem, label);
      await store.save(entry);
      ref.invalidate(sshKeysProvider);
      await _loadKeys();
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).keyImported(entry.label),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('Key import failed: $e', name: 'KeyManager');
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).invalidPem,
          level: ToastLevel.error,
        );
      }
    }
  }

  /// Format a date as `YYYY-MM-DD` via
  /// `lfs_core::format::format_date`.
  String _formatDate(DateTime dt) =>
      rust_format.formatDate(year: dt.year, month: dt.month, day: dt.day);
}

/// Dialog wrapper for standalone use (mobile settings).
class KeyManagerDialog extends StatelessWidget {
  const KeyManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(context, builder: (_) => const KeyManagerDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).sshKeys,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 400, child: KeyManagerPanel()),
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
    );
  }
}

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
            children: SshKeyType.values.where((t) => !t.isHardwareBound).map((
              t,
            ) {
              final selected = t == _type;
              return ChoiceChip(
                label: Text(t.label),
                selected: selected,
                onSelected: _generating
                    ? null
                    : (_) => setState(() => _type = t),
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

// ── Toolbar button ──────────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = AppButton.secondary(
      label: label,
      icon: icon,
      onTap: onTap,
      dense: true,
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

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

/// "Hardware-bound (FIDO2)" pill rendered in the key-manager row's
/// trailing slot when the stored key is an `sk-*` variant. Visual
/// contract mirrors `_ExpiredBadge` so the row tail reads
/// consistently when multiple badges co-exist.
class _HardwareBadge extends StatelessWidget {
  final String label;
  const _HardwareBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.16),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb, size: 12, color: AppTheme.accent),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppFonts.inter(
              fontSize: AppFonts.xxs,
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
