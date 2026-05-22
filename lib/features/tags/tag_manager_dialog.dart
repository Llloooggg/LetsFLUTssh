import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags/tag.dart';
import 'tags_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/core/app_collection_panel.dart';
import '../../widgets/core/app_data_row.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_icon_button.dart';
import '../../widgets/core/tag_color.dart';
import '../../widgets/core/toast.dart';

/// Embeddable tag manager — toolbar + list with CRUD over
/// [CollectionManagerPanel].
///
/// Used standalone inside [TagManagerDialog] (mobile) and embedded in
/// the desktop Tools dialog.
class TagManagerPanel extends StatelessWidget {
  const TagManagerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return CollectionManagerPanel<Tag>(
      load: (ref) => ref.read(tagsProvider.notifier).loadAll(),
      filter: filterTagsByName,
      countLabel: s.tagCount,
      emptyMessage: s.noTags,
      noResultsMessage: s.noResults,
      toolbarActions: (context, ref, reload) => [
        AppButton.secondary(
          label: s.addTag,
          icon: Icons.add,
          dense: true,
          onTap: () => _addTag(context, ref, reload),
        ),
      ],
      itemBuilder: _buildEntry,
    );
  }

  Widget _buildEntry(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
    Future<void> Function() reload,
  ) {
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
          onTap: () => _deleteTag(context, ref, tag, reload),
        ),
      ],
    );
  }

  Future<void> _addTag(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() reload,
  ) async {
    final result = await _AddTagDialog.show(context);
    if (result == null || !context.mounted) return;
    await ref.read(tagsProvider.notifier).add(result);
    await reload();
    if (context.mounted) {
      Toast.show(
        context,
        message: S.of(context).tagCreated,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _deleteTag(
    BuildContext context,
    WidgetRef ref,
    Tag tag,
    Future<void> Function() reload,
  ) async {
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
    if (confirmed != true || !context.mounted) return;
    await ref.read(tagsProvider.notifier).delete(tag.id);
    // SessionTags / FolderTags cascade on FK; `dbTagsDelete`
    // Rust-side publishes `SessionsChanged` so the workspace
    // stream re-fetches and any per-session-tag derived UI drops
    // the dead link without a Dart-side reload.
    await reload();
    if (context.mounted) {
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
