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
///  * responsive layout via [LayoutBuilder] — wide hosts keep the
///    single-row "search left, count middle, actions right" shape;
///    narrow hosts (≤ [_narrowBreakpoint]-px, e.g. phones and
///    narrow tablet modals) stack the search on its own row and
///    drop the actions into a full-width `Wrap` underneath, so
///    long-locale button labels (Russian "Сгенерировать ключ",
///    German "Passwort generieren", …) flow onto as many lines
///    as they need instead of clipping past the screen edge. An
///    earlier `Row` + inner `Wrap` layout tried to solve this in
///    a single row but failed because [Row] hands non-flex
///    children (the inner `Wrap`) **unbounded** main-axis
///    constraints, so `Wrap` never saw a max width and laid
///    everything out in a single, overflowing line. The
///    breakpoint split sidesteps that trap entirely.
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
  /// Breakpoint below which the toolbar stacks vertically. Matches
  /// the width at which three icon+label buttons in Russian /
  /// German translations stop fitting on a single row with a
  /// search field — empirically ~480 px after 12-px toolbar
  /// padding and the surrounding dialog insets. Tablets and
  /// desktop dialogs (≥ 640-px `maxWidth` in every caller) stay
  /// on the wide branch.
  static const double _narrowBreakpoint = 480;

  /// True when the backing collection has at least one entry. Drives
  /// visibility of the search bar + count label — see class docs.
  final bool hasItems;

  /// Search input rendered on the non-empty branch. Usually
  /// [AppDataSearchBar] but any widget works; the toolbar gives it
  /// an `Expanded`-equivalent slot on the wide branch and a full-
  /// width slot on the narrow branch.
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < _narrowBreakpoint;
          return narrow ? _buildNarrow() : _buildWide();
        },
      ),
    );
  }

  /// Wide layout (desktop dialogs, tablets): single row with the
  /// search + count label on the left, actions right-aligned. The
  /// actions live in an `Expanded` + `Align.centerRight` so they
  /// receive a bounded main-axis width from [Row] and the inner
  /// `Wrap` can legitimately wrap to a second row on locale builds
  /// that push total button width past the available space.
  Widget _buildWide() {
    return Row(
      // The search field is taller than the bare count label because
      // it renders an input chrome; without an explicit center
      // alignment the label top-aligned to the row and read as "count
      // floats above the search bar". Same for action buttons with
      // icon + label — center vs start shifts them a few pixels and
      // the mismatch is visible at a glance on a three-item toolbar.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasItems && search != null) ...[
          Expanded(child: search!),
          const SizedBox(width: 8),
          if (countLabel != null) ...[
            _CountLabel(countLabel!),
            const SizedBox(width: 8),
          ],
        ] else if (hasItems && countLabel != null) ...[
          _CountLabel(countLabel!),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
        ),
      ],
    );
  }

  /// Narrow layout (phones, narrow tablet modals): stack vertically.
  /// The search field takes the full row; the count label sits above
  /// the actions row so the action `Wrap` receives the full width
  /// and can break icon+label buttons onto multiple lines without
  /// shrinking their text.
  Widget _buildNarrow() {
    final rows = <Widget>[];
    if (hasItems && search != null) {
      rows.add(search!);
    }
    if (hasItems && countLabel != null) {
      rows.add(
        Align(alignment: Alignment.centerLeft, child: _CountLabel(countLabel!)),
      );
    }
    if (actions.isNotEmpty) {
      rows.add(
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }
}

class _CountLabel extends StatelessWidget {
  final String text;
  const _CountLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
    );
  }
}
