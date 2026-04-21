import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_data_search_bar.dart';

/// Standardised toolbar for collection-management dialogs (snippet
/// manager, tag manager, key manager, etc.).
///
/// Shared behaviour every caller used to re-implement:
///
///  * search bar + count label hidden when the collection is empty
///    (their signal is owned by the centered empty-state widget
///    below them — a lonely "0 tags" + empty search box to the left
///    of an Add button looked like dead UI);
///  * primary Add / Import action stays visible on both branches
///    so the user can always create the first entry;
///  * layout uses a `Wrap` with `spacing` + `runSpacing` so long-
///    locale labels (Russian "Добавить сниппет" + "Импортировать
///    ключ") fall to a second row on narrow modals instead of
///    overflowing horizontally — the old `Row`-based toolbar
///    clipped on the Russian + German locales when the modal
///    width dropped below ~520 px.
///
/// Usage:
///
///     AppCollectionToolbar(
///       hasItems: _snippets.isNotEmpty,
///       search: AppDataSearchBar(
///         onChanged: (v) => setState(() => _filter = v),
///         hintText: s.search,
///       ),
///       countLabel: s.snippetCount(_snippets.length),
///       actions: [
///         TextButton.icon(...),
///       ],
///     );
class AppCollectionToolbar extends StatelessWidget {
  /// True when the backing collection has at least one entry. Drives
  /// visibility of the search bar + count label — see class docs.
  final bool hasItems;

  /// Search input rendered on the non-empty branch. Usually
  /// [AppDataSearchBar] but any widget works; the toolbar gives it
  /// an `Expanded`-equivalent slot in the inner `Wrap`.
  final Widget? search;

  /// Short localised count string rendered next to the search bar.
  /// Null drops the label even when [hasItems] is true, for dialogs
  /// whose header already renders the count separately.
  final String? countLabel;

  /// Trailing primary actions (Add, Import, Refresh, …). Rendered on
  /// both empty and non-empty branches so the user can always create
  /// the first entry.
  final List<Widget> actions;

  const AppCollectionToolbar({
    super.key,
    required this.hasItems,
    this.search,
    this.countLabel,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (hasItems && search != null) ...[
            Expanded(child: search!),
            const SizedBox(width: 8),
            if (countLabel != null) ...[
              Text(
                countLabel!,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgDim,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ] else if (hasItems && countLabel != null) ...[
            Text(
              countLabel!,
              style: AppFonts.inter(
                fontSize: AppFonts.xs,
                color: AppTheme.fgDim,
              ),
            ),
            const Spacer(),
          ] else
            const Spacer(),
          // Actions live inside a `Wrap` so a narrow modal on a
          // long-locale build falls to a second line instead of
          // clipping the right-most button. Two-button toolbars
          // (Import + Generate in the key manager) are the usual
          // failure case on ~520-px modals.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}
