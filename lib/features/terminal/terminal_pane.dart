import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import '../../core/connection/progress_writer.dart';
import '../../core/shortcut_registry.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../core/ssh/shell_helper.dart';
import '../../core/config/app_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import 'cursor_overlay.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/context_menu.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart' as plat;
import '../snippets/snippet_picker.dart';

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
  final VoidCallback? onClose;

  /// Optional factory for testing — bypasses real SSH shell.
  final ShellOpenFactory? shellFactory;

  const TerminalPane({
    super.key,
    required this.connection,
    this.isFocused = false,
    this.hasMultiplePanes = false,
    this.onFocused,
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
  StreamSubscription<ConnectionStep>? _progressSub;
  Map<AppShortcut, VoidCallback>? _shortcuts;

  /// Whether the terminal pane is in an error state.
  bool get hasError => _error != null;

  String? _error;

  // Search visibility — ValueNotifier so toggling doesn't rebuild TerminalView
  final _showSearch = ValueNotifier<bool>(false);

  /// Cached terminal theme — rebuilt only when app brightness changes.
  TerminalTheme? _cachedTheme;
  bool? _cachedIsDark;

  TerminalTheme get _terminalTheme {
    final dark = AppTheme.isDark;
    if (_cachedTheme == null || _cachedIsDark != dark) {
      _cachedIsDark = dark;
      _cachedTheme = AppTheme.terminalTheme;
    }
    return _cachedTheme!;
  }

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

  /// Send a command string to the SSH shell.
  ///
  /// Appends a newline if not already present. No-op if shell is not open.
  void sendCommand(String command) {
    if (_shellConn == null) return;
    final cmd = command.endsWith('\n') ? command : '$command\n';
    _terminal.textInput(cmd);
  }

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: ref.read(configProvider).scrollback);
    _terminalController = TerminalController();
    // Register with the scrubber so auto-lock wipes this terminal's
    // scrollback alongside the DB key. Dispose removes us from the
    // registry so stale pointers do not linger.
    TerminalScrubber.instance.register(_terminal);
    HardwareKeyboard.instance.addHandler(_onShiftToggle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndOpenShell();
    });
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;
    final l10n = S.of(context);
    final tracker = ProgressTracker(conn);
    final writer = ProgressWriter(
      terminal: _terminal,
      l10n: l10n,
      config: conn.sshConfig,
    );

    // Subscribe to progress stream and write steps to terminal
    _progressSub = writer.subscribe(tracker);

    // Wait for connection if still connecting
    await conn.waitUntilReady();
    _progressSub?.cancel();
    _progressSub = null;
    tracker.dispose();

    // Check connection result
    if (!conn.isConnected) {
      if (!mounted) return;
      // Mark disconnected so tab dot and connection bar update
      conn.state = SSHConnectionState.disconnected;
      final error = conn.connectionError != null
          ? localizeError(l10n, conn.connectionError!)
          : l10n.errConnectionFailed;
      _terminal.write('\x1B[?25h\x1B[31m$error\x1B[0m\r\n');
      setState(() => _error = error);
      // Notify provider so workspace status dots and connection bar update
      ref.read(connectionManagerProvider).notifyStateChanged();
      return;
    }

    try {
      // Clear progress log before opening shell — openShell wires stdout
      // to terminal.write(), so any server output must not be erased.
      writer.clear();
      _shellConn = await _openShell(conn);
      // Notify provider so workspace status dots and connection bar update
      if (mounted) ref.read(connectionManagerProvider).notifyStateChanged();
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'TerminalPane',
        error: e,
      );
      if (mounted) {
        final localized = localizeError(l10n, e);
        _terminal.write('\x1B[?25h\x1B[31m$localized\x1B[0m\r\n');
        setState(() => _error = localized);
      }
    }
  }

  Future<ShellConnection> _openShell(Connection conn) async {
    void onDone() {
      if (mounted) {
        setState(() => _error = S.of(context).errSessionClosed);
      }
    }

    if (widget.shellFactory != null) {
      return widget.shellFactory!(
        connection: conn,
        terminal: _terminal,
        onDone: onDone,
      );
    }
    return ShellHelper.openShell(
      connection: conn,
      terminal: _terminal,
      onDone: onDone,
    );
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
    TerminalScrubber.instance.unregister(_terminal);
    _progressSub?.cancel();
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
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    // No border on panes — the 4px divider in TilingView separates them.
    //
    // Route onFocused through a raw Listener.onPointerDown rather than
    // GestureDetector.onTap: onTap only fires when the gesture arena
    // resolves as a clean tap, and any drift during the click (or the
    // xterm TerminalView's own pan/select gesture claiming the arena)
    // swallows the event, so the focused pane would stop switching
    // "every other click" when jumping between split panes.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onFocused?.call(),
      child: CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.terminalSearch: toggleSearch,
          AppShortcut.terminalCloseSearch: _closeSearch,
        }),
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
            // Snap the terminal widget's height to an integer number of
            // cells so xterm's viewport doesn't leave a dead strip at
            // the bottom — the same trick MobileTerminalView applies.
            // `kTerminalLineHeight` is the shared 1.2 multiplier xterm's
            // painter uses internally; mirroring it here gives us a
            // pre-layout estimate that matches the real measurement
            // closely enough that xterm settles on `rows * cellHeight`
            // rendered text with zero trailing gap. The remainder pixels
            // become a `ColoredBox` painted in the terminal background
            // so the boundary between the last row and the pane's next
            // widget (split divider / status) reads as a clean edge.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const verticalPadding = 8.0; // EdgeInsets.all(4).vertical
                  final cellHeight = fontSize * kTerminalLineHeight;
                  final usable = constraints.maxHeight - verticalPadding;
                  final rows = usable > 0 ? (usable / cellHeight).floor() : 0;
                  final snappedHeight = rows > 0
                      ? rows * cellHeight + verticalPadding
                      : constraints.maxHeight;
                  return Column(
                    children: [
                      SizedBox(
                        height: snappedHeight,
                        child: _buildTerminalStack(fontSize),
                      ),
                      if (snappedHeight < constraints.maxHeight)
                        Expanded(
                          child: ColoredBox(color: _terminalTheme.background),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Inner Listener + Stack(TerminalView, CursorTextOverlay). Extracted
  /// so the LayoutBuilder above can pin the terminal widget to an
  /// integer-row height via a `SizedBox` parent.
  Widget _buildTerminalStack(double fontSize) {
    return Listener(
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
            theme: _terminalTheme,
            textStyle: TerminalStyle(
              fontSize: fontSize,
              fontFamily: AppFonts.monoFamily,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
          Positioned.fill(
            child: CursorTextOverlay(terminal: _terminal, fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          StandardMenuAction.copy.item(
            context,
            shortcut: AppShortcut.terminalCopy,
            onTap: _copySelection,
          ),
        StandardMenuAction.paste.item(
          context,
          shortcut: AppShortcut.terminalPaste,
          onTap: _pasteClipboard,
        ),
        StandardMenuAction.snippets.item(
          context,
          onTap: () => _showSnippetPicker(context),
        ),
      ],
    );
  }

  /// Intercept keyboard shortcuts before xterm's built-in handler consumes
  /// them — xterm sends most key combos to the terminal as raw data, so
  /// ancestor CallbackShortcuts never see them.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final reg = AppShortcutRegistry.instance;

    _shortcuts ??= <AppShortcut, VoidCallback>{
      AppShortcut.terminalCopy: _copySelection,
      AppShortcut.terminalPaste: _pasteClipboard,
      AppShortcut.zoomIn: _zoomIn,
      AppShortcut.zoomOut: _zoomOut,
      AppShortcut.zoomReset: _zoomReset,
    };

    for (final entry in _shortcuts!.entries) {
      if (reg.matches(entry.key, event)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _copySelection() =>
      TerminalClipboard.copy(_terminal, _terminalController);

  Future<void> _pasteClipboard() => TerminalClipboard.paste(_terminal);

  Future<void> _showSnippetPicker(BuildContext context) async {
    final cfg = widget.connection.sshConfig;
    final command = await SnippetPicker.show(
      context,
      sessionId: widget.connection.sessionId,
      templateContext: {
        'host': cfg.host,
        'user': cfg.user,
        'port': cfg.port.toString(),
        'label': widget.connection.label,
        'now': DateTime.now().toIso8601String(),
      },
    );
    if (command != null) {
      sendCommand(command);
    }
  }

  void _zoomIn() => _adjustFontSize(1);

  void _zoomOut() => _adjustFontSize(-1);

  void _zoomReset() {
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(
            terminal: c.terminal.copyWith(
              fontSize: TerminalConfig.defaults.fontSize,
            ),
          ),
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
