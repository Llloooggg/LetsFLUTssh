part of 'terminal_pane.dart';

/// Self-contained search bar widget — manages its own state so that
/// search interactions (typing, next/prev) don't rebuild the TerminalView.
class TerminalSearchBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController terminalController;
  final VoidCallback onClose;

  const TerminalSearchBar({
    super.key,
    required this.terminal,
    required this.terminalController,
    required this.onClose,
  });

  @override
  State<TerminalSearchBar> createState() => TerminalSearchBarState();
}

class TerminalSearchBarState extends State<TerminalSearchBar> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<TerminalHighlight> _searchHighlights = [];
  int _currentMatchIndex = -1;
  int _totalMatches = 0;
  bool _disposed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _clearHighlights();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _debouncedSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _performSearch);
  }

  void _performSearch() {
    _clearHighlights();
    if (_disposed) return;
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _totalMatches = 0;
        _currentMatchIndex = -1;
      });
      return;
    }

    final buffer = widget.terminal.buffer;
    final highlights = <TerminalHighlight>[];
    const maxMatches = 1000;

    for (var y = 0; y < buffer.height && highlights.length < maxMatches; y++) {
      _highlightLineMatches(buffer, y, query, highlights, maxMatches);
    }

    setState(() {
      _searchHighlights = highlights;
      _totalMatches = highlights.length;
      _currentMatchIndex = highlights.isNotEmpty ? 0 : -1;
    });
  }

  void _highlightLineMatches(
    Buffer buffer,
    int y,
    String query,
    List<TerminalHighlight> highlights,
    int maxMatches,
  ) {
    final lineText = buffer.lines[y].toString().toLowerCase();
    final queryLower = query.toLowerCase();
    var startIndex = 0;
    while (startIndex < lineText.length && highlights.length < maxMatches) {
      final pos = lineText.indexOf(queryLower, startIndex);
      if (pos < 0) break;
      try {
        final p1 = buffer.createAnchor(pos, y);
        final p2 = buffer.createAnchor(pos + query.length, y);
        highlights.add(
          widget.terminalController.highlight(
            p1: p1,
            p2: p2,
            color: AppTheme.searchHighlight,
          ),
        );
      } catch (e) {
        AppLogger.instance.log(
          'Highlight failed at ($pos, $y): $e',
          name: 'TerminalSearch',
        );
      }
      startIndex = pos + 1;
    }
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(
      () => _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches,
    );
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(
      () => _currentMatchIndex =
          (_currentMatchIndex - 1 + _totalMatches) % _totalMatches,
    );
  }

  void _clearHighlights() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights = [];
  }

  void _close() {
    _clearHighlights();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.bg1,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
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
                hintText: S.of(context).search,
                hintStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgFaint,
                ),
                suffixText: _totalMatches > 0
                    ? '${_currentMatchIndex + 1}/$_totalMatches'
                    : null,
                suffixStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
              onChanged: (_) => _debouncedSearch(),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            onTap: _totalMatches > 0 ? _prevMatch : null,
            tooltip: S.of(context).previous,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            onTap: _totalMatches > 0 ? _nextMatch : null,
            tooltip: S.of(context).next,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: _close,
            tooltip: S.of(context).closeEsc,
          ),
        ],
      ),
    );
  }
}
