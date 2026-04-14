import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/snippets/snippet.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/snippet_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Dialog for managing command snippets — list, add, edit, delete.
class SnippetManagerDialog extends ConsumerStatefulWidget {
  const SnippetManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(
      context,
      builder: (_) => const SnippetManagerDialog(),
    );
  }

  @override
  ConsumerState<SnippetManagerDialog> createState() =>
      _SnippetManagerDialogState();
}

class _SnippetManagerDialogState extends ConsumerState<SnippetManagerDialog> {
  List<Snippet> _snippets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(snippetStoreProvider);
    final snippets = await store.loadAll();
    if (mounted) {
      setState(() {
        _snippets = snippets;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.snippets,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 400,
        child: Column(
          children: [
            _buildToolbar(s),
            const Divider(height: 1),
            Expanded(child: _buildBody(s)),
          ],
        ),
      ),
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
    );
  }

  Widget _buildToolbar(S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            s.snippetCount(_snippets.length),
            style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _addSnippet,
            icon: const Icon(Icons.add, size: 16),
            label: Text(s.addSnippet, style: TextStyle(fontSize: AppFonts.sm)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_snippets.isEmpty) {
      return Center(
        child: Text(
          s.noSnippets,
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
      );
    }
    return ListView.separated(
      itemCount: _snippets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(s, _snippets[index]),
    );
  }

  Widget _buildEntry(S s, Snippet snippet) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.code, size: 16, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snippet.title,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snippet.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
                if (snippet.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    snippet.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 14),
            tooltip: s.copy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _copyCommand(snippet),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 14),
            tooltip: s.editSnippet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _editSnippet(snippet),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: AppTheme.red),
            tooltip: s.deleteSnippet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _deleteSnippet(snippet),
          ),
        ],
      ),
    );
  }

  void _copyCommand(Snippet snippet) {
    Clipboard.setData(ClipboardData(text: snippet.command));
    Toast.show(
      context,
      message: S.of(context).commandCopied,
      level: ToastLevel.info,
    );
  }

  Future<void> _addSnippet() async {
    final result = await _SnippetEditDialog.show(context);
    if (result == null || !mounted) return;
    final store = ref.read(snippetStoreProvider);
    await store.add(result);
    ref.invalidate(snippetsProvider);
    await _load();
    if (mounted) {
      Toast.show(
        context,
        message: S.of(context).snippetSaved,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _editSnippet(Snippet snippet) async {
    final result = await _SnippetEditDialog.show(context, snippet: snippet);
    if (result == null || !mounted) return;
    final store = ref.read(snippetStoreProvider);
    await store.update(result);
    ref.invalidate(snippetsProvider);
    await _load();
    if (mounted) {
      Toast.show(
        context,
        message: S.of(context).snippetSaved,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _deleteSnippet(Snippet snippet) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.deleteSnippet,
        content: Text(s.deleteSnippetConfirm(snippet.title)),
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
    final store = ref.read(snippetStoreProvider);
    await store.delete(snippet.id);
    ref.invalidate(snippetsProvider);
    await _load();
    if (mounted) {
      Toast.show(context, message: s.snippetDeleted(snippet.title));
    }
  }
}

// ── Add / Edit Snippet Dialog ──────────────────────────────────────

class _SnippetEditDialog extends StatefulWidget {
  final Snippet? snippet;

  const _SnippetEditDialog({this.snippet});

  static Future<Snippet?> show(BuildContext context, {Snippet? snippet}) {
    return AppDialog.show<Snippet>(
      context,
      builder: (_) => _SnippetEditDialog(snippet: snippet),
    );
  }

  @override
  State<_SnippetEditDialog> createState() => _SnippetEditDialogState();
}

class _SnippetEditDialogState extends State<_SnippetEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _commandCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.snippet?.title ?? '');
    _commandCtrl = TextEditingController(text: widget.snippet?.command ?? '');
    _descCtrl = TextEditingController(text: widget.snippet?.description ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _commandCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isEdit = widget.snippet != null;
    return AppDialog(
      title: isEdit ? s.editSnippet : s.addSnippet,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: s.snippetTitle,
              hintText: s.snippetTitleHint,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commandCtrl,
            maxLines: 3,
            style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
            decoration: InputDecoration(
              labelText: s.snippetCommand,
              hintText: s.snippetCommandHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: s.snippetDescription,
              hintText: s.snippetDescriptionHint,
            ),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: s.save, onTap: _save),
      ],
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final command = _commandCtrl.text.trim();
    if (title.isEmpty || command.isEmpty) return;

    final snippet = widget.snippet != null
        ? widget.snippet!.copyWith(
            title: title,
            command: command,
            description: _descCtrl.text.trim(),
          )
        : Snippet(
            title: title,
            command: command,
            description: _descCtrl.text.trim(),
          );
    Navigator.pop(context, snippet);
  }
}
