import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'app_collection_toolbar.dart';
import 'app_data_search_bar.dart';
import 'app_empty_state.dart';

/// Builds the toolbar's trailing actions (typically an Add button).
/// [reload] re-runs the loader — call it after a mutation so the list
/// reflects the change.
typedef CollectionToolbarActions =
    List<Widget> Function(
      BuildContext context,
      WidgetRef ref,
      Future<void> Function() reload,
    );

/// Builds one list row for [item]. [reload] re-runs the loader after a
/// mutation triggered from the row (delete, edit).
typedef CollectionItemBuilder<T> =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      T item,
      Future<void> Function() reload,
    );

/// Embeddable "load a list, search it, act on its rows" manager panel —
/// the shared shell behind the Tags and Snippets managers. Owns the
/// load / loading / filter state and the toolbar + separated-list scaffold;
/// callers supply only how to load, filter, label, and render their type.
///
/// This is the imperative load-then-[reload] model. Reactive collections
/// that re-emit on a bus event (e.g. known hosts) watch their stream
/// directly instead — folding both modes in here would mean carrying a
/// stream path the list managers never use.
class CollectionManagerPanel<T> extends ConsumerStatefulWidget {
  /// Fetches the full (unfiltered) list. Re-run on mount and after mutations.
  final Future<List<T>> Function(WidgetRef ref) load;

  /// Narrows [items] to those matching the current search text.
  final List<T> Function(List<T> items, String filter) filter;

  /// Toolbar count label for the full list size (e.g. `s.tagCount`).
  final String Function(int count) countLabel;

  /// Shown when the list is empty (nothing loaded at all).
  final String emptyMessage;

  /// Shown when the list is non-empty but the filter matches nothing.
  final String noResultsMessage;

  final CollectionToolbarActions toolbarActions;
  final CollectionItemBuilder<T> itemBuilder;

  const CollectionManagerPanel({
    super.key,
    required this.load,
    required this.filter,
    required this.countLabel,
    required this.emptyMessage,
    required this.noResultsMessage,
    required this.toolbarActions,
    required this.itemBuilder,
  });

  @override
  ConsumerState<CollectionManagerPanel<T>> createState() =>
      _CollectionManagerPanelState<T>();
}

class _CollectionManagerPanelState<T>
    extends ConsumerState<CollectionManagerPanel<T>> {
  List<T> _items = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.load(ref);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppCollectionToolbar(
          hasItems: _items.isNotEmpty,
          search: AppDataSearchBar(
            onChanged: (v) => setState(() => _filter = v),
            hintText: S.of(context).search,
          ),
          countLabel: widget.countLabel(_items.length),
          actions: widget.toolbarActions(context, ref, _reload),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty) {
      return AppEmptyState(message: widget.emptyMessage);
    }
    final visible = widget.filter(_items, _filter);
    if (visible.isEmpty) {
      return AppEmptyState(message: widget.noResultsMessage);
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          widget.itemBuilder(context, ref, visible[index], _reload),
    );
  }
}
