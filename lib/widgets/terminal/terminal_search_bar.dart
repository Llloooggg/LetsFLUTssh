import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../core/app_icon_button.dart';

/// In-terminal search input. Owns only its text buffer, focus, and a
/// debounce timer (pre-submit text-field state is the one render concern
/// Flutter keeps — the match search itself runs Rust-side via the host's
/// [onQueryChanged]). The host holds the match list / current index and
/// feeds back [matchLabel] (e.g. `2/7`) so the count reflects the
/// Rust-computed results, not a Dart re-count.
class TerminalSearchBar extends StatefulWidget {
  const TerminalSearchBar({
    super.key,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    this.matchLabel,
    this.hasMatches = false,
  });

  /// Fired (debounced) when the query text changes. The host runs
  /// `TerminalSession.search` and updates the highlight list.
  final ValueChanged<String> onQueryChanged;

  /// Move to the next / previous match (also bound to Enter / Shift+Enter).
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// Close the search bar (Esc or the close button).
  final VoidCallback onClose;

  /// `current/total` label the host computes from the match list, or null
  /// when the query is empty / has no matches.
  final String? matchLabel;

  /// Whether there is at least one match — gates the next/prev buttons.
  final bool hasMatches;

  @override
  State<TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<TerminalSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => widget.onQueryChanged(_controller.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: AppTheme.bg1,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppTheme.bg3,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
                hintText: l10n.search,
                hintStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgFaint,
                ),
                suffixText: widget.matchLabel,
                suffixStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => widget.onNext(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            onTap: widget.hasMatches ? widget.onPrevious : null,
            tooltip: l10n.previous,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            onTap: widget.hasMatches ? widget.onNext : null,
            tooltip: l10n.next,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: widget.onClose,
            tooltip: l10n.closeEsc,
          ),
        ],
      ),
    );
  }
}
