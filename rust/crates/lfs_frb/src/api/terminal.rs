//! FRB adapter for `lfs_core::terminal` — the headless terminal engine
//! driven Rust-side off an SSH shell channel.
//!
//! The terminal loop lives entirely in Rust: a spawned tokio task
//! ([`TerminalSession::spawn_pump`]) reads shell output, feeds it into the
//! [`lfs_core::terminal::TerminalEngine`], drains the engine's side-effect
//! queue, and forwards every [`PtyWrite`](lfs_core::terminal::TerminalEvent::PtyWrite)
//! back to the shell **Rust→Rust** — the PtyWrite bytes (cursor-position
//! reports, DSR replies, bracketed-paste framing) never round-trip through
//! Dart, so interactive programs (vim focus/mouse probes, `tput`) keep
//! working even if the Dart isolate is busy painting. Dart only pulls
//! owned snapshots ([`TerminalFrame`]) and receives a coalesced wakeup /
//! bell / title / clipboard stream ([`TerminalUiEvent`]).
//!
//! Single shell-event consumer: the pump owns `shell.next_event()`. A given
//! shell is consumed by exactly one of `SshShell::events_stream` (the
//! non-terminal Dart path) or a `TerminalSession` — never both, or the two
//! readers deadlock on the shell's read-half mutex (see `api::ssh`).
//!
//! Architecture: see ARCHITECTURE.md §3.16 → "FRB bridge and the Rust-owned
//! pump".

use std::sync::Arc;

use flutter_rust_bridge::frb;
use tokio::sync::Mutex;

use lfs_core::terminal::{
    MatchRange, SelectionKind, TermPalette, TerminalEngine, TerminalEvent as CoreTerminalEvent,
};

use crate::api::frb_err;
use crate::api::ssh::SshSession;
use crate::frb_generated::StreamSink;

// ---- Palette DTO ------------------------------------------------------

/// FRB-friendly 24-bit color — three `u8` channels. Mirrors
/// `lfs_core::terminal::Rgb` without leaking the core type across the
/// boundary (the core `Rgb` lives in a module the bridge must not
/// re-export per the data-ownership pillar).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TerminalColor {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl TerminalColor {
    fn from_core(c: lfs_core::terminal::Rgb) -> Self {
        Self {
            r: c.r,
            g: c.g,
            b: c.b,
        }
    }

    fn into_core(self) -> lfs_core::terminal::Rgb {
        lfs_core::terminal::Rgb::new(self.r, self.g, self.b)
    }
}

/// FRB-friendly palette: the 16 ANSI base colors plus the default
/// foreground / background / cursor / selection swatches. Converts into
/// the core [`TermPalette`]; the 256-color cube is derived inside the
/// engine, so it is not carried here. The Dart theme layer fills this
/// from AppTheme in a later task.
#[derive(Debug, Clone)]
pub struct TerminalPalette {
    /// Indices 0..16 in NamedColor order: black, red, green, yellow,
    /// blue, magenta, cyan, white, then their eight bright variants.
    pub ansi: Vec<TerminalColor>,
    pub foreground: TerminalColor,
    pub background: TerminalColor,
    pub cursor: TerminalColor,
    pub selection: TerminalColor,
}

impl TerminalPalette {
    /// OneDark default — handed to `terminal_palette_default()` so the
    /// engine has a usable palette before the Dart theme layer pushes a
    /// real one. Mirrors `TermPalette::one_dark`.
    fn from_core(p: &TermPalette) -> Self {
        Self {
            ansi: p
                .ansi
                .iter()
                .map(|c| TerminalColor::from_core(*c))
                .collect(),
            foreground: TerminalColor::from_core(p.foreground),
            background: TerminalColor::from_core(p.background),
            cursor: TerminalColor::from_core(p.cursor),
            selection: TerminalColor::from_core(p.selection),
        }
    }

    /// Resolve into the core palette. A short ANSI vector is padded with
    /// the default foreground rather than rejected — a malformed palette
    /// from the theme layer degrades to readable colors instead of
    /// failing the whole terminal open.
    fn into_core(self) -> TermPalette {
        let mut ansi = [self.foreground.into_core(); 16];
        for (slot, color) in ansi.iter_mut().zip(self.ansi) {
            *slot = color.into_core();
        }
        TermPalette {
            ansi,
            foreground: self.foreground.into_core(),
            background: self.background.into_core(),
            cursor: self.cursor.into_core(),
            selection: self.selection.into_core(),
        }
    }
}

/// The OneDark default palette as a DTO. The Dart theme layer uses this
/// as the starting point before overriding swatches from AppTheme.
#[frb(sync)]
pub fn terminal_palette_default() -> TerminalPalette {
    TerminalPalette::from_core(&TermPalette::one_dark())
}

// ---- Frame DTO --------------------------------------------------------

/// Cursor rendering shape — FRB mirror of
/// `lfs_core::terminal::CursorShape`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalCursorShape {
    Block,
    Underline,
    Beam,
    HollowBlock,
    Hidden,
}

impl TerminalCursorShape {
    fn from_core(s: lfs_core::terminal::CursorShape) -> Self {
        use lfs_core::terminal::CursorShape as C;
        match s {
            C::Block => TerminalCursorShape::Block,
            C::Underline => TerminalCursorShape::Underline,
            C::Beam => TerminalCursorShape::Beam,
            C::HollowBlock => TerminalCursorShape::HollowBlock,
            C::Hidden => TerminalCursorShape::Hidden,
        }
    }
}

/// Cursor position + shape for one frame. `row` is in display-viewport
/// coordinates (`0` = top visible line).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TerminalCursor {
    pub row: i32,
    pub col: u32,
    pub shape: TerminalCursorShape,
    pub visible: bool,
}

/// One painted cell. `ch` is the primary character as a Unicode scalar
/// (`u32`) — FRB has no `char`, and the renderer re-materialises it with
/// `String.fromCharCode`. `fg`/`bg` are already resolved to concrete RGB
/// (INVERSE/DIM applied) so the renderer never resolves color. `flags`
/// is the raw `alacritty_terminal` attribute bitfield widened to `u32`
/// (the core type is `u16`; FRB marshals `u32` cleanly and the extra
/// bits stay zero).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TerminalCell {
    pub row: i32,
    pub col: u32,
    pub ch: u32,
    pub fg: TerminalColor,
    pub bg: TerminalColor,
    pub flags: u32,
}

/// Selection span for one frame, in viewport-row coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TerminalFrameSelection {
    pub start_row: i32,
    pub start_col: u32,
    pub end_row: i32,
    pub end_col: u32,
    pub is_block: bool,
}

/// Complete render state for one paint — FRB mirror of
/// `lfs_core::terminal::Frame`. The `cells` vector is sparse: blank
/// default cells are omitted, so the renderer clears to the background
/// once and overlays only the non-blank cells.
#[derive(Debug, Clone)]
pub struct TerminalFrame {
    pub cols: u32,
    pub rows: u32,
    pub cursor: TerminalCursor,
    /// How many lines the viewport is scrolled up into scrollback.
    /// `0` = the live screen is showing.
    pub display_offset: u32,
    /// Total scrollback lines available above the live screen.
    pub history_size: u32,
    pub cells: Vec<TerminalCell>,
    pub selection: Option<TerminalFrameSelection>,
}

impl TerminalFrame {
    fn from_core(frame: lfs_core::terminal::Frame) -> Self {
        let cells = frame
            .cells
            .iter()
            .map(|c| TerminalCell {
                row: c.row,
                col: c.col as u32,
                ch: c.ch as u32,
                fg: TerminalColor::from_core(c.fg),
                bg: TerminalColor::from_core(c.bg),
                flags: u32::from(c.flags),
            })
            .collect();
        let selection = frame.selection.map(|s| TerminalFrameSelection {
            start_row: s.start_row,
            start_col: s.start_col as u32,
            end_row: s.end_row,
            end_col: s.end_col as u32,
            is_block: s.is_block,
        });
        Self {
            cols: frame.cols as u32,
            rows: frame.rows as u32,
            cursor: TerminalCursor {
                row: frame.cursor.row,
                col: frame.cursor.col as u32,
                shape: TerminalCursorShape::from_core(frame.cursor.shape),
                visible: frame.cursor.visible,
            },
            display_offset: frame.display_offset as u32,
            history_size: frame.history_size as u32,
            cells,
            selection,
        }
    }
}

/// One search match — FRB mirror of `lfs_core::terminal::MatchRange`, in
/// absolute grid-line coordinates (negative line = scrollback).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TerminalMatch {
    pub line: i32,
    pub start_col: u32,
    pub end_col: u32,
}

impl TerminalMatch {
    fn from_core(m: MatchRange) -> Self {
        Self {
            line: m.line,
            start_col: m.start_col as u32,
            end_col: m.end_col as u32,
        }
    }
}

/// Selection geometry — FRB mirror of
/// `lfs_core::terminal::SelectionKind`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalSelectionKind {
    Simple,
    Block,
}

impl TerminalSelectionKind {
    fn into_core(self) -> SelectionKind {
        match self {
            TerminalSelectionKind::Simple => SelectionKind::Simple,
            TerminalSelectionKind::Block => SelectionKind::Block,
        }
    }
}

// ---- UI event stream --------------------------------------------------

/// A Dart-facing side effect from the pump. `PtyWrite` is intentionally
/// absent — those bytes are forwarded to the shell Rust-side and must not
/// reach Dart. `Wakeup` is the coalesced "grid changed, pull a fresh
/// snapshot" signal the pump emits after feeding each chunk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TerminalUiEvent {
    /// Grid content changed — the renderer should pull a fresh snapshot.
    /// Coalesced: one per fed chunk regardless of how many `Repaint`
    /// events the parser raised.
    Wakeup,
    /// The terminal bell (`\x07`) rang.
    Bell,
    /// The remote set the window/tab title (OSC 0/2).
    Title { title: String },
    /// The remote reset the title to its default.
    ResetTitle,
    /// The remote requested storing text in the system clipboard (OSC 52).
    ClipboardStore { text: String },
    /// The shell channel closed (remote `Eof` / exit). The pump task has
    /// ended; no further events or snapshots will change.
    Closed,
}

// ---- The session ------------------------------------------------------

/// A live headless terminal bound to one SSH shell. Owns the engine
/// behind a `tokio::sync::Mutex` (the async pump and the sync
/// snapshot/method calls both touch it) and a clone of the core `Shell`
/// the pump reads from and writes to.
///
/// Lock discipline: every method locks the engine briefly and releases
/// before any `await` — the pump locks, feeds, drains, releases, then
/// awaits the next shell event (and any `shell.write` for PtyWrite runs
/// after the engine lock is dropped). Holding the engine lock across an
/// `await` would deadlock the snapshot calls against the pump.
#[frb(opaque)]
pub struct TerminalSession {
    engine: Arc<Mutex<TerminalEngine>>,
    shell: Arc<lfs_core::ssh::Shell>,
}

/// Open a PTY-backed shell on `session`, build the engine, and return a
/// `TerminalSession` handle. The pump does NOT start here — the caller
/// then calls [`TerminalSession::events`] with a `StreamSink` to begin
/// pumping output. This is where Dart obtains a terminal for a connection.
///
/// Open-shape rationale: the function opens the shell itself rather than
/// taking an already-opened `SshShell`. The terminal must be the
/// **single** consumer of the shell's events (the read-half is a
/// single-reader mutex — two consumers deadlock), so coupling the open to
/// the session makes that ownership unambiguous: a `TerminalSession`
/// always owns the shell it pumps, and there is no window where a Dart
/// `events_stream` could have grabbed the same shell first. The
/// non-terminal `SshShell` / `events_stream` path stays untouched for
/// callers that do not want a terminal model.
///
/// Two-call shape (`open` returns the handle, `events` takes the sink):
/// FRB collapses any function carrying a `StreamSink` parameter into a
/// stream-returning function and drops its `Result` value, so the open
/// could not both return the handle and take the sink. Splitting them
/// also matches the `SshShell::events_stream` idiom — open the resource,
/// then subscribe.
pub async fn terminal_session_open(
    session: &SshSession,
    cols: u32,
    rows: u32,
    scrollback: u32,
    palette: TerminalPalette,
) -> Result<TerminalSession, String> {
    let shell = session.open_shell(cols, rows).await?;
    let shell = shell.into_arc();
    let engine = Arc::new(Mutex::new(TerminalEngine::new(
        cols.max(1) as usize,
        rows.max(1) as usize,
        scrollback as usize,
        palette.into_core(),
    )));
    Ok(TerminalSession { engine, shell })
}

impl TerminalSession {
    /// Start the Rust-owned shell→engine→shell pump and stream UI events to
    /// `sink`. Call exactly once per session — the pump is the single
    /// consumer of the shell's events; a second call would deadlock the two
    /// readers on the shell's read-half mutex. Returns when the shell closes
    /// (remote `Eof` / `next_event` returns `None`) or the Dart `sink`
    /// rejects an `add` (subscription cancelled).
    ///
    /// The pump reads shell output, locks the engine, feeds the bytes,
    /// drains the side-effect queue, releases the lock, then forwards every
    /// `PtyWrite` back to the shell Rust→Rust and pushes the translated
    /// UI events (coalesced `Wakeup`, bell, title, clipboard) to `sink`.
    ///
    /// Recorder / broadcast fork hook: when the live terminal pane moves to
    /// `TerminalSession`, the per-byte fork to the session recorder and the
    /// broadcast controller (today in Dart's `shell_helper.dart`) moves
    /// into the pump body, right after the output bytes are read and before
    /// they are fed into the engine. The loop is shaped so that hook slots
    /// in without reshaping the lock/await ordering.
    pub async fn events(&self, sink: StreamSink<TerminalUiEvent>) -> Result<(), String> {
        let engine = self.engine.clone();
        let shell = self.shell.clone();
        while let Some(event) = shell.next_event().await {
            let bytes = match event {
                lfs_core::ssh::ShellEvent::Output(b)
                | lfs_core::ssh::ShellEvent::ExtendedOutput(b) => b,
                lfs_core::ssh::ShellEvent::Eof => {
                    let _ = sink.add(TerminalUiEvent::Closed);
                    break;
                }
                // Exit status / signal do not touch the grid; the
                // channel-close `Eof` drives the `Closed` UI event.
                lfs_core::ssh::ShellEvent::ExitStatus(_)
                | lfs_core::ssh::ShellEvent::ExitSignal(_) => continue,
            };

            // Lock, feed, drain, then RELEASE before any write/await.
            // `pty_writes` is collected under the lock and flushed after —
            // never hold the engine lock across `shell.write`.
            let (pty_writes, ui_events) = {
                let mut guard = engine.lock().await;
                guard.feed(&bytes);
                partition_drained(guard.drain_events())
            };

            for chunk in pty_writes {
                // A failed write-back means the channel is going away; the
                // next `next_event` yields the close, which drives the
                // `Closed` UI event. Keep draining so the close surfaces
                // cleanly rather than spinning — the pump never gives up
                // early on a write. The error is logged (not raw bytes:
                // these are protocol reply frames — cursor-position / DSR
                // replies / bracketed-paste framing — so we record only the
                // length) before continuing.
                if let Err(e) = shell.write(&chunk).await {
                    // `lfs_core::app_log` is `pub(crate)`, so the internal
                    // log macros are unreachable here; emit the same
                    // sanitized `CoreLog` event through the public bus the
                    // Dart `AppLogger` already folds into `letsflutssh.log`.
                    lfs_core::app::instance()
                        .bus
                        .publish(lfs_core::bus::Event::CoreLog {
                            level: lfs_core::bus::CoreLogLevel::Warn,
                            name: "Terminal".to_string(),
                            message: pty_write_back_failed_line(chunk.len(), &e.to_string()),
                        });
                }
            }

            for ev in ui_events {
                if sink.add(ev).is_err() {
                    // Dart cancelled the subscription — stop pumping.
                    return Ok(());
                }
            }
        }
        Ok(())
    }

    /// Build an owned render snapshot of the current viewport. Sync so the
    /// renderer pulls a frame without an `await` per paint. Uses
    /// `blocking_lock` because the only writer is the pump, which holds the
    /// lock for a single non-awaiting feed/drain — contention is bounded
    /// and never crosses an `await`.
    #[frb(sync)]
    pub fn snapshot(&self) -> TerminalFrame {
        let guard = self.engine.blocking_lock();
        TerminalFrame::from_core(guard.snapshot())
    }

    /// Resize the viewport: the engine reflows the grid and the shell
    /// notifies the remote of the new window size. Both must happen — the
    /// engine for the local model, the `window_change` so the remote PTY
    /// (and any `SIGWINCH`-aware program) sees it.
    pub async fn resize(&self, cols: u32, rows: u32) -> Result<(), String> {
        {
            let mut guard = self.engine.lock().await;
            guard.resize(cols.max(1) as usize, rows.max(1) as usize);
        }
        self.shell
            .resize(cols, rows)
            .await
            .map_err(|e| frb_err::from_core(&e))
    }

    /// Scroll the viewport by `delta` lines (positive = up into
    /// scrollback, negative = back toward the live screen).
    pub async fn scroll(&self, delta: i32) {
        let mut guard = self.engine.lock().await;
        guard.scroll(delta);
    }

    /// Jump the viewport to the live screen (bottom).
    pub async fn scroll_to_bottom(&self) {
        let mut guard = self.engine.lock().await;
        guard.scroll_to_bottom();
    }

    /// Forward Dart key bytes straight to the remote shell's stdin. The
    /// engine processes only **server output**, never local input — so
    /// input bypasses the engine entirely (the server echoes it back, and
    /// that echo is what the engine renders). Key-byte encoding is a later
    /// task; this just forwards the already-encoded bytes.
    pub async fn write_input(&self, bytes: Vec<u8>) -> Result<(), String> {
        self.shell
            .write(&bytes)
            .await
            .map_err(|e| frb_err::from_core(&e))
    }

    /// Set a selection spanning `start` to `end` in absolute grid
    /// coordinates (negative row = scrollback). Read the covered text back
    /// with [`Self::selection_text`].
    pub async fn set_selection(
        &self,
        start_row: i32,
        start_col: u32,
        end_row: i32,
        end_col: u32,
        kind: TerminalSelectionKind,
    ) {
        let mut guard = self.engine.lock().await;
        guard.set_selection(
            (start_row, start_col as usize),
            (end_row, end_col as usize),
            kind.into_core(),
        );
    }

    /// Clear any active selection.
    pub async fn clear_selection(&self) {
        let mut guard = self.engine.lock().await;
        guard.clear_selection();
    }

    /// The text covered by the active selection, or `None` when there is
    /// no selection.
    pub async fn selection_text(&self) -> Option<String> {
        let guard = self.engine.lock().await;
        guard.selection_text()
    }

    /// Scan the grid + scrollback for every literal occurrence of `query`.
    /// Returns matches in absolute grid-line coordinates.
    pub async fn search(&self, query: String) -> Vec<TerminalMatch> {
        let guard = self.engine.lock().await;
        guard
            .search(&query)
            .into_iter()
            .map(TerminalMatch::from_core)
            .collect()
    }

    /// Replace the color palette (e.g. on theme change). Takes effect on
    /// the next snapshot; already-parsed cells keep their abstract colors
    /// and re-resolve against the new palette.
    pub async fn set_palette(&self, palette: TerminalPalette) {
        let mut guard = self.engine.lock().await;
        guard.set_palette(palette.into_core());
    }
}

/// Split drained engine events into the bytes to write back to the PTY and
/// the Dart-facing UI events. `Repaint` (and any non-PtyWrite mutation)
/// collapses into a single coalesced `Wakeup` so the renderer pulls one
/// fresh snapshot per fed chunk rather than once per parser event.
///
/// Factored out as a pure function so the PtyWrite-forwarding + event
/// translation can be unit-tested without a live shell.
fn partition_drained(events: Vec<CoreTerminalEvent>) -> (Vec<Vec<u8>>, Vec<TerminalUiEvent>) {
    let mut pty_writes = Vec::new();
    let mut ui_events = Vec::new();
    for event in events {
        match event {
            CoreTerminalEvent::PtyWrite(bytes) => pty_writes.push(bytes),
            // Repaint collapses into the single coalesced Wakeup pushed
            // below — one snapshot pull per fed chunk, not per event.
            CoreTerminalEvent::Repaint => {}
            CoreTerminalEvent::Bell => ui_events.push(TerminalUiEvent::Bell),
            CoreTerminalEvent::Title(title) => ui_events.push(TerminalUiEvent::Title { title }),
            CoreTerminalEvent::ResetTitle => ui_events.push(TerminalUiEvent::ResetTitle),
            CoreTerminalEvent::ClipboardStore(text) => {
                ui_events.push(TerminalUiEvent::ClipboardStore { text })
            }
        }
    }
    // Feeding a chunk always changed the grid even when the parser did not
    // raise an explicit Repaint (e.g. a pure `Print` run) — emit one
    // wakeup so the renderer never misses content. Placed last so the
    // renderer applies title/bell side effects against the new snapshot.
    ui_events.push(TerminalUiEvent::Wakeup);
    (pty_writes, ui_events)
}

/// Build the log line for a failed PtyWrite write-back. The dropped
/// chunk is a protocol reply frame (cursor-position / DSR reply /
/// bracketed-paste framing), so the line carries only the byte length
/// and the error string — never the payload bytes themselves. Runs the
/// same two-pass sanitise the `lfs_core::app_log` publisher applies
/// (secrets first, then PII): the bus does not re-sanitize, so the
/// publisher owns it. Pure so the no-raw-bytes contract is
/// unit-testable without a live shell.
fn pty_write_back_failed_line(len: usize, error: &str) -> String {
    let raw = format!("PtyWrite reply write-back to shell failed ({len} bytes dropped): {error}");
    lfs_core::log_sanitize::sanitize_error_message(&lfs_core::log_sanitize::redact_secrets(&raw))
}

#[cfg(test)]
mod tests {
    use super::*;

    // The live pump against a real shell needs a russh peer — it is an
    // external-system integration edge (covered by the connection
    // lifecycle integration binary once the Dart renderer lands). The
    // tests below pin the pure, harness-testable slices: the
    // Frame→TerminalFrame DTO mirror, the palette round-trip, and the
    // PtyWrite-forwarding / event-translation in `partition_drained`.

    #[test]
    fn palette_round_trips_through_core() {
        // Spec: a DTO built from a core palette must convert back into an
        // identical core palette — the bridge must not drop or reorder
        // swatches.
        let core = TermPalette::one_dark();
        let dto = TerminalPalette::from_core(&core);
        let back = dto.into_core();
        assert_eq!(back.ansi, core.ansi);
        assert_eq!(back.foreground, core.foreground);
        assert_eq!(back.background, core.background);
        assert_eq!(back.cursor, core.cursor);
        assert_eq!(back.selection, core.selection);
    }

    #[test]
    fn palette_default_exposes_one_dark() {
        // Spec: the FRB default palette is the core OneDark palette, so the
        // engine renders in theme colors before the Dart theme layer pushes
        // anything.
        let dto = terminal_palette_default();
        let core = TermPalette::one_dark();
        assert_eq!(dto.into_core().background, core.background);
    }

    #[test]
    fn palette_short_ansi_pads_with_foreground() {
        // Spec: a malformed (too-short) ANSI vector degrades to readable
        // colors rather than failing — missing slots fall back to the
        // default foreground, not to uninitialised / black.
        let fg = TerminalColor { r: 1, g: 2, b: 3 };
        let dto = TerminalPalette {
            ansi: vec![TerminalColor { r: 9, g: 9, b: 9 }],
            foreground: fg,
            background: TerminalColor { r: 0, g: 0, b: 0 },
            cursor: TerminalColor { r: 0, g: 0, b: 0 },
            selection: TerminalColor { r: 0, g: 0, b: 0 },
        };
        let core = dto.into_core();
        assert_eq!(core.ansi[0], lfs_core::terminal::Rgb::new(9, 9, 9));
        // Slot 1..16 fall back to the foreground swatch.
        assert_eq!(core.ansi[1], fg.into_core());
        assert_eq!(core.ansi[15], fg.into_core());
    }

    #[test]
    fn frame_dto_mirrors_engine_snapshot() {
        // Spec: feed known bytes, snapshot the engine, and assert the FRB
        // DTO mirrors the core Frame cell-for-cell — char as a scalar, the
        // cursor advanced past the printed text, the right geometry.
        let mut engine = TerminalEngine::new(20, 5, 100, TermPalette::one_dark());
        engine.feed(b"Hi");
        let core = engine.snapshot();
        let dto = TerminalFrame::from_core(core.clone());

        assert_eq!(dto.cols, core.cols as u32);
        assert_eq!(dto.rows, core.rows as u32);
        assert_eq!(dto.cells.len(), core.cells.len());
        // The two printed glyphs survive as scalars.
        let chars: Vec<char> = dto
            .cells
            .iter()
            .map(|c| char::from_u32(c.ch).expect("valid scalar"))
            .collect();
        assert!(chars.contains(&'H'));
        assert!(chars.contains(&'i'));
        // Cursor advanced two columns past the start.
        assert_eq!(dto.cursor.col, core.cursor.col as u32);
        assert_eq!(dto.cursor.row, core.cursor.row);
    }

    #[test]
    fn frame_dto_carries_selection() {
        // Spec: a set selection surfaces in the DTO with mirrored
        // coordinates and block flag.
        let mut engine = TerminalEngine::new(10, 3, 50, TermPalette::one_dark());
        engine.feed(b"hello");
        engine.set_selection((0, 0), (0, 4), SelectionKind::Simple);
        let dto = TerminalFrame::from_core(engine.snapshot());
        let sel = dto.selection.expect("selection present");
        assert_eq!(sel.start_row, 0);
        assert_eq!(sel.start_col, 0);
        assert!(!sel.is_block);
    }

    #[test]
    fn partition_drained_forwards_pty_writes_in_order() {
        // Spec: PtyWrite bytes are the cursor-report / DSR replies that
        // MUST reach the server; they must be extracted in arrival order
        // and never leak into the Dart UI event stream.
        let events = vec![
            CoreTerminalEvent::PtyWrite(b"\x1b[1;1R".to_vec()),
            CoreTerminalEvent::Repaint,
            CoreTerminalEvent::PtyWrite(b"\x1b[?1;2c".to_vec()),
        ];
        let (writes, ui) = partition_drained(events);
        assert_eq!(writes, vec![b"\x1b[1;1R".to_vec(), b"\x1b[?1;2c".to_vec()]);
        // No PtyWrite leaked into the UI stream.
        assert!(!ui.iter().any(|e| matches!(e, TerminalUiEvent::Bell)));
    }

    #[test]
    fn partition_drained_always_emits_one_wakeup() {
        // Spec: every fed chunk produced grid changes, so the pump must
        // emit exactly one coalesced Wakeup — even when the parser raised
        // no explicit Repaint, and never more than one however many
        // Repaints it raised.
        let none = partition_drained(Vec::new()).1;
        assert_eq!(
            none.iter()
                .filter(|e| matches!(e, TerminalUiEvent::Wakeup))
                .count(),
            1,
        );
        let many = partition_drained(vec![
            CoreTerminalEvent::Repaint,
            CoreTerminalEvent::Repaint,
            CoreTerminalEvent::Repaint,
        ])
        .1;
        assert_eq!(
            many.iter()
                .filter(|e| matches!(e, TerminalUiEvent::Wakeup))
                .count(),
            1,
        );
    }

    #[test]
    fn partition_drained_translates_each_ui_event() {
        // Spec: Bell / Title / ResetTitle / ClipboardStore each map to
        // their Dart-facing variant carrying the same payload.
        let events = vec![
            CoreTerminalEvent::Bell,
            CoreTerminalEvent::Title("vim".into()),
            CoreTerminalEvent::ResetTitle,
            CoreTerminalEvent::ClipboardStore("copied".into()),
        ];
        let (_writes, ui) = partition_drained(events);
        assert!(ui.contains(&TerminalUiEvent::Bell));
        assert!(ui.contains(&TerminalUiEvent::Title {
            title: "vim".into()
        }));
        assert!(ui.contains(&TerminalUiEvent::ResetTitle));
        assert!(ui.contains(&TerminalUiEvent::ClipboardStore {
            text: "copied".into()
        }));
    }

    #[test]
    fn terminal_match_mirrors_core_range() {
        // Spec: search-match coordinates survive the boundary as-is.
        let core = MatchRange {
            line: -3,
            start_col: 4,
            end_col: 9,
        };
        let dto = TerminalMatch::from_core(core);
        assert_eq!(dto.line, -3);
        assert_eq!(dto.start_col, 4);
        assert_eq!(dto.end_col, 9);
    }

    #[test]
    fn pty_write_back_failed_line_omits_raw_bytes() {
        // Spec: the dropped chunk is a protocol reply frame, so the log
        // line must carry the length + error string but never the payload
        // bytes. Pin both: the length and error are present, and the raw
        // byte values are absent.
        let raw_bytes = [0x1B, 0x5B, 0x36, 0x6E]; // ESC [ 6 n — a DSR reply
        let line = pty_write_back_failed_line(raw_bytes.len(), "channel closed");
        assert!(line.contains("4 bytes"), "length must be reported: {line}");
        assert!(
            line.contains("channel closed"),
            "error must be reported: {line}"
        );
        // The escape-sequence bytes must not leak into the line.
        assert!(
            !line.contains('\u{1B}'),
            "raw payload byte leaked into log line: {line:?}"
        );
        assert!(
            !line.contains("[6n"),
            "raw payload leaked into log line: {line:?}"
        );
    }

    #[test]
    fn cursor_shape_maps_each_variant() {
        use lfs_core::terminal::CursorShape as C;
        for core in [C::Block, C::Underline, C::Beam, C::HollowBlock, C::Hidden] {
            // Exhaustive match pins the mapping so a new core variant
            // forces a compile error here.
            match TerminalCursorShape::from_core(core) {
                TerminalCursorShape::Block
                | TerminalCursorShape::Underline
                | TerminalCursorShape::Beam
                | TerminalCursorShape::HollowBlock
                | TerminalCursorShape::Hidden => (),
            }
        }
    }
}
