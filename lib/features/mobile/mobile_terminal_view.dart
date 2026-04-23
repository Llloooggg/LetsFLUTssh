import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import '../../core/connection/progress_writer.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../core/ssh/shell_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../utils/terminal_clipboard.dart';
import '../snippets/snippet_picker.dart';
import '../terminal/cursor_overlay.dart';
import 'ssh_keyboard_bar.dart';
import 'terminal_copy_overlay.dart';

/// Full-screen mobile terminal with SSH keyboard bar.
///
/// No tiling/splitting — single pane, full screen.
///
/// **Gestures**. One-finger drags go to xterm (tap, scroll, long-press →
/// select-word). Font size is driven exclusively by the Settings slider —
/// pinch-to-zoom is intentionally absent: every pinch frame updated
/// `_fontSize`, which propagated into `TerminalView` and triggered a
/// per-frame `Terminal.buffer.resize` (columns change with cell width),
/// and even xterm's reflow path leaves the scrollback visibly shuffled
/// across dozens of such resize calls. One font change per settings
/// commit is a manageable single reflow; dozens per pinch are not.
///
/// **Copy mode**. Tapping the Copy button in the keyboard bar enters a
/// trackpad-style [TerminalCopyOverlay]: xterm pointer input is
/// suspended, a virtual cursor overlays the terminal, single-finger
/// drags move the cursor in cell units. The selection anchor is
/// dropped on the *first pointer-up* of the session, not on the first
/// pointer-down — this gives the user an explicit "aim" phase: drag
/// the virtual cursor to the start cell, lift → anchor drops, then
/// drag again to extend. Subsequent pointer-ups don't re-anchor, so
/// the user can lift + re-touch without losing progress.
class MobileTerminalView extends ConsumerStatefulWidget {
  final Connection connection;

  const MobileTerminalView({super.key, required this.connection});

  @override
  ConsumerState<MobileTerminalView> createState() => _MobileTerminalViewState();
}

class _MobileTerminalViewState extends ConsumerState<MobileTerminalView> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;

  /// Shared with the copy overlay. Passing a `ScrollController`
  /// into `TerminalView` gives us a handle to the viewport offset
  /// so copy mode can scroll the buffer when the virtual cursor
  /// hits the top / bottom edge during selection extension.
  /// Without this the cursor clamps inside the visible viewport,
  /// making it impossible to select more than one screen's worth
  /// of scrollback in one gesture.
  final ScrollController _terminalScrollController = ScrollController();
  final _keyboardKey = GlobalKey<SshKeyboardBarState>();
  final _copyOverlayKey = GlobalKey<TerminalCopyOverlayState>();
  ShellConnection? _shellConn;

  /// Whether the terminal pane is in an error state (for potential retry).
  bool hasError = false;
  StreamSubscription<ConnectionStep>? _progressSub;
  double _fontSize = 14.0;
  bool _copyMode = false;

  /// Manual pointer tracking — the outer [Listener] mirrors every active
  /// pointer here so the copy-mode overlay can pan the virtual cursor
  /// on single-finger drags. Two-finger gestures are not used anywhere
  /// (pinch-to-zoom was removed per the class docstring); tracking
  /// them here is still useful for future multi-touch gestures.
  final Map<int, Offset> _pointers = {};

  /// Debounced soft-keyboard inset. The raw `viewInsets.bottom` ticks
  /// once per animation frame while the keyboard slides in or out,
  /// which — fed straight into the layout — would drive a terminal
  /// height change and a matching `Terminal.buffer.resize` every
  /// frame. Each frame-level resize is lossy on xterm's rows-shrink
  /// path: lines near the cursor shuffle in and out of scrollback,
  /// and if the user also scrolls the terminal mid-animation the
  /// visible scrollback appears to rip. The debouncer freezes layout
  /// at the previous stable inset until the raw value has held still
  /// for [_insetSettleDuration]; then we apply one resize for the
  /// whole animation.
  double _appliedKeyboardInset = 0;
  Timer? _insetSettleTimer;
  static const _insetSettleDuration = Duration(milliseconds: 200);

  // `xterm.dart` 4.0.0 ships a known scrollback-corruption bug in
  // `Buffer.scrollUp` / `scrollDown` (issue #222): the in-place index
  // shift leaves detached `BufferLine` objects at intermediate slots
  // of the `IndexAwareCircularBuffer`, and in release mode (no
  // assertions) this silently mis-indexes lines — visible as
  // "chunks of text disappearing from the middle of the scrollback"
  // during vim / tmux / htop / paste-driven escape-sequence traffic.
  // Client-side workarounds (eviction watchdog via `CellAnchor`,
  // slow-fling `ClampingScrollPhysics`, scroll-offset compensation
  // via `ScrollPosition.correctBy`) were tried and reverted: they
  // masked the symptom without fixing the root cause, and xterm's
  // own `_scrollToBottom` path bypasses the shared scroll controller
  // anyway (issue #218). The honest stance is to wait on the
  // upstream patch.
  //
  //   https://github.com/TerminalStudio/xterm.dart/issues/222
  //
  // Related upstream items that would let us re-enable a subset of
  // the mitigations cleanly once merged: PR #219 adds a
  // `scrollOnInput` flag (stops xterm fighting our scroll position);
  // PR #220 adds a `scrollPhysics` parameter (lets us install a
  // velocity cap without a `ScrollConfiguration` hack).

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider);
    _terminal = Terminal(maxLines: config.scrollback);
    TerminalScrubber.instance.register(_terminal);
    _terminalController = TerminalController();
    // Hard-block xterm's built-in touch selection (long-press → word,
    // finger-drag → character select). xterm's [TerminalGestureHandler]
    // internally calls `renderTerminal.selectWord/selectCharacters` on
    // every touch long-press + drag; there is no public flag to turn
    // that off, and winning the Flutter gesture arena at a parent level
    // would also steal the scroll gesture. Instead we listen to the
    // controller and drop any selection that appears while the copy-mode
    // overlay is not active — that overlay is the only sanctioned
    // selection surface on mobile. The listener no-ops when selection
    // is already null, so `clearSelection()` does not recurse through
    // `notifyListeners`. Users who want to select text must enter copy
    // mode via the keyboard bar's 📋 button.
    _terminalController.addListener(_enforceCopyModeSelectionGuard);
    // Delay connection until after the first frame so TerminalView can
    // set the correct terminal dimensions. Without this, the shell opens
    // with the default 80x24 and the server sends output for that size;
    // when TerminalView later resizes, the buffer rearranges and causes
    // duplicated/garbled first lines on mobile (where the actual viewport
    // differs significantly from 80x24).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndOpenShell();
    });
  }

  /// See [initState] for the rationale — xterm's built-in touch
  /// selection is blocked outside copy mode by clearing any selection
  /// that lands on the controller when `_copyMode` is false.
  void _enforceCopyModeSelectionGuard() {
    if (_copyMode) return;
    if (_terminalController.selection == null) return;
    _terminalController.clearSelection();
  }

  /// Arm the debounce timer so we update [_appliedKeyboardInset] only
  /// after the raw `viewInsets.bottom` has stopped ticking for
  /// [_insetSettleDuration]. Called from [build] — Flutter rebuilds
  /// the subtree on every inset tick during the keyboard slide
  /// animation (we read `MediaQuery.viewInsetsOf(context)` there to
  /// register the dependency), so this runs once per animation frame
  /// and keeps resetting the timer until the animation ends. Takes
  /// the raw value as an argument so we don't re-read MediaQuery in
  /// the timer callback — by the time the callback fires the context
  /// may have been deactivated.
  void _scheduleKeyboardInsetSettle(double raw) {
    if (raw == _appliedKeyboardInset) return;
    _insetSettleTimer?.cancel();
    _insetSettleTimer = Timer(_insetSettleDuration, () {
      if (!mounted) return;
      setState(() => _appliedKeyboardInset = raw);
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

    _progressSub = writer.subscribe(tracker);
    await conn.waitUntilReady();
    _progressSub?.cancel();
    _progressSub = null;
    tracker.dispose();

    if (!conn.isConnected) {
      if (mounted) {
        final error = conn.connectionError != null
            ? localizeError(l10n, conn.connectionError!)
            : l10n.errConnectionFailed;
        _terminal.write('\x1B[?25h\x1B[31m$error\x1B[0m\r\n');
        setState(() => hasError = true);
      }
      return;
    }

    try {
      // Clear progress log before opening shell — openShell wires stdout
      // to terminal.write(), so any server output must not be erased.
      writer.clear();
      _shellConn = await ShellHelper.openShell(
        connection: conn,
        terminal: _terminal,
        onDone: () {
          if (mounted) {
            setState(() => hasError = true);
          }
        },
      );

      // Override terminal.onOutput to apply keyboard bar modifiers
      // (Ctrl/Alt) to system keyboard input before sending to shell.
      //
      // Encode via `utf8.encode` — `String.codeUnits` returns UTF-16
      // code units, and `Uint8List.fromList` masks each element to its
      // low byte, which silently collapses every non-ASCII codepoint
      // onto the 0x00–0xFF range. On a Russian Gboard long-press the
      // symptom was Cyrillic letters landing as ASCII punctuation /
      // digits: U+0430 `а` → 0x30 `0`, U+0440 `р` → 0x40 `@`, and so
      // on across U+0430..U+044F → 0x30..0x4F. The same truncation
      // would silently corrupt CJK, Arabic, emoji and every other
      // non-ASCII script. `utf8.encode` produces the correct
      // multi-byte sequence the SSH shell expects.
      _terminal.onOutput = (data) {
        final transformed =
            _keyboardKey.currentState?.applyModifiers(data) ?? data;
        _shellConn?.shell.write(Uint8List.fromList(utf8.encode(transformed)));
      };

      if (mounted) setState(() {});
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'MobileTerminal',
        error: e,
      );
      if (mounted) {
        final localized = localizeError(l10n, e);
        _terminal.write('\x1B[?25h\x1B[31m$localized\x1B[0m\r\n');
        setState(() => hasError = true);
      }
    }
  }

  @override
  void dispose() {
    TerminalScrubber.instance.unregister(_terminal);
    _progressSub?.cancel();
    _shellConn?.close();
    _insetSettleTimer?.cancel();
    _terminalController.removeListener(_enforceCopyModeSelectionGuard);
    _terminalController.dispose();
    _terminalScrollController.dispose();
    super.dispose();
  }

  void _onKeyboardInput(String data) {
    _shellConn?.shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  void _paste() {
    TerminalClipboard.paste(_terminal);
  }

  /// Open the snippet picker and, if the user picks a snippet, send the
  /// command to the shell with a trailing newline — matching the desktop
  /// terminal pane behaviour.
  Future<void> _showSnippets() async {
    final shell = _shellConn?.shell;
    if (shell == null) return;
    final command = await SnippetPicker.show(
      context,
      sessionId: widget.connection.sessionId,
    );
    if (command == null) return;
    final payload = command.endsWith('\n') ? command : '$command\n';
    shell.write(Uint8List.fromList(utf8.encode(payload)));
  }

  // ── Pointer tracking ─────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    // Multi-touch is intentionally unused: pinch-to-zoom was removed
    // because every pinch frame drove a `_fontSize` mutation that
    // propagated through `TerminalView` into `Terminal.buffer.resize`,
    // which reflowed columns and reshuffled scrollback dozens of
    // times per gesture. Font size is now driven exclusively by the
    // Settings slider (one commit = one reflow).
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && _copyMode) {
      _copyOverlayKey.currentState?.onCursorPan(e.delta);
    }
    // Single-finger outside copy mode: do nothing — the pointer event
    // has already reached xterm (Listener does not consume events),
    // which handles tap / long-press / drag-select on its own. The
    // controller-side guard in [_enforceCopyModeSelectionGuard] wipes
    // any selection xterm tries to stamp.
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    // Anchor drop is no longer bound to pointer-up. Earlier revisions
    // auto-committed the anchor on the first release, which forced
    // the user to land the cursor in a single uninterrupted drag —
    // too demanding on a phone viewport where the target cell is
    // often under the thumb and the user needs to lift + re-grip to
    // aim. The explicit "Set anchor" button in the copy-mode bar row
    // now commits the anchor; lifts are free aim passes until then.
  }

  /// Fired by the copy-mode row's "Set anchor" button. Drops the
  /// selection anchor at the current virtual cursor position and
  /// flips the bar from the aim hint to the extend hint.
  void _onSetCopyAnchor() {
    if (!_copyMode) return;
    _copyOverlayKey.currentState?.onAnchorDown();
    HapticFeedback.selectionClick();
    // `anchorSet` is exposed via the overlay's GlobalKey state and the
    // bar reads it through the `anchorSet` prop on every build;
    // `setState` forces the re-read so the row's affordances flip to
    // the post-anchor layout (Copy replaces the anchor button).
    if (mounted) setState(() {});
  }

  // ── Copy mode ────────────────────────────────────────────────────────

  void _onCopyModeChanged(bool active) {
    setState(() => _copyMode = active);
  }

  void _copyFromOverlay() {
    HapticFeedback.lightImpact();
    TerminalClipboard.copy(_terminal, _terminalController);
    _keyboardKey.currentState?.exitCopyMode();
  }

  @override
  Widget build(BuildContext context) {
    // React to font size changes from the Settings slider. This
    // triggers an xterm `buffer.resize` (cell width + height both
    // change, so columns AND rows move), which runs one reflow.
    // Accepted tradeoff — single commit per slider release on the
    // settings side means a single visible reflow, not the dozens
    // pinch-to-zoom used to produce.
    _fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    // Layout rationale — reflow-on-keyboard, stable-on-copy-mode.
    //
    // Two triggers could resize the terminal widget: soft-keyboard
    // open/close, and copy-mode toggle. Each one propagates into
    // `Terminal.buffer.resize`, and xterm's resize has visible
    // side effects. The compromise landing here:
    //
    //   - **Keyboard reflow is allowed.** When the soft keyboard
    //     opens, the terminal shrinks to the free area above the
    //     SSH bar (which floats flush against the keyboard top).
    //     xterm runs its rows-only resize path — popping empty
    //     trailing lines when the cursor is already at bottom,
    //     otherwise moving the cursor up — and the earlier rows
    //     become reachable via xterm's own scrollback gesture.
    //     The prior "translate + ClipRect + stable height"
    //     attempt avoided the resize but parked the top rows
    //     off-screen under the mobile-shell AppBar with NO way
    //     for the user to scroll them back into view (scrolling
    //     xterm moves the whole render, not the clip), which is
    //     worse than a clean reflow.
    //   - **Copy-mode toggle is stable.** `SshKeyboardBar` swaps
    //     its row content in-place between normal keys and the
    //     copy-mode variant (hint + Copy + Cancel) inside the
    //     same `itemHeightLg` Container. No widget in the column
    //     changes height on toggle, so `buffer.resize` does not
    //     fire when the user enters or leaves copy mode — that
    //     was the scrollback-corruption path.
    //
    // `MobileShell` already sets `resizeToAvoidBottomInset: false`
    // on the terminal page, so we own the keyboard layout here —
    // the Scaffold body stays at full height regardless of the
    // keyboard. The bar's `bottom` offset clamps to `navBarHeight`
    // (sits above the mobile-shell nav bar when the keyboard is
    // hidden) and follows the *settled* keyboard inset once the
    // animation has finished. `_appliedKeyboardInset` is updated
    // through the [_scheduleKeyboardInsetSettle] debouncer so we
    // don't re-layout (and re-resize xterm) on every animation
    // frame — per-frame resizes visibly rip the scrollback.
    //
    // Reading `MediaQuery.viewInsetsOf(context)` here is load-
    // bearing: it registers a dependency on MediaQuery so build
    // fires on every keyboard-animation tick, which both arms the
    // debouncer for terminal-side layout and lets the SSH bar
    // track the sliding keyboard in real time.
    //
    // Two separate `bottom` offsets come out of this split:
    //   * `_barBottomLive` follows the raw inset — the bar slides
    //     with the keyboard so the user sees a smooth motion
    //     rather than a post-animation snap.
    //   * `_terminalBottomSettled` uses the debounced
    //     `_appliedKeyboardInset` — the xterm-hosting `Positioned`
    //     keeps its size until the animation settles, so
    //     `Terminal.buffer.resize` fires exactly once per
    //     keyboard open / close. During the animation the terminal
    //     keeps its old rendered height; the bar paints on top of
    //     the lower rows, and those rows briefly tuck behind the
    //     bar + keyboard. No scrollback shuffle, no visual rip.
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
              onInput: _onKeyboardInput,
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
    // xterm's `TerminalView` paints whole cells only — its viewport
    // rounds the available height down to `floor(h / cellHeight)` rows
    // and leaves the remainder as a theme-coloured strip at the bottom
    // that the user reads as "dead terminal space" (the literal
    // complaint: *"он выглядит как терминал, но туда ничего не
    // выписывается"*). `LayoutBuilder` below snaps the widget's own
    // height to an integer-row multiple so the last rendered row sits
    // flush against the next widget in the Column; the few remaining
    // pixels between the snapped height and the parent's height become
    // a `ColoredBox` strip that visually belongs to the bottom control
    // strip instead of the terminal.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cell height mirrors xterm's painter: fontSize × the shared
        // `kTerminalLineHeight` multiplier. Padding is the same
        // `EdgeInsets.all(4)` we pass to TerminalView below.
        const verticalPadding = 8.0; // EdgeInsets.all(4).vertical
        final cellHeight = _fontSize * kTerminalLineHeight;
        final usable = constraints.maxHeight - verticalPadding;
        final rows = usable > 0 ? (usable / cellHeight).floor() : 0;
        final snappedHeight = rows > 0
            ? rows * cellHeight + verticalPadding
            : constraints.maxHeight;
        return Column(
          children: [
            SizedBox(height: snappedHeight, child: _buildTerminalListener()),
            if (snappedHeight < constraints.maxHeight)
              Expanded(
                child: ColoredBox(color: AppTheme.terminalTheme.background),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalListener() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Stack(
        children: [
          // Isolate xterm's internal gesture recognizers (drag-select,
          // scroll) while copy mode is active. xterm still sees
          // `setSuspendPointerInput(true)` which gates mouse-reporting
          // to the remote shell, but its LOCAL LongPressGestureRecognizer
          // + PanGestureRecognizer keep firing without this shield:
          // a single-finger drag in copy mode used to run both
          // `renderTerminal.selectCharacters` (xterm) *and*
          // `onCursorPan` (our overlay) on every frame, and the two
          // competing setSelection calls produced the duplicate-rows +
          // gaps artefacts users saw in scrollback. `AbsorbPointer`
          // blocks pointers from reaching TerminalView; the outer
          // Listener still observes them via its ancestor hit-test so
          // cursor-pan deltas keep flowing.
          AbsorbPointer(
            absorbing: _copyMode,
            child: TerminalView(
              _terminal,
              controller: _terminalController,
              scrollController: _terminalScrollController,
              autofocus: true,
              backgroundOpacity: 1.0,
              padding: const EdgeInsets.all(4),
              theme: AppTheme.terminalTheme,
              textStyle: TerminalStyle(
                fontSize: _fontSize,
                fontFamily: AppFonts.monoFamily,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
              // xterm's default is `TextInputType.emailAddress`, which
              // tells Gboard/iOS that the field holds an email — the
              // IME then surfaces email-specific helpers (the
              // clipboard/@-symbol pill, auto-suggest toolbars that
              // wouldn't dismiss with a tap on the terminal) that
              // users correctly interpreted as "random popups I
              // can't close". `TextInputType.text` removes the
              // email hint while still advertising a text field so
              // IMEs keep full cursor-gesture support; xterm's own
              // `CustomTextEdit` already disables autocorrect,
              // suggestions, and IME personalisation inside its
              // `TextInputConfiguration`, so the field stays
              // prediction-free regardless.
              keyboardType: TextInputType.text,
            ),
          ),
          Positioned.fill(
            child: CursorTextOverlay(terminal: _terminal, fontSize: _fontSize),
          ),
          if (_copyMode)
            Positioned.fill(
              child: TerminalCopyOverlay(
                key: _copyOverlayKey,
                terminal: _terminal,
                controller: _terminalController,
                scrollController: _terminalScrollController,
                fontSize: _fontSize,
                fontFamily: AppFonts.monoFamily,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
        ],
      ),
    );
  }
}
