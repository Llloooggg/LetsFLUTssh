import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/import/key_file_helper.dart';
import '../../core/security/hardware_tier.dart';
import '../../core/security/ssh_key.dart';
import 'key_manager_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/key_provider.dart';
import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/fido2.dart' as rust_fido2;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/keys.dart' as rust_keys;
import '../../src/rust/api/pkcs11.dart' as rust_pkcs11;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/platform.dart';
import '../../widgets/core/app_collection_toolbar.dart';
import '../../widgets/core/app_data_row.dart';
import '../../widgets/core/app_data_search_bar.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_icon_button.dart';
import '../../widgets/core/app_picker_chip.dart';
import '../../utils/secret_controller.dart';
import '../../widgets/core/app_empty_state.dart';
import '../../widgets/ssh_keys/enclave_ssh_dialog.dart';
import '../../widgets/ssh_keys/hardware_key_badge.dart';
import '../../widgets/ssh_keys/hello_ssh_dialog.dart';
import '../../widgets/ssh_keys/keystore_ssh_dialog.dart';
import '../../widgets/ssh_keys/pkcs11_import_dialog.dart';
import '../../widgets/core/toast.dart';
import '../../widgets/ssh_keys/tpm_ssh_dialog.dart';

part 'key_manager_dialog_add.dart';
part 'key_manager_dialog_rows.dart';

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
    final store = ref.read(sshKeysMutatorProvider);
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
    return AppCollectionToolbar(
      hasItems: _keys.isNotEmpty,
      // Search + count mirror the snippet / tag manager toolbars so
      // every collection dialog reads the same way.
      search: AppDataSearchBar(
        onChanged: (v) => setState(() => _filter = v),
        hintText: s.search,
      ),
      countLabel: s.keyCount(_keys.length),
      // Single `+ Add ▾` trigger collapses the import / generate /
      // hardware-tier / smart-card paths into one popup so the
      // toolbar stays a flat decision surface (one button) instead
      // of a horizontal stack of 4–9 icon+label rectangles. Items
      // unavailable on the host platform (FIDO2 without HID access,
      // PKCS#11 on mobile, unsupported hardware tiers) drop from
      // the menu rather than render disabled — action menus hide,
      // configuration surfaces disable (CLAUDE.md UI rule).
      actions: [_buildAddMenuButton(s)],
    );
  }

  /// `+ Add ▾` popup trigger styled to match `AppButton.secondary
  /// (dense: true)` so it sits visually beside the search bar at the
  /// same height the previous icon+label buttons did.
  Widget _buildAddMenuButton(S s) {
    return PopupMenuButton<_AddKeyAction>(
      onSelected: _dispatchAddAction,
      tooltip: '',
      // `PopupMenuButton` owns its own `AnimationController` and
      // ignores the root `MediaQuery(disableAnimations: true)` —
      // opt out so the open matches the project-wide hard-off.
      popUpAnimationStyle: AnimationStyle.noAnimation,
      offset: const Offset(0, AppTheme.controlHeightXs),
      constraints: const BoxConstraints(
        minWidth: 220,
        maxHeight: AppTheme.popupMaxHeight,
      ),
      color: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
      itemBuilder: (_) => _buildAddMenuItems(s),
      child: _AddMenuTrigger(label: s.addKey),
    );
  }

  /// Build the popup item list. Common paths (paste / file / generate)
  /// always render; hardware-backed paths are folded under a divider
  /// in the order `supportedHardwareTiersForPlatform()` returns them
  /// so a future tier addition lands in the same shape without a
  /// new layout decision.
  List<PopupMenuEntry<_AddKeyAction>> _buildAddMenuItems(S s) {
    final items = <PopupMenuEntry<_AddKeyAction>>[
      _addMenuItem(
        _AddKeyAction.pastePem,
        Icons.edit_outlined,
        s.addKeyMenuPaste,
      ),
      _addMenuItem(
        _AddKeyAction.importFile,
        Icons.file_download_outlined,
        s.importKey,
      ),
      _addMenuItem(_AddKeyAction.generate, Icons.add, s.generateKey),
    ];
    final hardware = _buildHardwareMenuItems(s);
    if (hardware.isNotEmpty) {
      items.add(const PopupMenuDivider());
      items.addAll(hardware);
    }
    return items;
  }

  /// Hardware-tier menu items for the current platform plus the
  /// FIDO2 + PKCS#11 entries when the host's runtime probes accept
  /// them. Per-tier wizard probes (Enclave entitlement, Hello
  /// configuration, TPM presence) still gate the actual mint call.
  List<PopupMenuEntry<_AddKeyAction>> _buildHardwareMenuItems(S s) {
    final entries = <PopupMenuEntry<_AddKeyAction>>[];
    for (final tier in supportedHardwareTiersForPlatform()) {
      switch (tier) {
        case HardwareTier.appleEnclave:
          entries.add(
            _addMenuItem(
              _AddKeyAction.hwEnclave,
              Icons.shield_outlined,
              s.sshKeyAddHardwareBound,
            ),
          );
        case HardwareTier.windowsHello:
          entries.add(
            _addMenuItem(
              _AddKeyAction.hwHello,
              Icons.shield_outlined,
              s.helloWizardTitle,
            ),
          );
        case HardwareTier.tpm:
          entries.add(
            _addMenuItem(_AddKeyAction.hwTpm, Icons.memory, s.tpmSshTitle),
          );
          // Linux owns the only portable TPM blob format the app
          // ingests; Windows CNG keystore is opaque and has no
          // import path.
          if (Platform.isLinux) {
            entries.add(
              _addMenuItem(
                _AddKeyAction.hwTpmImport,
                Icons.file_download_outlined,
                s.tpmSshImportTitle,
              ),
            );
          }
        case HardwareTier.androidKeystore:
          entries.add(
            _addMenuItem(
              _AddKeyAction.hwKeystore,
              Icons.security,
              s.keystoreWizardTitle,
            ),
          );
      }
    }
    if (_fido2Available) {
      entries.add(
        _addMenuItem(_AddKeyAction.hwFido2, Icons.usb, s.hardwareKeyImport),
      );
    }
    if (_pkcs11Available) {
      entries.add(
        _addMenuItem(_AddKeyAction.pkcs11, Icons.memory, s.pkcs11AddTitle),
      );
    }
    return entries;
  }

  PopupMenuItem<_AddKeyAction> _addMenuItem(
    _AddKeyAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_AddKeyAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.fgDim),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
            ),
          ),
        ],
      ),
    );
  }

  void _dispatchAddAction(_AddKeyAction action) {
    switch (action) {
      case _AddKeyAction.pastePem:
        _addKey();
      case _AddKeyAction.importFile:
        _importKey();
      case _AddKeyAction.generate:
        _generateKey();
      case _AddKeyAction.hwEnclave:
        _generateEnclaveKey();
      case _AddKeyAction.hwHello:
        _generateHelloKey();
      case _AddKeyAction.hwTpm:
        _generateTpmKey();
      case _AddKeyAction.hwTpmImport:
        _importTpmBlob();
      case _AddKeyAction.hwKeystore:
        _generateKeystoreKey();
      case _AddKeyAction.hwFido2:
        _importHardwareKey();
      case _AddKeyAction.pkcs11:
        _importPkcs11Key();
    }
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
    // Stub rows landed via `.lfs` import / WebDAV sync for a
    // device-bound backend — only the public half travelled. The
    // row renders desaturated, the secondary line carries the
    // "re-generate here" hint, and the action set swaps to
    // [Re-generate, Remove] (no copy / cert / delete because the
    // private side is bound to the original device).
    final isStub = entry.importedAsStub;
    return Opacity(
      opacity: isStub ? 0.55 : 1.0,
      child: AppDataRow(
        icon: _rowIcon(entry),
        iconColor: entry.isGenerated ? AppTheme.accent : AppTheme.fgDim,
        title: entry.label,
        secondary: isStub
            ? s.hardwareKeyStubSubtitle
            : '${entry.keyType}  •  ${_formatDate(entry.createdAt)}'
                  '${entry.isGenerated ? '  •  ${s.generated}' : ''}',
        secondaryMono: !isStub,
        tertiary: entry.hasCertificate ? _certTertiary(s, entry) : null,
        trailing: [
          _KeyRowBadges(s: s, entry: entry),
          _KeyRowActions(
            s: s,
            entry: entry,
            onRegenerateStub: () => _regenerateStub(entry),
            onCopyPublicKey: () => _copyPublicKey(entry),
            onImportCertificate: () => _importCertificate(entry),
            onRemoveCertificate: () => _removeCertificate(entry),
            onDelete: () => _deleteKey(entry),
          ),
        ],
      ),
    );
  }

  /// Pick the row's left-side icon from the backend discriminator.
  /// `sk-*` keyType strings fall through the `isFido2` flag — see
  /// [_KeyRowBadges] for the matching fallback rationale.
  IconData _rowIcon(SshKeyMetadata entry) {
    if (_isFido2Row(entry)) return Icons.usb;
    if (entry.isPkcs11) return Icons.memory;
    if (entry.isEnclave) return Icons.shield_outlined;
    if (entry.isHello) return Icons.shield_outlined;
    if (entry.isTpm) return Icons.memory;
    if (entry.isKeystore) return Icons.security;
    return Icons.vpn_key;
  }

  /// Open the per-backend wizard so the user mints a fresh
  /// hardware-backed key. On wizard success the wizard upserts a
  /// full row whose label / id is the user's choice; the original
  /// stub stays in the table until the user removes it explicitly
  /// (the actions live side by side on the row). Dispatch is by
  /// backend: Enclave, Hello, TPM, Keystore each open their own
  /// wizard dialog seeded with the stub's label so the user does
  /// not retype the name from the source device.
  Future<void> _regenerateStub(SshKeyMetadata entry) async {
    final label = entry.label;
    if (entry.isEnclave) {
      await EnclaveSshDialog.show(context, initialLabel: label);
    } else if (entry.isHello) {
      await HelloSshDialog.show(context, initialLabel: label);
    } else if (entry.isTpm) {
      await TpmSshDialog.show(context, initialLabel: label);
    } else if (entry.isKeystore) {
      await KeystoreSshDialog.show(context, initialLabel: label);
    }
    if (!mounted) return;
    await _loadKeys();
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
    final store = ref.read(sshKeysMutatorProvider);
    await store.delete(entry.id);
    // DB cascades `Sessions.keyId → NULL` on key deletion;
    // `dbSshKeysDelete` Rust-side publishes `SessionsChanged` so
    // the workspace stream re-fetches and the tree picks up the
    // cleared keyId without a Dart-side reload.
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
      bytes = Uint8List.fromList(
        await rust_keys.keysReadCertBytesForImport(path: path),
      );
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

    try {
      await rust_db.dbSshKeyCertificateUpsert(
        rec: rust_db.DbSshKeyCertificate(
          keyId: entry.id,
          certificate: bytes,
          validAfter: summary.validAfterUnix,
          validBefore: summary.validBeforeUnix,
          principals: summary.principals,
          criticalOptions: summary.criticalOptions,
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
    await _loadKeys();
  }

  Future<void> _generateKey() async {
    final result = await _GenerateKeyDialog.show(context);
    if (result == null || !mounted) return;

    final store = ref.read(sshKeysMutatorProvider);
    await store.save(result);
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
      final store = ref.read(sshKeysMutatorProvider);
      await store.save(entry);
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
      final store = ref.read(sshKeysMutatorProvider);
      final entry = await store.importKey(pem, label);
      await store.save(entry);
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
