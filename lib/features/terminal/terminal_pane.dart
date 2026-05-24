import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../widgets/core/shortcut_registry.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../core/config/app_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../src/rust/api/terminal.dart' as rust_terminal;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/terminal/connection_progress.dart';
import '../../widgets/terminal/terminal_grid_view.dart';
import '../../widgets/terminal/terminal_key_input.dart';
import '../../widgets/terminal/terminal_palette_theme.dart';
import '../../l10n/app_localizations.dart';
import '../snippets/snippet_picker.dart';

/// A single terminal pane — a Rust-engine-backed [rust_terminal.TerminalSession]
/// rendered through the [TerminalGridView] cell-grid painter, connected to one
/// SSH shell.
///
/// Multiple panes can share the same [Connection] (each opens its own shell).
/// During the connect cascade the pane shows [ConnectionProgress]; once the
/// session opens it swaps to the live grid view. Keyboard input is encoded
/// Rust-side: [handleKey] normalises each event to a
/// [rust_terminal.TerminalKey] and forwards it through
/// [rust_terminal.TerminalSession.sendKey] (Ctrl+Shift+C/V stay reserved for
/// copy/paste). Selection/copy via mouse and in-terminal search land in a
/// later task. Scroll-wheel scrollback and font zoom work today.
class TerminalPane extends ConsumerStatefulWidget {
  final Connection connection;
  final bool isFocused;

  /// Whether this pane's tab is the foreground tab of the focused panel.
  /// Distinct from [isFocused] (which pane within the tab): a backgrounded
  /// tab keeps its panes mounted in the `IndexedStack` with `isFocused`
  /// unchanged, so only this flag flips when tabs switch. Defaults to true
  /// for single-pane / mobile callers that have no tab switching.
  final bool isActiveTab;

  /// Whether there are multiple panes in the tiling layout.
  /// Focus border is only shown when this is true.
  final bool hasMultiplePanes;

  /// Tiling-tree leaf id — stable across rebuilds. Optional so tests /
  /// single-pane callers (mobile shell, quick-connect) can omit it.
  final String? paneId;

  /// Owning tab's stable id. Optional so non-tabbed callers compile.
  final String? tabId;

  final VoidCallback? onFocused;
  final VoidCallback? onClose;

  const TerminalPane({
    super.key,
    required this.connection,
    this.isFocused = false,
    this.isActiveTab = true,
    this.hasMultiplePanes = false,
    this.paneId,
    this.tabId,
    this.onFocused,
    this.onClose,
  });

  @override
  ConsumerState<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends ConsumerState<TerminalPane> {
  /// Owned focus node so the pane can `requestFocus()` on its own schedule
  /// across `isFocused` / `isActiveTab` flips — the grid view's own focus
  /// surface only autofocuses on initial mount.
  final FocusNode _terminalFocus = FocusNode(debugLabel: 'TerminalPane');
  late final void Function() _scrubFn;

  rust_terminal.TerminalSession? _session;

  /// Bumped each time a fresh session opens so the [TerminalGridView] (keyed
  /// on this) tears down its old event subscription and resubscribes to the
  /// new session's stream rather than reusing the stale one.
  int _sessionEpoch = 0;

  StreamSubscription<ConnectionStep>? _progressSub;
  Map<AppShortcut, VoidCallback>? _shortcuts;

  /// Whether the terminal pane is in an error state.
  bool get hasError => _error != null;

  String? _error;

  /// Last viewport size reported by the grid view. Held so a font-zoom or
  /// theme change that rebuilds the view re-pushes the size to the session.
  int _cols = 80;
  int _rows = 24;

  /// Brightness the live session's palette was last pushed for. A theme
  /// toggle re-pushes the palette via [rust_terminal.TerminalSession.setPalette].
  bool? _paletteIsDark;

  /// Exposed for testing — the active Rust terminal session, or null before
  /// the shell opens / after an error.
  @visibleForTesting
  rust_terminal.TerminalSession? get session => _session;

  /// Exposed for testing — zoom in / out / reset.
  @visibleForTesting
  void zoomIn() => _zoomIn();
  @visibleForTesting
  void zoomOut() => _zoomOut();
  @visibleForTesting
  void zoomReset() => _zoomReset();

  /// Send a command string to the SSH shell. Appends a newline if not already
  /// present. No-op if the session is not open.
  void sendCommand(String command) {
    final session = _session;
    if (session == null) return;
    final cmd = command.endsWith('\n') ? command : '$command\n';
    unawaited(session.writeInput(bytes: cmd.codeUnits));
  }

  @override
  void initState() {
    super.initState();
    // Register a scrub callback so the auto-lock / wipe paths can wipe this
    // pane's scrollback alongside the DB key. The scrollback lives Rust-side;
    // `clear()` blanks the visible grid AND purges the scrollback history so
    // sensitive command output cannot be read back after the key is cleared
    // (a viewport scroll would leave that content in memory). See
    // ARCHITECTURE.md §5.1.
    _scrubFn = () {
      final session = _session;
      if (session != null) unawaited(session.clear());
    };
    TerminalScrubber.instance.register(_scrubFn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isActiveTab && widget.isFocused) _terminalFocus.requestFocus();
      _connectAndOpenShell();
    });
  }

  /// Tear down the per-connect progress plumbing. Idempotent — every
  /// `!mounted` early-return and the success path route through this so the
  /// subscription never leaks.
  void _disposeProgress() {
    _progressSub?.cancel();
    _progressSub = null;
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;

    // Wait for connection if still connecting.
    await conn.waitUntilReady();
    if (!mounted) {
      _disposeProgress();
      return;
    }
    // `state == connected` flips when the Rust actor publishes Connected, but
    // the russh handle is adopted asynchronously. Wait for the adopt to settle
    // before reading `conn.transport`.
    if (conn.isConnecting || conn.isConnected) {
      await conn.transportReady;
      if (!mounted) {
        _disposeProgress();
        return;
      }
    }
    _disposeProgress();

    if (!conn.isConnected) {
      _onConnectFailed(conn);
      return;
    }

    await _openSessionAndAttach(conn);
  }

  /// Disconnected branch — surface the failure and notify the workspace so
  /// status dots / connection bar update.
  void _onConnectFailed(Connection conn) {
    conn.state = SSHConnectionState.disconnected;
    final l10n = S.of(context);
    final error = conn.connectionError != null
        ? localizeError(l10n, conn.connectionError!)
        : l10n.errConnectionFailed;
    setState(() => _error = error);
    ref.read(connectionsProvider.notifier).notifyStateChanged();
  }

  /// Success branch — open the Rust terminal session on the adopted transport.
  /// Every async hop checks `mounted` so a mid-open dispose closes the freshly
  /// opened session instead of leaking it.
  Future<void> _openSessionAndAttach(Connection conn) async {
    try {
      AppLogger.instance.log(
        'Terminal session open: starting for connection ${conn.id}',
        name: 'TerminalPane',
      );
      final transport = conn.transport;
      if (transport == null || !transport.isConnected) {
        throw StateError('Not connected');
      }
      final isDark = AppTheme.isDark;
      final session = await transport.openTerminalSession(
        cols: _cols,
        rows: _rows,
        scrollback: ref.read(configProvider).scrollback,
        palette: TerminalPaletteFromTheme.fromAppTheme(),
      );
      if (!mounted) {
        // Pane disposed mid-open — drop the session so the Rust pump + shell
        // channel do not leak past dispose.
        session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _sessionEpoch++;
        _paletteIsDark = isDark;
      });
      AppLogger.instance.log(
        'Terminal session open: success for ${conn.id}',
        name: 'TerminalPane',
      );
      ref.read(connectionsProvider.notifier).notifyStateChanged();
    } catch (e) {
      AppLogger.instance.log(
        'Terminal session open failed: $e',
        name: 'TerminalPane',
        error: e,
      );
      if (!mounted) return;
      setState(() => _error = localizeError(S.of(context), e));
    }
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keyboard ownership = the focused pane of the foreground tab. The tab can
    // leave the foreground (`isActiveTab` flips) without the in-tab `isFocused`
    // flag changing, since `IndexedStack` keeps backgrounded tabs mounted.
    final hadFocus = oldWidget.isActiveTab && oldWidget.isFocused;
    final hasFocus = widget.isActiveTab && widget.isFocused;
    if (hadFocus && !hasFocus) {
      if (_terminalFocus.hasFocus) _terminalFocus.unfocus();
    }
    if (!hadFocus && hasFocus) {
      _terminalFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    TerminalScrubber.instance.unregister(_scrubFn);
    _progressSub?.cancel();
    _session?.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    // Re-push the palette to the live session on a brightness change so a
    // theme toggle re-themes the terminal (the engine re-resolves abstract
    // cell colors against the new palette on the next snapshot).
    _maybeRepushPalette();

    // Focus surface owns keyboard focus across the connect → live phases so
    // the tab-switch focus contract holds and zoom shortcuts dispatch. It
    // wraps the whole body (not just the live grid) so `_terminalFocus` stays
    // attached during the pre-session progress phase, when `requestFocus()`
    // fires from initState / didUpdateWidget. Full key-input encoding lands in
    // the input task; `handleKey` only consumes the local zoom combos today.
    final body = Focus(
      focusNode: _terminalFocus,
      autofocus: widget.isActiveTab && widget.isFocused,
      onKeyEvent: (_, event) => handleKey(event),
      child: _buildBody(fontSize),
    );

    // No border on panes — the 4px divider in TilingView separates them.
    // Route onFocused through a raw Listener.onPointerDown rather than
    // GestureDetector.onTap: onTap only fires on a clean tap, and any drift
    // during the click swallows the event, so the focused pane would stop
    // switching "every other click" when jumping between split panes.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onFocused?.call(),
      child: body,
    );
  }

  Widget _buildBody(double fontSize) {
    final error = _error;
    if (error != null) {
      return ColoredBox(
        color: AppTheme.bg2,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            error,
            style: AppFonts.mono(fontSize: fontSize, color: AppTheme.red),
          ),
        ),
      );
    }

    final session = _session;
    if (session == null) {
      // Pre-session connect phase — reuse the shared progress surface.
      return ConnectionProgress(
        connection: widget.connection,
        fontSize: fontSize,
      );
    }

    return TerminalGridView(
      // Re-key on the session epoch so a reconnect rebinds the event stream.
      key: ValueKey<int>(_sessionEpoch),
      session: session,
      fontSize: fontSize,
      onResize: _onResize,
      onScroll: _onScroll,
      onPointerSignal: _onPointerSignal,
      onClosed: _onSessionClosed,
    );
  }

  void _onScroll(int lineDelta) {
    final session = _session;
    if (session == null) return;
    unawaited(session.scroll(delta: lineDelta));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _adjustFontSize(event.scrollDelta.dy < 0 ? 1 : -1);
    }
  }

  /// Forward a viewport-size change to the Rust session and remember it so a
  /// later session-open / re-layout starts at the right grid size.
  void _onResize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    final session = _session;
    if (session == null) return;
    unawaited(session.resize(cols: cols, rows: rows));
  }

  void _onSessionClosed() {
    if (!mounted) return;
    setState(() => _error = S.of(context).errSessionClosed);
    ref.read(connectionsProvider.notifier).notifyStateChanged();
  }

  void _maybeRepushPalette() {
    final session = _session;
    if (session == null) return;
    final isDark = AppTheme.isDark;
    if (_paletteIsDark == isDark) return;
    _paletteIsDark = isDark;
    unawaited(
      session.setPalette(palette: TerminalPaletteFromTheme.fromAppTheme()),
    );
  }

  /// Keyboard dispatch for the live pane. Order matters: app-level combos
  /// (zoom, copy, paste) are claimed first so they never reach the shell as
  /// raw bytes; every other key-down / repeat is normalised to a
  /// [rust_terminal.TerminalKey] and forwarded through [rust_terminal.TerminalSession.sendKey],
  /// which reads the live terminal mode Rust-side and encodes the VT bytes.
  KeyEventResult handleKey(KeyEvent event) {
    // Only key-down and repeat produce input; key-up never does. Repeats
    // (auto-repeat held key) must reach the shell, so accept both.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final reg = AppShortcutRegistry.instance;

    _shortcuts ??= <AppShortcut, VoidCallback>{
      AppShortcut.zoomIn: _zoomIn,
      AppShortcut.zoomOut: _zoomOut,
      AppShortcut.zoomReset: _zoomReset,
      AppShortcut.terminalCopy: _copySelection,
      AppShortcut.terminalPaste: _pasteClipboard,
    };

    for (final entry in _shortcuts!.entries) {
      if (reg.matches(entry.key, event)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }

    return _forwardKey(event);
  }

  /// Normalise a key event and send it to the shell. Returns `handled` when
  /// the event maps to PTY bytes so the framework does not also treat it as
  /// a text-input / traversal event; `ignored` for bare modifiers and
  /// unmappable keys so other handlers (and IME) still see them.
  KeyEventResult _forwardKey(KeyEvent event) {
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    final key = terminalKeyFromEvent(
      event,
      HardwareKeyboard.instance.logicalKeysPressed,
    );
    if (key == null) return KeyEventResult.ignored;
    unawaited(session.sendKey(key: key));
    return KeyEventResult.handled;
  }

  /// Copy the active terminal selection to the clipboard. Selection set-up
  /// (mouse drag) lands in the selection task; this reads whatever the Rust
  /// engine currently holds so the Ctrl+Shift+C combo is reserved (never
  /// sent to the shell as raw bytes) and works once selection is wired.
  void _copySelection() {
    final session = _session;
    if (session == null) return;
    unawaited(_copySelectionAsync(session));
  }

  Future<void> _copySelectionAsync(
    rust_terminal.TerminalSession session,
  ) async {
    final text = await session.selectionText();
    if (text == null || text.isEmpty) return;
    TerminalClipboard.copyText(text);
  }

  /// Paste clipboard text into the shell via the Rust paste encoder, which
  /// wraps the body in bracketed-paste framing when the running program
  /// enabled it (and filters any embedded terminator) — so a multi-line
  /// paste lands as data, not as a burst of executed commands.
  void _pasteClipboard() {
    final session = _session;
    if (session == null) return;
    unawaited(_pasteClipboardAsync(session));
  }

  Future<void> _pasteClipboardAsync(
    rust_terminal.TerminalSession session,
  ) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    await session.paste(text: text);
  }

  Future<void> showSnippetPicker(BuildContext context) async {
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
}
