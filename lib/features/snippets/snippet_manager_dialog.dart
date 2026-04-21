import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/snippets/snippet.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/session_provider.dart';
import '../../providers/snippet_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_collection_toolbar.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/toast.dart';

/// Embeddable snippet manager — toolbar + list with CRUD.
///
/// Used standalone inside [SnippetManagerDialog] (mobile) and embedded in
/// the desktop Tools dialog.
class SnippetManagerPanel extends ConsumerStatefulWidget {
  const SnippetManagerPanel({super.key});

  @override
  ConsumerState<SnippetManagerPanel> createState() =>
      _SnippetManagerPanelState();
}

class _SnippetManagerPanelState extends ConsumerState<SnippetManagerPanel> {
  List<Snippet> _snippets = [];
  bool _loading = true;
  String _filter = '';

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

  List<Snippet> _filtered() {
    if (_filter.isEmpty) return _snippets;
    final needle = _filter.toLowerCase();
    return _snippets.where((sn) {
      return sn.title.toLowerCase().contains(needle) ||
          sn.command.toLowerCase().contains(needle) ||
          sn.description.toLowerCase().contains(needle);
    }).toList();
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
      hasItems: _snippets.isNotEmpty,
      search: AppDataSearchBar(
        onChanged: (v) => setState(() => _filter = v),
        hintText: s.search,
      ),
      countLabel: s.snippetCount(_snippets.length),
      actions: [
        TextButton.icon(
          onPressed: _addSnippet,
          icon: const Icon(Icons.add, size: 16),
          label: Text(s.addSnippet, style: TextStyle(fontSize: AppFonts.sm)),
        ),
      ],
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_snippets.isEmpty) {
      return AppEmptyState(message: s.noSnippets);
    }
    final visible = _filtered();
    if (visible.isEmpty) {
      return AppEmptyState(message: s.noResults);
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(s, visible[index]),
    );
  }

  Widget _buildEntry(S s, Snippet snippet) {
    return AppDataRow(
      icon: Icons.code,
      title: snippet.title,
      secondary: snippet.command,
      secondaryMono: true,
      tertiary: snippet.description.isEmpty ? null : snippet.description,
      trailing: [
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
    // SessionSnippets cascades on FK; reload so the in-memory session list
    // doesn't hold stale snippet links in its derived UI state.
    await ref.read(sessionProvider.notifier).load();
    await _load();
    if (mounted) {
      Toast.show(context, message: s.snippetDeleted(snippet.title));
    }
  }
}

/// Dialog wrapper for standalone use (mobile settings).
class SnippetManagerDialog extends StatelessWidget {
  const SnippetManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(
      context,
      builder: (_) => const SnippetManagerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).snippets,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 400, child: SnippetManagerPanel()),
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
    );
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
