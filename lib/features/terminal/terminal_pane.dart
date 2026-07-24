import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/session/session_recorder.dart';
import '../../widgets/core/shortcut_registry.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../core/config/app_config.dart';
import '../../providers/broadcast_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../src/rust/api/terminal.dart' as rust_terminal;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/terminal/connection_progress.dart';
import '../../widgets/terminal/terminal_controller.dart';
import '../../widgets/terminal/terminal_key_input.dart';
import '../../widgets/terminal/terminal_view.dart';
import '../../widgets/terminal/terminal_palette_theme.dart';
import '../../widgets/terminal/terminal_pointer_input.dart';
import '../../widgets/terminal/terminal_search_bar.dart';
import '../../l10n/app_localizations.dart';
import '../snippets/snippet_picker.dart';
import 'broadcast_controller.dart';
import 'pane_recording_registry.dart';

/// A single terminal pane — a Rust-engine-backed [rust_terminal.TerminalSession]
/// rendered through the unified [TerminalView] (a [LiveTerminalController] over
/// the session), connected to one SSH shell.
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
  /// across `isFocused` / `isActiveTab` flips. Focus is managed explicitly
  /// by `initState` (post-frame) and `didUpdateWidget` — no `autofocus` on
  /// the `Focus` widget, which would race with the explicit transfer logic.
  final FocusNode _terminalFocus = FocusNode(debugLabel: 'TerminalPane');
  late final void Function() _scrubFn;

  rust_terminal.TerminalSession? _session;

  /// Controller bridging the live session's `events()`/`snapshot()` to the
  /// [TerminalView]. Recreated on each fresh session open (the prior one is
  /// disposed first); subscribes to `events()` exactly once, never per rebuild.
  LiveTerminalController? _controller;

  /// Per-tab broadcast controller this pane is registered with, or null
  /// when the pane is not part of a tab (single-pane / test callers). Held
  /// so `dispose` can unregister this pane's sink from the same controller
  /// it registered against.
  BroadcastController? _broadcast;

  /// Live recording state for this pane. Drives the connection-bar record
  /// button via [PaneRecordingRegistry] — the registry handle re-exports
  /// this [ValueListenable] so a single `ValueListenableBuilder` rebuilds
  /// the icon when recording starts / stops without churning the grid.
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);

  /// The active recorder for this pane, or null when not recording. The
  /// recorder owns its `.lfsr` / `.cast` file; `set_recorder` Rust-side
  /// forks the session bytes into it while it is attached.
  SessionRecorder? _recorder;

  /// Bumped each time a fresh session opens so the [TerminalView] (keyed on
  /// this) rebinds to the new [LiveTerminalController] rather than reusing the
  /// stale one.
  int _sessionEpoch = 0;

  StreamSubscription<ConnectionStep>? _progressSub;
  Map<AppShortcut, VoidCallback>? _shortcuts;

  /// Whether the terminal pane is in an error state.
  bool get hasError => _error != null;

  /// True when both the pane id and tab id are present — guards every
  /// broadcast-related path. Single-pane / test callers omit them.
  bool get _supportsBroadcast => widget.paneId != null && widget.tabId != null;

  String? _error;

  /// Last viewport size reported by the grid view. Held so a font-zoom or
  /// theme change that rebuilds the view re-pushes the size to the session.
  int _cols = 80;
  int _rows = 24;

  /// Brightness the live session's palette was last pushed for. A theme
  /// toggle re-pushes the palette via [rust_terminal.TerminalSession.setPalette].
  bool? _paletteIsDark;

  /// Whether the in-terminal search bar is open.
  bool _searchOpen = false;

  /// Matches from the last `TerminalSession.search`, in absolute grid-line
  /// coordinates. The highlight overlay and next/prev navigation derive
  /// from this list; empty when the query is empty or has no hit.
  List<rust_terminal.TerminalMatch> _matches = const [];

  /// Index of the focused match within [_matches], or `-1` when none.
  int _currentMatch = -1;

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
    final bytes = Uint8List.fromList(utf8.encode(cmd));
    unawaited(session.writeInput(bytes: bytes));
    _broadcastInput(BroadcastBytes(bytes));
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
    _registerRecordingHandle();
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
        _controller?.dispose();
        _session = session;
        _controller = LiveTerminalController(session);
        _sessionEpoch++;
        _paletteIsDark = isDark;
      });
      AppLogger.instance.log(
        'Terminal session open: success for ${conn.id}',
        name: 'TerminalPane',
      );
      _attachBroadcast(session);
      await _maybeAutoStartRecording(session, conn);
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

  // ── Broadcast ──────────────────────────────────────────────────────────

  /// Wire this pane into the per-tab broadcast controller. Runs after the
  /// session opens so the receiver sink has a live session to replay onto.
  /// The sink re-runs each fanned [BroadcastInput] against THIS pane's
  /// session — keys through `sendKey` (re-encoded against this pane's mode),
  /// bytes through `writeInput` — so a broadcast holds across panes whose
  /// programs differ in terminal mode.
  void _attachBroadcast(rust_terminal.TerminalSession session) {
    if (!_supportsBroadcast) return;
    final controller = ref.read(broadcastControllerProvider(widget.tabId!));
    _broadcast = controller;
    controller.registerSink(widget.paneId!, (input) {
      // Replay on this receiver's own session. A torn-down session
      // between dispatch and replay drops the input rather than faulting
      // the driver loop (the controller already isolates throws).
      switch (input) {
        case BroadcastKey(:final key):
          unawaited(session.sendKey(key: key));
        case BroadcastBytes(:final bytes):
          unawaited(session.writeInput(bytes: bytes));
      }
    });
  }

  /// Fan a driver-side input action to every receiver pane. No-op unless
  /// this pane is the active driver (the controller enforces the gate) or
  /// the pane is not part of a tab.
  void _broadcastInput(BroadcastInput input) {
    final controller = _broadcast;
    if (controller == null) return;
    final paneId = widget.paneId;
    if (paneId == null) return;
    controller.broadcastFrom(paneId, input);
  }

  // ── Recording ────────────────────────────────────────────────────────

  /// Register this pane's recording handle so the workspace connection
  /// bar's record button can find it by paneId. Runs once at mount; the
  /// registry holds a stable [ValueListenable] pointer that survives shell
  /// reconnects. `canRecord` is false for unsaved quick-connect panes —
  /// recordings need a session folder to land in, and the button hides
  /// itself when this is false.
  void _registerRecordingHandle() {
    final paneId = widget.paneId;
    if (paneId == null) return;
    PaneRecordingRegistry.instance.register(
      paneId,
      PaneRecordingHandle(
        isRecording: _isRecording,
        canRecord: widget.connection.sessionId != null,
        toggle: _toggleRecording,
      ),
    );
  }

  /// Auto-start recording when the session opted in via
  /// `Session.extras['record'] == true`. No-op for quick-connect
  /// (no `sessionId`) or sessions without the opt-in flag.
  Future<void> _maybeAutoStartRecording(
    rust_terminal.TerminalSession session,
    Connection conn,
  ) async {
    final sessionId = conn.sessionId;
    if (sessionId == null) return;
    final saved = ref.read(sessionMutatorProvider).get(sessionId);
    if (saved == null || saved.extrasBool('record') != true) return;
    await _startRecording(session, conn);
  }

  /// Start or stop recording for the open session. No-op when the session
  /// has not opened yet (the user mashed the button during the connect
  /// spinner) — the pane records no pre-session bytes either way.
  Future<void> _toggleRecording() async {
    final session = _session;
    if (session == null) return;
    if (_isRecording.value) {
      await _stopRecording(session);
      return;
    }
    await _startRecording(session, widget.connection);
  }

  /// Open a recorder, attach it to the Rust pump (which then tees output +
  /// input bytes to it), and flip the recording flag. Recorder open is
  /// best-effort: a null recorder (unsaved session / open failure) leaves
  /// recording off rather than blocking the session.
  Future<void> _startRecording(
    rust_terminal.TerminalSession session,
    Connection conn,
  ) async {
    final sessionId = conn.sessionId;
    if (sessionId == null) return;
    final saved = ref.read(sessionMutatorProvider).get(sessionId);
    if (saved == null) return;
    final recorder = await SessionRecorder.open(
      sessionId: sessionId,
      shellLabel: saved.label,
      width: _cols,
      height: _rows,
    );
    if (recorder == null) return;
    if (!mounted || _session != session) {
      // Pane disposed or session swapped mid-open — seal the half-open
      // file rather than leaving it with only a header.
      await recorder.close();
      return;
    }
    _recorder = recorder;
    session.setRecorder(id: recorder.handleId);
    _isRecording.value = true;
  }

  /// Detach the recorder from the pump and seal the file. Idempotent —
  /// a no-op when not recording.
  Future<void> _stopRecording(rust_terminal.TerminalSession session) async {
    final recorder = _recorder;
    if (recorder == null) return;
    // Detach the fork first so no further bytes tee into a closing file,
    // then seal it.
    session.setRecorder(id: null);
    _recorder = null;
    _isRecording.value = false;
    await recorder.close();
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
      // Defer requestFocus to after the build — addPostFrameCallback
      // coalesces with initState's callback in the same frame, so the
      // single callback sees the latest flags and requests focus once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isActiveTab && widget.isFocused) {
          _terminalFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    TerminalScrubber.instance.unregister(_scrubFn);
    _progressSub?.cancel();
    final paneId = widget.paneId;
    if (paneId != null) {
      _broadcast?.unregisterSink(paneId);
      PaneRecordingRegistry.instance.unregister(paneId);
    }
    // Seal the recording before the session drops so its trailing bytes
    // land before the shell closes. Best-effort, fire-and-forget.
    final recorder = _recorder;
    if (recorder != null) unawaited(recorder.close());
    _controller?.dispose();
    _session?.dispose();
    _terminalFocus.dispose();
    _isRecording.dispose();
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
    // `autofocus` is intentionally omitted — it only fires on initial mount
    // and its dynamic toggling races with the explicit didUpdateWidget focus
    // transfer (see `fce12693` history: autofocus + didUpdateWidget together
    // still leaves focus stuck on the most-recently-opened tab).
    final body = Focus(
      focusNode: _terminalFocus,
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

    final controller = _controller;
    if (controller == null) {
      // Pre-session connect phase — reuse the shared progress surface.
      return ConnectionProgress(
        connection: widget.connection,
        fontSize: fontSize,
      );
    }

    final grid = TerminalView(
      // Re-key on the session epoch so a reconnect rebinds the controller.
      key: ValueKey<int>(_sessionEpoch),
      controller: controller,
      config: const TerminalViewConfig.interactive(),
      fontSize: fontSize,
      onResize: _onResize,
      onScroll: _onScroll,
      onPointerSignal: _onPointerSignal,
      onClosed: _onSessionClosed,
      onCopy: _copySelection,
      onPaste: _pasteClipboard,
      searchMatches: _searchOpen ? _matches : const [],
      activeMatchIndex: _searchOpen ? _currentMatch : -1,
    );
    if (!_searchOpen) return grid;
    return Column(
      children: [
        TerminalSearchBar(
          onQueryChanged: _onSearchQueryChanged,
          onNext: _nextMatch,
          onPrevious: _prevMatch,
          onClose: _closeSearch,
          hasMatches: _matches.isNotEmpty,
          matchLabel: _matchLabel(),
        ),
        Expanded(child: grid),
      ],
    );
  }

  /// `current/total` for the search bar, or null when there is nothing to
  /// label (empty query / no matches). Pure number formatting — no l10n.
  String? _matchLabel() {
    if (_matches.isEmpty) return null;
    return '${_currentMatch + 1}/${_matches.length}';
  }

  void _onScroll(int lineDelta) {
    final controller = _controller;
    if (controller == null) return;
    controller.scroll(lineDelta);
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

    // Esc closes the search bar only while it is open; otherwise Esc must
    // reach the shell (vim, less, …), so it is not a blanket shortcut.
    if (_searchOpen && reg.matches(AppShortcut.terminalCloseSearch, event)) {
      _closeSearch();
      return KeyEventResult.handled;
    }

    _shortcuts ??= <AppShortcut, VoidCallback>{
      AppShortcut.zoomIn: _zoomIn,
      AppShortcut.zoomOut: _zoomOut,
      AppShortcut.zoomReset: _zoomReset,
      AppShortcut.terminalCopy: _copySelection,
      AppShortcut.terminalPaste: _pasteClipboard,
      AppShortcut.terminalSearch: _openSearch,
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
    // Mirror the logical key to receivers so each re-encodes against its
    // own terminal mode (arrows under DECCKM, etc.).
    _broadcastInput(BroadcastKey(key));
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
    // Sensitive-content routing + 30s auto-wipe live in TerminalClipboard
    // (SecureClipboard underneath) — reused so the new engine's copy obeys
    // the same clipboard threat model as the old renderer.
    TerminalClipboard.copyText(text);
    // Clear through the controller, not the raw session, so it pulses the
    // repaint signal and the highlight actually disappears — the engine
    // raises no Wakeup for a host-driven selection change.
    _controller?.clearSelection();
  }

  // ── In-terminal search ─────────────────────────────────────────────────

  void _openSearch() {
    if (_searchOpen) return;
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    _controller?.clearSelection();
    setState(() {
      _searchOpen = false;
      _matches = const [];
      _currentMatch = -1;
    });
    _terminalFocus.requestFocus();
  }

  void _onSearchQueryChanged(String query) {
    final session = _session;
    if (session == null) return;
    unawaited(_runSearch(session, query));
  }

  Future<void> _runSearch(
    rust_terminal.TerminalSession session,
    String query,
  ) async {
    final matches = await session.search(query: query);
    if (!mounted) return;
    setState(() {
      _matches = matches;
      _currentMatch = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _revealMatch(session, 0);
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    _focusMatch((_currentMatch + 1) % _matches.length);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    _focusMatch((_currentMatch - 1 + _matches.length) % _matches.length);
  }

  void _focusMatch(int index) {
    final session = _session;
    if (session == null) return;
    setState(() => _currentMatch = index);
    _revealMatch(session, index);
  }

  /// Scroll the focused match into view so next/prev never lands on an
  /// off-screen hit. The scroll delta is computed against the live frame's
  /// offset; `scroll` clamps internally so an over-scroll is harmless.
  void _revealMatch(rust_terminal.TerminalSession session, int index) {
    if (index < 0 || index >= _matches.length) return;
    final frame = session.snapshot();
    final delta = scrollDeltaToRevealLine(
      matchLine: _matches[index].line,
      displayOffset: frame.displayOffset,
      rows: frame.rows,
    );
    if (delta != 0) unawaited(session.scroll(delta: delta));
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
    // Mirror the paste body to receivers. They write it verbatim — the
    // driver's session already applied any bracketed-paste framing when it
    // wrote, but each receiver re-frames on its own `writeInput`/`paste`
    // path is unnecessary here: the user intent is "the same text reaches
    // every shell", so the raw text bytes are fanned and each receiver's
    // shell consumes them directly.
    _broadcastInput(BroadcastBytes(Uint8List.fromList(utf8.encode(text))));
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
