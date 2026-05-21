import 'package:flutter/material.dart';

/// Drop-in replacement for [SelectionArea] that strips the
/// "Select All" entry from the right-click / long-press context
/// menu.
///
/// "Select All" is how Flutter's default text-selection toolbar
/// advertises "select every selectable span inside the nearest
/// `SelectionArea`". That matches what a text field or a confined
/// log viewer should do — but the app wraps whole screens (settings,
/// dialogs, the main desktop shell) in a single [SelectionArea], so
/// tapping Select All grabs every Text widget on the screen at once,
/// which is confusing and borderline meaningless. We keep Copy (and
/// any future per-platform extras) and drop Select All only.
///
/// Usage: replace `SelectionArea(child: …)` with
/// `AppSelectionArea(child: …)` — nothing else changes.
class AppSelectionArea extends StatelessWidget {
  const AppSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (ctx, state) {
        final items = state.contextMenuButtonItems
            .where((item) => item.type != ContextMenuButtonType.selectAll)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: child,
    );
  }
}
