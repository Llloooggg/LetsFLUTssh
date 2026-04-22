import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags/tag.dart';
import '../../core/tags/tag_store.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/data_checkboxes.dart';
import 'tag_manager_dialog.dart';

/// Dialog to assign/remove tags on a session or folder.
///
/// Shows every tag as a [DataCheckboxRow] so the row metrics match the
/// rest of the import/export surface. Changes apply immediately: each tap
/// writes through to the store, no explicit "Save". A tristate header row
/// toggles every tag in one gesture; a search field appears once the tag
/// list crosses the threshold where scanning becomes awkward.
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

/// The search field only appears once the user has enough tags that
/// eyeballing them becomes slower than typing. Below this threshold the
/// field is just chrome.
const int _kSearchThreshold = 6;

class _TagAssignDialogState extends ConsumerState<TagAssignDialog> {
  List<Tag> _allTags = [];
  Set<String> _assignedIds = {};
  bool _loading = true;
  String _filter = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

  List<Tag> get _visibleTags {
    if (_filter.isEmpty) return _allTags;
    final q = _filter.toLowerCase();
    return _allTags.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  /// Tristate for the "select all" row: all → true, none → false,
  /// partial → null (drawn as the mixed indicator).
  bool? get _allAssignedTristate {
    if (_allTags.isEmpty) return false;
    final n = _assignedIds.length;
    if (n == 0) return false;
    if (n == _allTags.length) return true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.editTags,
      maxWidth: 420,
      scrollable: false,
      // Default padding (all(16)) — avoids trailing labels touching the
      // modal's rounded corners, which earlier clipped the "N / M"
      // counter against the right edge.
      content: SizedBox(height: 360, child: _buildBody(s)),
      actions: [
        // Manage lives in the footer so it's reachable from both the
        // populated and empty states without duplicating the button.
        if (!_loading)
          AppButton.secondary(label: s.manageTags, onTap: _openTagManager),
        AppButton.primary(label: s.close, onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildBody(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_allTags.isEmpty) {
      return _buildEmptyState(s);
    }
    final showSearch = _allTags.length >= _kSearchThreshold;
    final visible = _visibleTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch) ...[_buildSearchField(s), const SizedBox(height: 6)],
        _buildSelectAllRow(s),
        const AppDivider(),
        const SizedBox(height: 4),
        Expanded(child: _buildTagList(s, visible)),
      ],
    );
  }

  Widget _buildEmptyState(S s) {
    // Subtle icon + single-line message. The "Manage Tags" CTA lives in
    // the dialog footer; repeating it here confuses widget finders (two
    // "Manage Tags" texts on screen) and just clutters a small surface.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_outlined, size: 32, color: AppTheme.fgFaint),
          const SizedBox(height: 12),
          Text(
            s.noTags,
            textAlign: TextAlign.center,
            style: AppFonts.inter(fontSize: AppFonts.md, color: AppTheme.fgDim),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(S s) {
    return TextField(
      controller: _searchCtrl,
      style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: s.search).copyWith(
        isDense: true,
        prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.fgDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffixIcon: _filter.isEmpty
            ? null
            : AppIconButton(
                icon: Icons.clear,
                dense: true,
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _filter = '');
                },
              ),
      ),
      onChanged: (v) => setState(() => _filter = v),
    );
  }

  Widget _buildSelectAllRow(S s) {
    final total = _allTags.length;
    final selected = _assignedIds.length;
    return DataCheckboxRow(
      icon: Icons.done_all,
      label: s.selectAll,
      value: _allAssignedTristate,
      tristate: true,
      trailingLabel: '$selected / $total',
      onTap: _toggleAll,
    );
  }

  Widget _buildTagList(S s, List<Tag> visible) {
    if (visible.isEmpty) {
      // Filtered to nothing — keep the frame but tell the user why.
      return AppEmptyState(message: s.noTags);
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final tag = visible[index];
        final isAssigned = _assignedIds.contains(tag.id);
        final color = tag.colorValue ?? AppTheme.fgDim;
        return DataCheckboxRow(
          icon: Icons.label,
          iconColor: color,
          label: tag.name,
          value: isAssigned,
          onTap: () => _toggle(tag, isAssigned),
        );
      },
    );
  }

  Future<void> _openTagManager() async {
    await TagManagerDialog.show(context);
    // Manager may have added, renamed, or removed tags — reload so the
    // picker reflects the new state without the user having to reopen the
    // assign dialog.
    if (mounted) {
      setState(() => _loading = true);
      await _load();
    }
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

    if (!mounted) return;
    setState(() {
      if (currentlyAssigned) {
        _assignedIds.remove(tag.id);
      } else {
        _assignedIds.add(tag.id);
      }
    });
  }

  /// Tristate toggle-all: tapping the header row assigns every tag when any
  /// are unassigned, and unassigns every tag when all are already on. The
  /// mixed state resolves to "assign all" because that's the most common
  /// follow-up after selecting partially.
  Future<void> _toggleAll() async {
    final next = _allAssignedTristate != true;
    final store = ref.read(tagStoreProvider);
    for (final tag in _allTags) {
      final isAssigned = _assignedIds.contains(tag.id);
      if (next && !isAssigned) {
        await _writeAssignment(store, tag, assign: true);
      } else if (!next && isAssigned) {
        await _writeAssignment(store, tag, assign: false);
      }
    }
    if (!mounted) return;
    if (widget.sessionId != null) {
      ref.invalidate(sessionTagsProvider(widget.sessionId!));
    } else {
      ref.invalidate(folderTagsProvider(widget.folderId!));
    }
    setState(() {
      _assignedIds = next ? _allTags.map((t) => t.id).toSet() : <String>{};
    });
  }

  Future<void> _writeAssignment(
    TagStore store,
    Tag tag, {
    required bool assign,
  }) async {
    if (widget.sessionId != null) {
      if (assign) {
        await store.tagSession(widget.sessionId!, tag.id);
      } else {
        await store.untagSession(widget.sessionId!, tag.id);
      }
    } else {
      if (assign) {
        await store.tagFolder(widget.folderId!, tag.id);
      } else {
        await store.untagFolder(widget.folderId!, tag.id);
      }
    }
  }
}
