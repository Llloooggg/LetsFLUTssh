import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared search input used by every list / table dialog (known hosts,
/// snippets, tags, session panel, …).
///
/// Fixes the visual drift that had each dialog rolling its own
/// [TextField] with slightly different heights, fills and icon sizes.
/// The known-hosts dialog was the canonical look — compact 28 px row,
/// filled `AppTheme.bg3`, `Icons.search` 16 px in the prefix, rounded
/// `AppTheme.radiusSm` border — so this widget is that same shape
/// lifted out and given stable defaults.
///
/// Caller owns the string via [onChanged]; the widget holds its own
/// [TextEditingController] so hot-reload doesn't wipe the current
/// query. Pass [initialText] to seed a non-empty value on first
/// build (e.g. restored from state).
class AppDataSearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final String initialText;
  final bool autofocus;

  const AppDataSearchBar({
    super.key,
    required this.onChanged,
    required this.hintText,
    this.initialText = '',
    this.autofocus = false,
  });

  @override
  State<AppDataSearchBar> createState() => _AppDataSearchBarState();
}

class _AppDataSearchBarState extends State<AppDataSearchBar> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Let the TextField pick its own natural height and centre it in a
    // `controlHeightSm` slot — an earlier wrap that forced the
    // TextField to fit inside a `SizedBox(height: 28)` clipped the
    // internal layout from the top, so the bar's visible content sat
    // above the toolbar's centerline. `Center` inside the fixed-height
    // slot keeps the outer height stable (so the toolbar row still
    // matches the count label's 28-px slot) while letting the
    // TextField's own content centre against the slot.
    return SizedBox(
      height: AppTheme.controlHeightSm,
      child: Center(
        child: TextField(
          controller: _ctrl,
          autofocus: widget.autofocus,
          onChanged: widget.onChanged,
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fg),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            hintStyle: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
            prefixIcon: const Icon(Icons.search, size: 16),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 0,
            ),
            filled: true,
            fillColor: AppTheme.bg3,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppTheme.radiusSm,
              borderSide: BorderSide(color: AppTheme.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppTheme.radiusSm,
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
      ),
    );
  }
}
