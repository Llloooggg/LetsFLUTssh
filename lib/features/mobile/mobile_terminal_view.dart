import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/config_provider.dart';
import '../../src/rust/api/terminal.dart' as rust_terminal;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/terminal/connection_progress.dart';
import '../../widgets/terminal/terminal_controller.dart';
import '../../widgets/terminal/terminal_palette_theme.dart';
import '../../widgets/terminal/terminal_view.dart';
import '../snippets/snippet_picker.dart';
import 'ssh_keyboard_bar.dart';
import 'terminal_copy_overlay.dart';

/// Full-screen mobile terminal: a Rust-engine-backed
/// [rust_terminal.TerminalSession] rendered through the unified [TerminalView]
/// (a [LiveTerminalController] over the session), with an SSH keyboard bar
/// above the soft keyboard.
///
/// No tiling/splitting — single pane, full screen.
///
/// **Input model.** The on-bar keys build logical [rust_terminal.TerminalKey]s
/// (sticky Ctrl / Alt folded in) and feed `TerminalSession.sendKey`, which
/// encodes the VT bytes Rust-side against the live terminal mode. System
/// soft-keyboard text is captured by a hidden text field and routed the same
/// way, one [rust_terminal.TerminalKey] per typed character so the bar's
/// modifiers apply.
///
/// **Gestures.** One-finger drags scroll the scrollback. Font size is driven
/// exclusively by the Settings slider — pinch-to-zoom is intentionally absent
/// (it drove a per-frame resize that visibly reshuffled the grid).
///
/// **Copy mode.** Tapping the Copy button in the keyboard bar enters a
/// trackpad-style [TerminalCopyOverlay]: a virtual cursor overlays the
/// terminal, single-finger drags move it in cell units, the "Set anchor"
/// bar button drops the selection start, and a further drag extends it. The
/// selection is driven entirely through the Rust engine's
/// `setSelection` / `selectionText`.
class MobileTerminalView extends ConsumerStatefulWidget {
  final Connection connection;

  const MobileTerminalView({super.key, required this.connection});

  @override
  ConsumerState<MobileTerminalView> createState() => _MobileTerminalViewState();
}

class _MobileTerminalViewState extends ConsumerState<MobileTerminalView> {
  late final void Function() _scrubFn;

  final _keyboardKey = GlobalKey<SshKeyboardBarState>();
  final _copyOverlayKey = GlobalKey<TerminalCopyOverlayState>();

  /// Hidden text field that captures soft-keyboard input. Tapping the
  /// terminal focuses it (summoning the keyboard); each change is diffed to
  /// the inserted text and routed to the session.
  final _imeController = TextEditingController();
  final _imeFocus = FocusNode(debugLabel: 'MobileTerminalIme');

  rust_terminal.TerminalSession? _session;

  /// Controller bridging the live session into the [TerminalView]. Recreated
  /// on each fresh session open (the prior one disposed first).
  LiveTerminalController? _controller;

  /// Bumped on each fresh session open so the [TerminalView] (keyed on this)
  /// rebinds to the new controller rather than the stale one.
  int _sessionEpoch = 0;

  /// Last viewport size reported by the grid view — re-pushed to the session
  /// after a re-layout / font-zoom.
  int _cols = 80;
  int _rows = 24;

  /// Brightness the live palette was last pushed for; a theme toggle
  /// re-pushes via [rust_terminal.TerminalSession.setPalette].
  bool? _paletteIsDark;

  String? _error;
  StreamSubscription<ConnectionStep>? _progressSub;
  double _fontSize = 14.0;
  bool _copyMode = false;

  /// Manual pointer tracking — the outer [Listener] mirrors every active
  /// pointer here so copy mode can pan the virtual cursor on single-finger
  /// drags.
  final Map<int, Offset> _pointers = {};

  /// Debounced soft-keyboard inset so the bar slides smoothly while the
  /// terminal area only re-lays-out (and re-resizes the engine grid) once
  /// the animation settles, not once per frame.
  double _appliedKeyboardInset = 0;
  Timer? _insetSettleTimer;
  static const _insetSettleDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _scrubFn = () {
      final session = _session;
      if (session != null) unawaited(session.clear());
    };
    TerminalScrubber.instance.register(_scrubFn);
    // Delay connect until after the first frame so the grid view reports the
    // real viewport size before the shell opens — opening at the default
    // 80x24 then resizing garbles the first lines on a phone viewport.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connectAndOpenSession();
    });
  }

  void _scheduleKeyboardInsetSettle(double raw) {
    if (raw == _appliedKeyboardInset) return;
    _insetSettleTimer?.cancel();
    _insetSettleTimer = Timer(_insetSettleDuration, () {
      if (!mounted) return;
      setState(() => _appliedKeyboardInset = raw);
    });
  }

  Future<void> _connectAndOpenSession() async {
    final conn = widget.connection;
    await conn.waitUntilReady();
    if (!mounted) {
      _disposeProgress();
      return;
    }
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

  void _disposeProgress() {
    _progressSub?.cancel();
    _progressSub = null;
  }

  void _onConnectFailed(Connection conn) {
    conn.state = SSHConnectionState.disconnected;
    final l10n = S.of(context);
    final error = conn.connectionError != null
        ? localizeError(l10n, conn.connectionError!)
        : l10n.errConnectionFailed;
    setState(() => _error = error);
  }

  Future<void> _openSessionAndAttach(Connection conn) async {
    try {
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
    } catch (e) {
      AppLogger.instance.log(
        'Mobile terminal session open failed: $e',
        name: 'MobileTerminal',
        error: e,
      );
      if (!mounted) return;
      setState(() => _error = localizeError(S.of(context), e));
    }
  }

  @override
  void dispose() {
    TerminalScrubber.instance.unregister(_scrubFn);
    _progressSub?.cancel();
    _insetSettleTimer?.cancel();
    _imeController.dispose();
    _imeFocus.dispose();
    _controller?.dispose();
    _session?.dispose();
    super.dispose();
  }

  // ── Input ────────────────────────────────────────────────────────────

  /// Forward a logical key from the keyboard bar to the session. Re-encoded
  /// Rust-side against the live mode.
  void _onBarKey(rust_terminal.TerminalKey key) {
    final session = _session;
    if (session == null) return;
    unawaited(session.sendKey(key: key));
  }

  /// Diff the hidden IME field on each change and send the inserted text. We
  /// reset the field to empty after each change so the next change carries
  /// only the freshly-typed text — the terminal owns the real text buffer,
  /// the field is a pure capture surface. Each character is sent as its own
  /// [rust_terminal.TerminalKey] so the bar's sticky Ctrl / Alt fold in.
  void _onImeChanged(String value) {
    if (value.isEmpty) return;
    final session = _session;
    _imeController.clear();
    if (session == null) return;
    final bar = _keyboardKey.currentState;
    final ctrl = bar?.ctrlActive ?? false;
    final alt = bar?.altActive ?? false;
    for (final rune in value.runes) {
      // Newline / tab must encode as the named Enter / Tab key so the Rust
      // encoder applies the live mode (CR vs CR+LF under LNM, etc.) — a bare
      // Char(0x0A) would type a literal control byte instead.
      final name = switch (rune) {
        0x0A || 0x0D => const rust_terminal.TerminalKeyName.enter(),
        0x09 => const rust_terminal.TerminalKeyName.tab(),
        _ => rust_terminal.TerminalKeyName.char(code: rune),
      };
      unawaited(
        session.sendKey(
          key: rust_terminal.TerminalKey(
            name: name,
            ctrl: ctrl,
            alt: alt,
            shift: false,
            meta: false,
          ),
        ),
      );
    }
    bar?.consumeOneShotModifiers();
  }

  void _paste() {
    final session = _session;
    if (session == null) return;
    unawaited(_pasteAsync(session));
  }

  Future<void> _pasteAsync(rust_terminal.TerminalSession session) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    await session.paste(text: text);
  }

  /// Open the snippet picker and send the chosen command with a trailing
  /// newline — matching the desktop pane.
  Future<void> _showSnippets() async {
    final session = _session;
    if (session == null) return;
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
    if (command == null) return;
    final payload = command.endsWith('\n') ? command : '$command\n';
    await session.writeInput(bytes: Uint8List.fromList(utf8.encode(payload)));
  }

  // ── Pointer tracking ─────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && _copyMode) {
      _copyOverlayKey.currentState?.onCursorPan(e.delta);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
  }

  /// Summon the soft keyboard on a tap of the terminal area (outside copy
  /// mode). Industry-standard: one explicit tap rather than auto-opening the
  /// keyboard the moment the tab is shown.
  void _focusKeyboard() {
    if (_copyMode) return;
    if (!_imeFocus.hasFocus) _imeFocus.requestFocus();
  }

  // ── Copy mode ────────────────────────────────────────────────────────

  void _onCopyModeChanged(bool active) {
    setState(() => _copyMode = active);
    if (active) {
      // Drop the soft keyboard so the whole viewport is free for the
      // trackpad cursor.
      _imeFocus.unfocus();
    }
  }

  void _onSetCopyAnchor() {
    if (!_copyMode) return;
    _copyOverlayKey.currentState?.onAnchorDown();
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<void> _copyFromOverlay() async {
    final session = _session;
    if (session == null) return;
    HapticFeedback.lightImpact();
    final text = await session.selectionText();
    if (text != null && text.isNotEmpty) {
      // Reuse the shared sensitive-content routing + auto-wipe path.
      TerminalClipboard.copyText(text);
    }
    unawaited(session.clearSelection());
    _keyboardKey.currentState?.exitCopyMode();
  }

  void _onSetSelection(int startRow, int startCol, int endRow, int endCol) {
    final session = _session;
    if (session == null) return;
    unawaited(
      session
          .setSelection(
            startRow: startRow,
            startCol: startCol,
            endRow: endRow,
            endCol: endCol,
            kind: rust_terminal.TerminalSelectionKind.simple,
          )
          .then((_) {
            // The engine raises no Wakeup for a host-driven selection;
            // rebuild so the grid pulls a fresh snapshot with the highlight.
            if (mounted) setState(() {});
          }),
    );
  }

  void _onClearSelection() {
    final session = _session;
    if (session == null) return;
    unawaited(session.clearSelection());
  }

  void _onCopyScroll(int lineDelta) {
    final session = _session;
    if (session == null) return;
    unawaited(session.scroll(delta: lineDelta));
  }

  // ── Grid callbacks ───────────────────────────────────────────────────

  void _onResize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    final session = _session;
    if (session == null) return;
    unawaited(session.resize(cols: cols, rows: rows));
  }

  void _onScroll(int lineDelta) {
    final session = _session;
    if (session == null) return;
    unawaited(session.scroll(delta: lineDelta));
  }

  void _onSessionClosed() {
    if (!mounted) return;
    setState(() => _error = S.of(context).errSessionClosed);
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

  @override
  Widget build(BuildContext context) {
    _fontSize = ref.watch(configProvider.select((c) => c.fontSize));
    _maybeRepushPalette();

    final rawKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    _scheduleKeyboardInsetSettle(rawKeyboardInset);
    const navBarHeight = AppTheme.itemHeightXl;
    const barHeight = AppTheme.itemHeightLg;
    final barBottomLive = math.max(navBarHeight, rawKeyboardInset);
    final terminalBottomSettled =
        math.max(navBarHeight, _appliedKeyboardInset) + barHeight;
    final anchorSet =
        _copyMode && (_copyOverlayKey.currentState?.anchorSet ?? false);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: terminalBottomSettled,
          child: SelectionContainer.disabled(child: _buildTerminalArea()),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: barBottomLive,
          height: barHeight,
          child: SelectionContainer.disabled(
            child: SshKeyboardBar(
              key: _keyboardKey,
              onKey: _onBarKey,
              onPaste: _paste,
              onSnippets: _showSnippets,
              onCopyModeChanged: _onCopyModeChanged,
              onCopyPressed: _copyFromOverlay,
              onAnchorPressed: _onSetCopyAnchor,
              anchorSet: anchorSet,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalArea() {
    final error = _error;
    if (error != null) {
      return ColoredBox(
        color: AppTheme.bg2,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            error,
            style: AppFonts.mono(fontSize: _fontSize, color: AppTheme.red),
          ),
        ),
      );
    }
    final session = _session;
    final controller = _controller;
    if (session == null || controller == null) {
      return ConnectionProgress(
        connection: widget.connection,
        fontSize: _fontSize,
      );
    }
    return _buildLiveTerminal(session, controller);
  }

  Widget _buildLiveTerminal(
    rust_terminal.TerminalSession session,
    LiveTerminalController controller,
  ) {
    // Mobile drives input through the IME field and selection through the
    // copy overlay, not the desktop drag-select / mouse-report path — so the
    // view only renders + scrolls + reports resize, with the live cursor on.
    final grid = TerminalView(
      key: ValueKey<int>(_sessionEpoch),
      controller: controller,
      config: const TerminalViewConfig.readOnly(
        selectable: false,
        showCursor: true,
      ),
      fontSize: _fontSize,
      onResize: _onResize,
      onScroll: _onScroll,
      onClosed: _onSessionClosed,
    );
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: GestureDetector(
        // A tap that did not drag summons the soft keyboard. The grid's own
        // pointer handling drives scroll; this only captures the tap.
        behavior: HitTestBehavior.translucent,
        onTap: _focusKeyboard,
        child: Stack(
          children: [
            // AbsorbPointer in copy mode so the grid's own scroll/selection
            // recognisers don't fight the virtual cursor — the outer
            // Listener still observes pointers via its ancestor hit-test so
            // cursor-pan deltas keep flowing.
            AbsorbPointer(absorbing: _copyMode, child: grid),
            // Offstage IME capture field. Zero-size so it never paints; its
            // focus node owns the system keyboard, and each change feeds the
            // session via _onImeChanged.
            _buildImeCapture(),
            if (_copyMode)
              Positioned.fill(
                child: TerminalCopyOverlay(
                  key: _copyOverlayKey,
                  snapshotProvider: session.snapshot,
                  onSetSelection: _onSetSelection,
                  onClearSelection: _onClearSelection,
                  onScroll: _onCopyScroll,
                  fontSize: _fontSize,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImeCapture() {
    return Positioned(
      width: 0,
      height: 0,
      child: Opacity(
        opacity: 0,
        child: EditableText(
          controller: _imeController,
          focusNode: _imeFocus,
          onChanged: _onImeChanged,
          // Multi-line keeps Enter producing a newline character the diff
          // can capture, rather than a submit action that loses it; the
          // session encodes Enter from the char itself.
          maxLines: null,
          cursorColor: AppTheme.termCursor,
          backgroundCursorColor: AppTheme.termCursor,
          style: TextStyle(fontSize: _fontSize, color: AppTheme.fg),
          keyboardType: TextInputType.text,
          // Prediction-free so the IME doesn't rewrite already-sent text.
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
        ),
      ),
    );
  }
}
