import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/key_store.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/key_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../widgets/app_dialog.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            s.keyCount(_keys.length),
            style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          ),
          const Spacer(),
          _ToolbarButton(
            icon: Icons.file_download_outlined,
            label: s.importKey,
            onTap: _importKey,
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.add,
            label: s.generateKey,
            onTap: _generateKey,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_keys.isEmpty) {
      return Center(
        child: Text(
          s.noKeys,
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
      );
    }
    return ListView.separated(
      itemCount: _keys.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildKeyEntry(s, _keys[index]),
    );
  }

  Widget _buildKeyEntry(S s, SshKeyEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.vpn_key,
            size: 16,
            color: entry.isGenerated ? AppTheme.accent : AppTheme.fgDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.keyType}  •  ${_formatDate(entry.createdAt)}'
                  '${entry.isGenerated ? '  •  ${s.generated}' : ''}',
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 14),
            tooltip: s.publicKey,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _copyPublicKey(entry),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: AppTheme.red),
            tooltip: s.deleteKey,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _deleteKey(entry),
          ),
        ],
      ),
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
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppDialogAction.destructive(
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

  Future<void> _importKey() async {
    final result = await _ImportKeyDialog.show(context);
    if (result == null || !mounted) return;

    try {
      final store = ref.read(keyStoreProvider);
      final entry = store.importKey(result.pem, result.label);
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
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
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
        AppDialogAction.cancel(
          onTap: _generating ? null : () => Navigator.pop(context),
        ),
        AppDialogAction.primary(
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

// ── Import Key Dialog ───────────────────────────────────────────────

class _ImportKeyDialog extends StatefulWidget {
  const _ImportKeyDialog();

  static Future<({String label, String pem})?> show(BuildContext context) {
    return AppDialog.show<({String label, String pem})>(
      context,
      builder: (_) => const _ImportKeyDialog(),
    );
  }

  @override
  State<_ImportKeyDialog> createState() => _ImportKeyDialogState();
}

class _ImportKeyDialogState extends State<_ImportKeyDialog> {
  final _labelCtrl = TextEditingController();
  final _pemCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _pemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.importKey,
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
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: s.importKey, onTap: _doImport),
      ],
    );
  }

  void _doImport() {
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
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: TextStyle(fontSize: AppFonts.sm)),
    );
  }
}
