import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags/tag.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';

/// Dialog to assign/remove tags on a session or folder.
///
/// Shows all available tags as checkboxes. Changes are applied immediately.
class TagAssignDialog extends ConsumerStatefulWidget {
  /// Session ID to tag. Mutually exclusive with [folderId].
  final String? sessionId;

  /// Folder DB ID to tag. Mutually exclusive with [sessionId].
  final String? folderId;

  const TagAssignDialog({super.key, this.sessionId, this.folderId})
    : assert(
        (sessionId != null) != (folderId != null),
        'Provide exactly one of sessionId or folderId',
      );

  /// Show the tag assignment dialog for a session.
  static Future<void> showForSession(
    BuildContext context, {
    required String sessionId,
  }) {
    return AppDialog.show(
      context,
      builder: (_) => TagAssignDialog(sessionId: sessionId),
    );
  }

  /// Show the tag assignment dialog for a folder.
  static Future<void> showForFolder(
    BuildContext context, {
    required String folderId,
  }) {
    return AppDialog.show(
      context,
      builder: (_) => TagAssignDialog(folderId: folderId),
    );
  }

  @override
  ConsumerState<TagAssignDialog> createState() => _TagAssignDialogState();
}

class _TagAssignDialogState extends ConsumerState<TagAssignDialog> {
  List<Tag> _allTags = [];
  Set<String> _assignedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(tagStoreProvider);
    final allTags = await store.loadAll();

    List<Tag> assigned;
    if (widget.sessionId != null) {
      assigned = await store.getForSession(widget.sessionId!);
    } else {
      assigned = await store.getForFolder(widget.folderId!);
    }

    if (mounted) {
      setState(() {
        _allTags = allTags;
        _assignedIds = assigned.map((t) => t.id).toSet();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.editTags,
      maxWidth: 400,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(height: 300, child: _buildBody(s)),
      actions: [
        AppDialogAction.primary(
          label: s.close,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_allTags.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.noTags,
              style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.manageTags),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _allTags.length,
      itemBuilder: (context, index) {
        final tag = _allTags[index];
        final isAssigned = _assignedIds.contains(tag.id);
        final color = tag.colorValue ?? AppTheme.fgDim;
        return CheckboxListTile(
          dense: true,
          value: isAssigned,
          onChanged: (_) => _toggle(tag, isAssigned),
          secondary: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          title: Text(
            tag.name,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fg),
          ),
        );
      },
    );
  }

  Future<void> _toggle(Tag tag, bool currentlyAssigned) async {
    final store = ref.read(tagStoreProvider);
    if (widget.sessionId != null) {
      if (currentlyAssigned) {
        await store.untagSession(widget.sessionId!, tag.id);
      } else {
        await store.tagSession(widget.sessionId!, tag.id);
      }
      ref.invalidate(sessionTagsProvider(widget.sessionId!));
    } else {
      if (currentlyAssigned) {
        await store.untagFolder(widget.folderId!, tag.id);
      } else {
        await store.tagFolder(widget.folderId!, tag.id);
      }
      ref.invalidate(folderTagsProvider(widget.folderId!));
    }

    setState(() {
      if (currentlyAssigned) {
        _assignedIds.remove(tag.id);
      } else {
        _assignedIds.add(tag.id);
      }
    });
  }
}
