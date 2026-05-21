import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags/tag.dart';
import 'tags_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/core/app_collection_toolbar.dart';
import '../../widgets/core/app_data_row.dart';
import '../../widgets/core/app_data_search_bar.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_icon_button.dart';
import '../../widgets/core/app_empty_state.dart';
import '../../widgets/core/tag_color.dart';
import '../../widgets/core/toast.dart';

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
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await ref.read(tagsProvider.notifier).loadAll();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  List<Tag> _filtered() => filterTagsByName(_tags, _filter);

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
      hasItems: _tags.isNotEmpty,
      search: AppDataSearchBar(
        onChanged: (v) => setState(() => _filter = v),
        hintText: s.search,
      ),
      countLabel: s.tagCount(_tags.length),
      actions: [
        AppButton.secondary(
          label: s.addTag,
          icon: Icons.add,
          onTap: _addTag,
          dense: true,
        ),
      ],
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_tags.isEmpty) {
      return AppEmptyState(message: s.noTags);
    }
    final visible = _filtered();
    if (visible.isEmpty) {
      return AppEmptyState(message: s.noResults);
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(visible[index]),
    );
  }

  Widget _buildEntry(Tag tag) {
    final s = S.of(context);
    final color = tag.colorValue ?? AppTheme.fgDim;
    return AppDataRow(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: tag.name,
      trailing: [
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: s.deleteTag,
          dense: true,
          color: AppTheme.red,
          onTap: () => _deleteTag(tag),
        ),
      ],
    );
  }

  Future<void> _addTag() async {
    final result = await _AddTagDialog.show(context);
    if (result == null || !mounted) return;
    await ref.read(tagsProvider.notifier).add(result);
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
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
            label: s.delete,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(tagsProvider.notifier).delete(tag.id);
    // SessionTags / FolderTags cascade on FK; `dbTagsDelete`
    // Rust-side publishes `SessionsChanged` so the workspace
    // stream re-fetches and any per-session-tag derived UI drops
    // the dead link without a Dart-side reload.
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
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
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
          const SizedBox(height: AppSpacing.lg),
          Text(s.tagColor, style: TextStyle(fontSize: AppFonts.sm)),
          const SizedBox(height: AppSpacing.sm),
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
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        AppButton.primary(label: s.save, onTap: _save),
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
