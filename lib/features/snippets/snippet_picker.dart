import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/snippets/snippet.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/snippet_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Snippet picker dialog — select a snippet to execute in terminal.
///
/// Shows pinned snippets for the session first, then all snippets.
/// Returns the command string to send, or null if cancelled.
class SnippetPicker extends ConsumerStatefulWidget {
  final String? sessionId;

  const SnippetPicker({super.key, this.sessionId});

  /// Show the picker and return the selected command, or null.
  static Future<String?> show(BuildContext context, {String? sessionId}) {
    return AppDialog.show<String>(
      context,
      builder: (_) => SnippetPicker(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<SnippetPicker> createState() => _SnippetPickerState();
}

class _SnippetPickerState extends ConsumerState<SnippetPicker> {
  List<Snippet> _pinned = [];
  List<Snippet> _all = [];
  Set<String> _pinnedIds = {};
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(snippetStoreProvider);
    final all = await store.loadAll();
    List<Snippet> pinned = [];
    Set<String> pinnedIds = {};
    if (widget.sessionId != null) {
      pinned = await store.loadForSession(widget.sessionId!);
      pinnedIds = pinned.map((s) => s.id).toSet();
    }
    if (mounted) {
      setState(() {
        _all = all;
        _pinned = pinned;
        _pinnedIds = pinnedIds;
        _loading = false;
      });
    }
  }

  bool _matches(Snippet snippet) {
    if (_filter.isEmpty) return true;
    final needle = _filter.toLowerCase();
    return snippet.title.toLowerCase().contains(needle) ||
        snippet.command.toLowerCase().contains(needle) ||
        snippet.description.toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.snippets,
      maxWidth: 500,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 350,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AppDataSearchBar(
                onChanged: (v) => setState(() => _filter = v),
                hintText: s.search,
                autofocus: true,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(s)),
          ],
        ),
      ),
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_all.isEmpty) {
      return Center(
        child: Text(
          s.noSnippets,
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
      );
    }

    final filteredPinned = _pinned.where(_matches).toList();
    final filteredUnpinned = _all
        .where((sn) => !_pinnedIds.contains(sn.id) && _matches(sn))
        .toList();
    if (filteredPinned.isEmpty && filteredUnpinned.isEmpty) {
      return Center(
        child: Text(
          s.noResults,
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
      );
    }
    final hasPinned = filteredPinned.isNotEmpty;

    return ListView(
      children: [
        if (hasPinned) ...[
          _sectionHeader(s.pinnedSnippets),
          for (final snippet in filteredPinned)
            _snippetTile(snippet, pinned: true),
          if (filteredUnpinned.isNotEmpty) _sectionHeader(s.allSnippets),
        ],
        for (final snippet in filteredUnpinned)
          _snippetTile(snippet, pinned: false),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.xs,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
          color: AppTheme.fgFaint,
        ),
      ),
    );
  }

  Widget _snippetTile(Snippet snippet, {required bool pinned}) {
    final s = S.of(context);
    return AppDataRow(
      icon: pinned ? Icons.push_pin : Icons.code,
      iconColor: pinned ? AppTheme.accent : AppTheme.fgDim,
      title: snippet.title,
      secondary: snippet.command,
      secondaryMono: true,
      onTap: () => Navigator.pop(context, snippet.command),
      trailing: [
        if (widget.sessionId != null)
          IconButton(
            icon: Icon(
              pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 14,
              color: pinned ? AppTheme.accent : AppTheme.fgFaint,
            ),
            tooltip: pinned ? s.unpinFromSession : s.pinToSession,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _togglePin(snippet, pinned),
          ),
        IconButton(
          icon: const Icon(Icons.content_copy, size: 14),
          tooltip: s.copy,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: snippet.command));
            Toast.show(
              context,
              message: s.commandCopied,
              level: ToastLevel.info,
            );
          },
        ),
      ],
    );
  }

  Future<void> _togglePin(Snippet snippet, bool currentlyPinned) async {
    final store = ref.read(snippetStoreProvider);
    final sid = widget.sessionId!;
    if (currentlyPinned) {
      await store.unlinkFromSession(snippet.id, sid);
    } else {
      await store.linkToSession(snippet.id, sid);
    }
    ref.invalidate(sessionSnippetsProvider(sid));
    await _load();
  }
}
