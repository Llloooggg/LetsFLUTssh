import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/ssh/shell_helper.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import 'cursor_overlay.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/error_state.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart' as plat;

/// A single terminal pane — xterm TerminalView connected to one SSH shell.
///
/// Multiple panes can share the same [Connection] (each opens its own shell).
/// Factory for opening SSH shell — injectable for testing.
typedef ShellOpenFactory =
    Future<ShellConnection> Function({
      required Connection connection,
      required Terminal terminal,
      VoidCallback? onDone,
    });

class TerminalPane extends ConsumerStatefulWidget {
  final Connection connection;
  final bool isFocused;

  /// Whether there are multiple panes in the tiling layout.
  /// Focus border is only shown when this is true.
  final bool hasMultiplePanes;
  final VoidCallback? onFocused;
  final VoidCallback? onSplitVertical;
  final VoidCallback? onSplitHorizontal;
  final VoidCallback? onClose;

  /// Optional factory for testing — bypasses real SSH shell.
  final ShellOpenFactory? shellFactory;

  const TerminalPane({
    super.key,
    required this.connection,
    this.isFocused = false,
    this.hasMultiplePanes = false,
    this.onFocused,
    this.onSplitVertical,
    this.onSplitHorizontal,
    this.onClose,
    this.shellFactory,
  });

  @override
  ConsumerState<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends ConsumerState<TerminalPane> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  ShellConnection? _shellConn;
  bool _connected = false;
  String? _error;

  // Search visibility — ValueNotifier so toggling doesn't rebuild TerminalView
  final _showSearch = ValueNotifier<bool>(false);

  /// Exposed for testing — toggle search bar visibility.
  @visibleForTesting
  ValueNotifier<bool> get showSearchNotifier => _showSearch;

  /// Exposed for testing — access the xterm Terminal instance.
  @visibleForTesting
  Terminal get terminal => _terminal;

  /// Exposed for testing — access the TerminalController.
  @visibleForTesting
  TerminalController get terminalController => _terminalController;

  /// Exposed for testing — zoom in / out / reset.
  @visibleForTesting
  void zoomIn() => _zoomIn();
  @visibleForTesting
  void zoomOut() => _zoomOut();
  @visibleForTesting
  void zoomReset() => _zoomReset();

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: ref.read(configProvider).scrollback);
    _terminalController = TerminalController();
    HardwareKeyboard.instance.addHandler(_onShiftToggle);
    _connectAndOpenShell();
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;

    // Wait for connection if still connecting
    await conn.waitUntilReady();

    // Check connection result
    if (!conn.isConnected) {
      if (!mounted) return;
      final l10n = S.of(context);
      final error = conn.connectionError != null
          ? localizeError(l10n, conn.connectionError!)
          : l10n.errConnectionFailed;
      _terminal.write('\x1B[31m$error\x1B[0m\r\n');
      setState(() => _error = error);
      return;
    }

    void onDone() {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = S.of(context).errSessionClosed;
        });
      }
    }

    try {
      if (widget.shellFactory != null) {
        _shellConn = await widget.shellFactory!(
          connection: conn,
          terminal: _terminal,
          onDone: onDone,
        );
      } else {
        _shellConn = await ShellHelper.openShell(
          connection: conn,
          terminal: _terminal,
          onDone: onDone,
        );
      }
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'TerminalPane',
        error: e,
      );
      if (mounted) {
        final l10n = S.of(context);
        final localized = localizeError(l10n, e);
        _terminal.write(
          '\r\n\x1B[31m${l10n.errShellError(localized)}\x1B[0m\r\n',
        );
        setState(() => _error = localized);
      }
    }
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFocused && !widget.isFocused) {
      _terminalController.clearSelection();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onShiftToggle);
    _shellConn?.close();
    _terminalController.dispose();
    _showSearch.dispose();
    super.dispose();
  }

  /// When the terminal app has enabled mouse mode (e.g. htop, vim), holding
  /// Shift bypasses mouse forwarding so the user can select text locally.
  /// Standard terminal-emulator behaviour (xterm, GNOME Terminal, etc.).
  bool _onShiftToggle(KeyEvent event) {
    final shouldSuspend =
        HardwareKeyboard.instance.isShiftPressed &&
        _terminal.mouseMode != MouseMode.none;
    if (_terminalController.suspendedPointerInputs != shouldSuspend) {
      _terminalController.setSuspendPointerInput(shouldSuspend);
    }
    return false; // never consume the key event
  }

  /// Toggle search bar visibility. Exposed for testing — in production
  /// triggered by Ctrl+Shift+F shortcut.
  @visibleForTesting
  void toggleSearch() {
    _showSearch.value = !_showSearch.value;
  }

  void _closeSearch() {
    _showSearch.value = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorState();
    }
    if (!_connected) {
      return const Center(child: CircularProgressIndicator());
    }

    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    // No border on panes — the 4px divider in TilingView separates them.
    return GestureDetector(
      onTap: widget.onFocused,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): toggleSearch,
          const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
        },
        child: Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _showSearch,
              builder: (context, show, _) {
                if (!show) return const SizedBox.shrink();
                return TerminalSearchBar(
                  terminal: _terminal,
                  terminalController: _terminalController,
                  onClose: _closeSearch,
                );
              },
            ),
            Expanded(
              // Listener intercepts right-click and Ctrl+scroll before
              // xterm's gesture detector, so context menu and zoom work
              // even when the terminal is in mouse mode (e.g. htop, vim).
              child: Listener(
                onPointerDown: (event) {
                  if (event.buttons == kSecondaryButton) {
                    _showContextMenu(context, event.position);
                  }
                },
                onPointerSignal: _onPointerSignal,
                child: Stack(
                  children: [
                    TerminalView(
                      _terminal,
                      controller: _terminalController,
                      autofocus: widget.isFocused,
                      hardwareKeyboardOnly: plat.isDesktopPlatform,
                      onKeyEvent: _handleTerminalKey,
                      backgroundOpacity: 1.0,
                      padding: const EdgeInsets.all(4),
                      theme: TerminalTheme(
                        cursor: AppTheme.termCursor,
                        selection: AppTheme.termSelection,
                        foreground: AppTheme.fg,
                        background: AppTheme.bg2,
                        black: AppTheme.termBlack,
                        red: AppTheme.termRed,
                        green: AppTheme.termGreen,
                        yellow: AppTheme.termYellow,
                        blue: AppTheme.termBlue,
                        magenta: AppTheme.termMagenta,
                        cyan: AppTheme.termCyan,
                        white: AppTheme.termWhite,
                        brightBlack: AppTheme.termBrightBlack,
                        brightRed: AppTheme.termBrightRed,
                        brightGreen: AppTheme.termBrightGreen,
                        brightYellow: AppTheme.termBrightYellow,
                        brightBlue: AppTheme.termBrightBlue,
                        brightMagenta: AppTheme.termBrightMagenta,
                        brightCyan: AppTheme.termBrightCyan,
                        brightWhite: AppTheme.termBrightWhite,
                        searchHitBackground: AppTheme.accent.withValues(
                          alpha: 0.3,
                        ),
                        searchHitBackgroundCurrent: AppTheme.accent,
                        searchHitForeground: AppTheme.searchHitFg,
                      ),
                      textStyle: TerminalStyle(
                        fontSize: fontSize,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    Positioned.fill(
                      child: CursorTextOverlay(
                        terminal: _terminal,
                        fontSize: fontSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;
    final hasSplit = widget.onSplitVertical != null;

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          ContextMenuItem(
            label: S.of(context).copy,
            icon: Icons.copy,
            shortcut: 'Ctrl+C',
            onTap: _copySelection,
          ),
        ContextMenuItem(
          label: S.of(context).paste,
          icon: Icons.paste,
          shortcut: 'Ctrl+V',
          onTap: _pasteClipboard,
        ),
        if (hasSplit) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: S.of(context).copyRight,
            icon: Icons.vertical_split,
            onTap: () => widget.onSplitVertical?.call(),
          ),
          ContextMenuItem(
            label: S.of(context).copyDown,
            icon: Icons.horizontal_split,
            onTap: () => widget.onSplitHorizontal?.call(),
          ),
          if (widget.onClose != null)
            ContextMenuItem(
              label: S.of(context).closePane,
              icon: Icons.close,
              onTap: () => widget.onClose?.call(),
            ),
        ],
      ],
    );
  }

  /// Intercept keyboard shortcuts before xterm's built-in handler consumes
  /// them — xterm sends most key combos to the terminal as raw data, so
  /// ancestor CallbackShortcuts never see them.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && shift) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }
      // Ctrl+Shift+\ → split pane down
      if (event.logicalKey == LogicalKeyboardKey.backslash) {
        widget.onSplitHorizontal?.call();
        return KeyEventResult.handled;
      }
    }
    // Ctrl+\ → split pane right
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.backslash) {
      widget.onSplitVertical?.call();
      return KeyEventResult.handled;
    }
    // Ctrl+= / Ctrl+- / Ctrl+0 → zoom in / out / reset
    if (ctrl && !shift) {
      if (event.logicalKey == LogicalKeyboardKey.equal) {
        _zoomIn();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.minus) {
        _zoomOut();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.digit0) {
        _zoomReset();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _copySelection() =>
      TerminalClipboard.copy(_terminal, _terminalController);

  Future<void> _pasteClipboard() => TerminalClipboard.paste(_terminal);

  void _zoomIn() => _adjustFontSize(1);

  void _zoomOut() => _adjustFontSize(-1);

  void _zoomReset() {
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: 14.0)),
        );
  }

  void _adjustFontSize(double delta) {
    final current = ref.read(configProvider).fontSize;
    final updated = (current + delta).clamp(8.0, 24.0);
    if (updated == current) return;
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: updated)),
        );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _adjustFontSize(event.scrollDelta.dy < 0 ? 1 : -1);
    }
  }

  Widget _buildErrorState() {
    return ErrorState(message: _error!);
  }
}

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

    final queryLower = query.toLowerCase();
    final buffer = widget.terminal.buffer;
    final highlights = <TerminalHighlight>[];

    for (var y = 0; y < buffer.height; y++) {
      final line = buffer.lines[y];
      final lineText = line.toString().toLowerCase();
      var startIndex = 0;
      while (true) {
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

    setState(() {
      _searchHighlights = highlights;
      _totalMatches = highlights.length;
      _currentMatchIndex = highlights.isNotEmpty ? 0 : -1;
    });
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
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            onTap: _totalMatches > 0 ? _prevMatch : null,
            tooltip: S.of(context).previous,
            size: 18,
            boxSize: 28,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            onTap: _totalMatches > 0 ? _nextMatch : null,
            tooltip: S.of(context).next,
            size: 18,
            boxSize: 28,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: _close,
            tooltip: S.of(context).closeEsc,
            size: 18,
            boxSize: 28,
          ),
        ],
      ),
    );
  }
}
