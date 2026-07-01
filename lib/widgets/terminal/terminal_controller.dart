import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/terminal.dart';
import 'terminal_palette_theme.dart';

/// The terminal operations a [TerminalView] needs, expressed once so a single
/// view renders both the live SSH shell and the read-only replay surfaces.
///
/// The two backing engines are FRB opaque types (`TerminalSession`,
/// `TerminalReplay`) that cannot implement a Dart interface directly, so each
/// is wrapped by a concrete adapter: [LiveTerminalController] over the live
/// session and [ReplayTerminalController] over the shell-less replay. The
/// adapter pattern also pins the data-ownership rule — the grid is Rust-owned;
/// a controller pulls a fresh [snapshot] each repaint and never caches frame
/// data Dart-side.
///
/// Capabilities the read-only surfaces do not support (input, mouse reporting,
/// paste, search) are absent on the replay adapter; [TerminalView] gates each
/// feature behind a [TerminalViewConfig] flag and the host wires only the
/// callbacks the config enables, so an unsupported call is never reached.
abstract class TerminalController {
  /// Pull the current viewport snapshot. Always re-read from Rust — the engine
  /// owns the grid; this is called on every repaint.
  TerminalFrame snapshot();

  /// Repaint signal the view listens to. Bumped after each host-driven feed /
  /// clear / resize / selection change and, on the live adapter, after each
  /// engine `Wakeup`. Present on every controller.
  Listenable get repaint;

  /// Stream of out-of-band UI events (title / bell / reset-title / clipboard
  /// store / closed). Live-only — `null` on the replay adapter, which raises
  /// none of these.
  Stream<TerminalUiEvent>? get uiEvents;

  /// Resize the engine grid. Present on every controller.
  void resize(int cols, int rows);

  /// Set a selection in absolute grid-line coordinates (negative row =
  /// scrollback). Returns once the engine applied it so the view can pull a
  /// fresh snapshot — neither engine raises a `Wakeup` for a host-driven
  /// selection, so the highlight would not paint without the pull.
  Future<void> setSelection(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  );

  /// Clear any active selection.
  void clearSelection();

  /// The text covered by the active selection, or null when nothing is
  /// selected. Read straight from the engine — never cached Dart-side.
  Future<String?> selectionText();

  // ── Live-only capabilities ───────────────────────────────────────────────
  // Default to no-op / absent so the read-only adapter does not implement
  // them; [TerminalView] only invokes these when its config enables the
  // matching feature, which is only ever paired with a live controller.

  /// Whether this controller backs an interactive session (live shell). Drives
  /// nothing on its own — [TerminalView] reads it only to assert the config
  /// matches the controller's capabilities in debug builds.
  bool get isLive => false;

  /// Scroll the viewport by whole lines (positive = up into scrollback).
  /// No-op on the replay adapter — the read-only surfaces feed bytes and do
  /// not wheel-scroll a viewport.
  void scroll(int delta) {}

  /// Encode a key against the live terminal mode and write it to the shell.
  /// No-op on the replay adapter.
  void sendKey(TerminalKey key) {}

  /// Encode and write pasted text to the shell. No-op on the replay adapter.
  Future<void> paste(String text) async {}

  /// Write raw bytes straight to the shell stdin. No-op on the replay adapter.
  void writeInput(List<int> bytes) {}

  /// Encode a mouse report against the live mode and write it to the shell.
  /// No-op on the replay adapter.
  void sendMouse(TerminalMouseInput event) {}

  /// Scan the grid + scrollback for `query`. Returns an empty list on the
  /// replay adapter, which exposes no search.
  Future<List<TerminalMatch>> search(String query) async => const [];
}

/// [TerminalController] over a live, Rust-owned [TerminalSession].
///
/// `events()` is subscribed exactly once in the constructor and bridged into
/// two surfaces: every `Wakeup` bumps [repaint] (the view pulls a fresh
/// snapshot per frame), and every other event flows out on [uiEvents] for the
/// host's title / bell / clipboard / closed handlers. Subscribing once is the
/// invariant the prior live grid carried — calling `session.events()` per
/// rebuild would mint a fresh FRB stream each time and drop pump wakeups while
/// posting to torn-down sinks ("Fail to post message to Dart" spam).
class LiveTerminalController extends TerminalController {
  LiveTerminalController(this._session) {
    _sub = _session.events().listen(
      _onEvent,
      onDone: () {
        // Surface the shell-closed edge on the UI-event stream so the host's
        // onClosed handler fires on a plain stream-done as well as an explicit
        // Closed event.
        if (!_uiEvents.isClosed) {
          _uiEvents.add(const TerminalUiEvent.closed());
        }
      },
    );
  }

  final TerminalSession _session;
  late final StreamSubscription<TerminalUiEvent> _sub;
  final _repaint = _RepaintNotifier();
  final _uiEvents = StreamController<TerminalUiEvent>.broadcast();
  bool _disposed = false;

  // `setSelection` / `clearSelection` notify the repaint signal from a
  // `.then` callback that can resolve after the pane closes and
  // [dispose] ran — `notifyListeners` on a disposed ChangeNotifier
  // throws. Gate every notify on the disposed flag.
  void _notifyRepaint() {
    if (_disposed) return;
    _repaint.notify();
  }

  /// The wrapped session, exposed so the host can drive the lifecycle calls
  /// the controller intentionally does not own (dispose, set_recorder).
  TerminalSession get session => _session;

  void _onEvent(TerminalUiEvent event) {
    if (event is TerminalUiEvent_Wakeup) {
      _notifyRepaint();
      return;
    }
    if (!_uiEvents.isClosed) _uiEvents.add(event);
  }

  @override
  bool get isLive => true;

  @override
  TerminalFrame snapshot() => _session.snapshot();

  @override
  Listenable get repaint => _repaint;

  @override
  Stream<TerminalUiEvent> get uiEvents => _uiEvents.stream;

  @override
  void resize(int cols, int rows) =>
      unawaited(_session.resize(cols: cols, rows: rows));

  @override
  void scroll(int delta) =>
      unawaited(_session.scroll(delta: delta).then((_) => _notifyRepaint()));

  // The engine raises no Wakeup for a host-driven selection change, so the
  // controller pulses `repaint` once the change lands — that way every caller
  // (the view's drag, the pane's copy-then-clear, Select All) repaints the
  // highlight through the same signal, with no per-caller frame pull.
  @override
  Future<void> setSelection(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  ) => _session
      .setSelection(
        startRow: startRow,
        startCol: startCol,
        endRow: endRow,
        endCol: endCol,
        kind: kind,
      )
      .then((_) => _notifyRepaint());

  @override
  void clearSelection() =>
      unawaited(_session.clearSelection().then((_) => _notifyRepaint()));

  @override
  Future<String?> selectionText() => _session.selectionText();

  @override
  void sendKey(TerminalKey key) => unawaited(_session.sendKey(key: key));

  @override
  Future<void> paste(String text) => _session.paste(text: text);

  @override
  void writeInput(List<int> bytes) =>
      unawaited(_session.writeInput(bytes: bytes));

  @override
  void sendMouse(TerminalMouseInput event) =>
      unawaited(_session.sendMouse(event: event));

  @override
  Future<List<TerminalMatch>> search(String query) =>
      _session.search(query: query);

  /// Release the event subscription and the bridge surfaces. The wrapped
  /// session is NOT disposed here — its lifecycle (and any attached recorder)
  /// is the host's, which may outlive a controller swap. Dispose the session
  /// separately.
  void dispose() {
    _disposed = true;
    unawaited(_sub.cancel());
    unawaited(_uiEvents.close());
    _repaint.dispose();
  }
}

/// [TerminalController] over a shell-less [TerminalReplay] for read-only
/// surfaces: feed bytes, pull a snapshot, repaint. No SSH shell, no pump, no
/// input — the feeder (progress writer, recording scrub loop, log viewer)
/// pushes bytes through [feed] and the [TerminalView] listening to [repaint]
/// re-pulls a snapshot.
///
/// Widget-local repaint state, so this is itself a [ChangeNotifier] (the grid
/// is Rust-owned; the controller holds only the repaint signal). Capabilities
/// the read-only surfaces do not need (input, mouse, paste, search) inherit
/// the base no-ops, and [uiEvents] is null — the replay raises none.
class ReplayTerminalController extends TerminalController with ChangeNotifier {
  ReplayTerminalController({
    required int cols,
    required int rows,
    int scrollback = 10000,
    TerminalPalette? palette,
  }) : _replay = terminalReplayOpen(
         cols: cols,
         rows: rows,
         scrollback: scrollback,
         palette: palette ?? TerminalPaletteFromTheme.fromAppTheme(),
       ),
       _cols = cols,
       _rows = rows;

  final TerminalReplay _replay;
  int _cols;
  int _rows;

  /// Current grid width in columns — the wrap width feeders (the log viewer)
  /// format against. Tracks [resize].
  int get cols => _cols;

  /// Current grid height in rows.
  int get rows => _rows;

  @override
  TerminalFrame snapshot() => _replay.snapshot();

  @override
  Listenable get repaint => this;

  @override
  Stream<TerminalUiEvent>? get uiEvents => null;

  /// Feed bytes (UTF-8 / ANSI) into the engine and schedule a repaint. The
  /// engine drops any `PtyWrite` reply (no shell) — see `TerminalReplay`.
  void feed(List<int> bytes) {
    _replay.feed(bytes: bytes);
    notifyListeners();
  }

  /// Wipe the grid + scrollback and repaint. Used by the recording scrub path
  /// before re-feeding from `t=0`.
  void clear() {
    _replay.clear();
    notifyListeners();
  }

  @override
  void resize(int cols, int rows) {
    if (cols == _cols && rows == _rows) return;
    _cols = cols;
    _rows = rows;
    _replay.resize(cols: cols, rows: rows);
    notifyListeners();
  }

  /// Re-theme the terminal (brightness flip). Re-resolves cell colors on the
  /// next snapshot.
  void setPalette(TerminalPalette palette) {
    _replay.setPalette(palette: palette);
    notifyListeners();
  }

  @override
  Future<void> setSelection(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  ) async {
    _replay.setSelection(
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
      kind: kind,
    );
    notifyListeners();
  }

  @override
  void clearSelection() {
    _replay.clearSelection();
    notifyListeners();
  }

  @override
  Future<String?> selectionText() async => _replay.selectionText();

  @override
  void dispose() {
    // Release the Rust-side replay engine deterministically instead of
    // leaving the opaque handle to the FRB finalizer; the host calls
    // this from its `State.dispose`.
    _replay.dispose();
    super.dispose();
  }
}

/// A [ChangeNotifier] whose notify is public, so [LiveTerminalController] can
/// bump the repaint signal from its `events()` bridge (a plain `ChangeNotifier`
/// guards `notifyListeners` to subclass instance members).
class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
