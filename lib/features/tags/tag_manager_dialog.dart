import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/session_provider.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Embeddable tag manager — toolbar + list with CRUD.
///
/// Used standalone inside [TagManagerDialog] (mobile) and embedded in
/// the desktop Tools dialog.
class TagManagerPanel extends ConsumerStatefulWidget {
  const TagManagerPanel({super.key});

  @override
  ConsumerState<TagManagerPanel> createState() => _TagManagerPanelState();
}

class _TagManagerPanelState extends ConsumerState<TagManagerPanel> {
  List<Tag> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(tagStoreProvider);
    final tags = await store.loadAll();
    if (mounted) {
      setState(() {
        _tags = tags;
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
            s.tagCount(_tags.length),
            style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _addTag,
            icon: const Icon(Icons.add, size: 16),
            label: Text(s.addTag, style: TextStyle(fontSize: AppFonts.sm)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_tags.isEmpty) {
      return Center(
        child: Text(
          s.noTags,
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
      );
    }
    return ListView.separated(
      itemCount: _tags.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(_tags[index]),
    );
  }

  Widget _buildEntry(Tag tag) {
    final s = S.of(context);
    final color = tag.colorValue ?? AppTheme.fgDim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tag.name,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: AppTheme.red),
            tooltip: s.deleteTag,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _deleteTag(tag),
          ),
        ],
      ),
    );
  }

  Future<void> _addTag() async {
    final result = await _AddTagDialog.show(context);
    if (result == null || !mounted) return;
    final store = ref.read(tagStoreProvider);
    await store.add(result);
    ref.invalidate(tagsProvider);
    await _load();
    if (mounted) {
      Toast.show(
        context,
        message: S.of(context).tagCreated,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.deleteTag,
        content: Text(s.deleteTagConfirm(tag.name)),
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
    final store = ref.read(tagStoreProvider);
    await store.delete(tag.id);
    ref.invalidate(tagsProvider);
    // SessionTags cascades on FK, but any UI that derives per-session tag
    // lists from the in-memory session state needs a reload to drop links
    // to the now-deleted tag.
    await ref.read(sessionProvider.notifier).load();
    await _load();
    if (mounted) {
      Toast.show(context, message: s.tagDeleted(tag.name));
    }
  }
}

/// Dialog wrapper for standalone use (mobile settings).
class TagManagerDialog extends StatelessWidget {
  const TagManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(context, builder: (_) => const TagManagerDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).tags,
      maxWidth: 480,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 350, child: TagManagerPanel()),
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
    );
  }
}

// ── Add Tag Dialog ─────────────────────────────────────────────────

class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog();

  static Future<Tag?> show(BuildContext context) {
    return AppDialog.show<Tag>(context, builder: (_) => const _AddTagDialog());
  }

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final _nameCtrl = TextEditingController();
  int _selectedColorIndex = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.addTag,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: s.tagName,
              hintText: s.tagNameHint,
            ),
          ),
          const SizedBox(height: 16),
          Text(s.tagColor, style: TextStyle(fontSize: AppFonts.sm)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < tagColors.length; i++)
                _ColorDot(
                  color: tagColors[i],
                  selected: i == _selectedColorIndex,
                  onTap: () => setState(() => _selectedColorIndex = i),
                ),
            ],
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
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      Tag(name: name, color: tagColors[_selectedColorIndex]),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hex = color.replaceFirst('#', '');
    final c = Color(int.parse('FF$hex', radix: 16));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: AppTheme.fg, width: 2) : null,
        ),
      ),
    );
  }
}
