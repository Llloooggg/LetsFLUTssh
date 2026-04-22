import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/import/key_file_helper.dart';
import '../../core/security/key_store.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../widgets/app_collection_toolbar.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/toast.dart';

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
  List<SshKeyEntry> _keys = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final store = ref.read(keyStoreProvider);
    final keys = await store.loadAllSafe();
    if (mounted) {
      setState(() {
        _keys = keys.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _loading = false;
      });
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
        _ToolbarButton(
          icon: Icons.add,
          label: s.generateKey,
          onTap: _generateKey,
        ),
      ],
    );
  }

  List<SshKeyEntry> _filtered() {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return _keys;
    return _keys
        .where(
          (k) =>
              k.label.toLowerCase().contains(q) ||
              k.keyType.toLowerCase().contains(q),
        )
        .toList();
  }

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

  Widget _buildKeyEntry(S s, SshKeyEntry entry) {
    return AppDataRow(
      icon: Icons.vpn_key,
      iconColor: entry.isGenerated ? AppTheme.accent : AppTheme.fgDim,
      title: entry.label,
      secondary:
          '${entry.keyType}  •  ${_formatDate(entry.createdAt)}'
          '${entry.isGenerated ? '  •  ${s.generated}' : ''}',
      secondaryMono: true,
      trailing: [
        AppIconButton(
          icon: Icons.content_copy,
          tooltip: s.publicKey,
          dense: true,
          onTap: () => _copyPublicKey(entry),
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

  void _copyPublicKey(SshKeyEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.publicKey));
    Toast.show(
      context,
      message: S.of(context).publicKeyCopied,
      level: ToastLevel.info,
    );
  }

  Future<void> _deleteKey(SshKeyEntry entry) async {
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
    final store = ref.read(keyStoreProvider);
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

  Future<void> _generateKey() async {
    final result = await _GenerateKeyDialog.show(context);
    if (result == null || !mounted) return;

    final store = ref.read(keyStoreProvider);
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
      final extracted = KeyFileHelper.tryReadPemKey(path);
      pem = extracted ?? await File(path).readAsString();
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

  Future<void> _persistImportedKey(String label, String pem) async {
    try {
      final store = ref.read(keyStoreProvider);
      final entry = store.importKey(pem, label);
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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')}';
  }
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
          const SizedBox(height: 16),
          Text(s.selectKeyType, style: TextStyle(fontSize: AppFonts.sm)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: SshKeyType.values.map((t) {
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
        () => KeyStore.generateKeyPair(_type, label),
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
          const SizedBox(height: 12),
          TextField(
            controller: _pemCtrl,
            maxLines: 5,
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
  final VoidCallback? onTap;

  const _ToolbarButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      label: label,
      icon: icon,
      onTap: onTap,
      dense: true,
    );
  }
}
