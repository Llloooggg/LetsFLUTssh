//! Headless terminal-emulation core.
//!
//! Rust owns the terminal grammar — ANSI parser, grid, scrollback,
//! scroll-region, and selection — per the project pillar "Rust owns data
//! AND logic; Flutter renders". The engine wraps
//! [`alacritty_terminal`] (the battle-tested model behind Alacritty) and
//! exposes only owned snapshots ([`Frame`]) and a drained event queue.
//! No `flutter_rust_bridge`, no FRB types: the bridge is a later task.
//!
//! Why this exists: the previous renderer used the unmaintained `xterm`
//! Dart package, whose buffer corrupts on scroll-region operations
//! (vim line-delete leaves stray horizontal stripes — upstream issue
//! #222). Moving the model into a maintained Rust engine fixes that class
//! of bug and satisfies the data-ownership pillar in one step.
//!
//! Architecture: see ARCHITECTURE.md → "Rust terminal engine".

mod frame;
mod input;
mod palette;

pub use frame::{Cell, CursorShape, Frame, FrameCursor, FrameSelection};
pub use input::{encode_key, encode_paste, KeyInput, KeyName};
pub use palette::{Rgb, TermPalette};

use std::sync::{Arc, Mutex};

use alacritty_terminal::event::{Event as AlacrittyEvent, EventListener};
use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::index::{Column, Line, Point, Side};
use alacritty_terminal::selection::{Selection, SelectionType};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::{Config, Term, TermMode};
use alacritty_terminal::vte::ansi::{CursorShape as VteCursorShape, Processor};

/// A side-effect the terminal emitted while parsing a byte stream. These
/// are surfaced to the caller via [`TerminalEngine::drain_events`] so the
/// later FRB/SSH layer can act on them — most importantly forwarding
/// [`TerminalEvent::PtyWrite`] back to the SSH channel.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TerminalEvent {
    /// Bytes the terminal wants written back to the PTY (cursor-position
    /// reports, device-status replies, bracketed-paste framing). The
    /// caller MUST forward these to the remote shell or interactive
    /// programs (vim's mouse/focus probes, `tput`) will misbehave.
    PtyWrite(Vec<u8>),
    /// The terminal bell (`\x07`) rang.
    Bell,
    /// The remote set the window/tab title (OSC 0/2).
    Title(String),
    /// The remote reset the title to its default.
    ResetTitle,
    /// Grid content changed — the renderer should repaint.
    Repaint,
    /// The remote requested storing text in the system clipboard (OSC 52).
    ClipboardStore(String),
}

/// `EventListener` sink. `send_event` takes `&self`, so the queue lives
/// behind a `Mutex` for interior mutability. The engine keeps a cloned
/// `Arc` handle to the same queue because `Term` exposes no accessor back
/// to the proxy it was constructed with. Events we do not model
/// (mouse-cursor-shape hints, color requests, exit) are dropped.
#[derive(Clone, Default)]
struct Proxy {
    events: Arc<Mutex<Vec<TerminalEvent>>>,
}

impl Proxy {
    fn drain(&self) -> Vec<TerminalEvent> {
        let mut guard = self.events.lock().expect("terminal event queue poisoned");
        std::mem::take(&mut *guard)
    }
}

impl EventListener for Proxy {
    fn send_event(&self, event: AlacrittyEvent) {
        let mapped = match event {
            AlacrittyEvent::PtyWrite(s) => Some(TerminalEvent::PtyWrite(s.into_bytes())),
            AlacrittyEvent::Bell => Some(TerminalEvent::Bell),
            AlacrittyEvent::Title(t) => Some(TerminalEvent::Title(t)),
            AlacrittyEvent::ResetTitle => Some(TerminalEvent::ResetTitle),
            AlacrittyEvent::ClipboardStore(_, text) => Some(TerminalEvent::ClipboardStore(text)),
            AlacrittyEvent::Wakeup | AlacrittyEvent::MouseCursorDirty => {
                Some(TerminalEvent::Repaint)
            }
            // ClipboardLoad / ColorRequest / TextAreaSizeRequest carry
            // reply closures we cannot answer headlessly; the live SSH
            // layer will own those once it wires the PTY. CursorBlinking /
            // Exit / ChildExit are not part of the render model.
            _ => None,
        };
        if let Some(ev) = mapped {
            self.events
                .lock()
                .expect("terminal event queue poisoned")
                .push(ev);
        }
    }
}

/// Implements `alacritty_terminal::grid::Dimensions` so `Term::new` and
/// `Term::resize` can read the geometry. `total_lines` includes scrollback
/// so the grid allocates history.
struct Sizer {
    cols: usize,
    rows: usize,
    scrollback: usize,
}

impl Dimensions for Sizer {
    fn total_lines(&self) -> usize {
        self.rows + self.scrollback
    }

    fn screen_lines(&self) -> usize {
        self.rows
    }

    fn columns(&self) -> usize {
        self.cols
    }
}

/// Which selection geometry to build.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionKind {
    /// Linear selection — flows column-by-column, row-by-row.
    Simple,
    /// Rectangular (block) selection.
    Block,
}

/// One substring match found by [`TerminalEngine::search`], in absolute
/// grid-line coordinates (negative = scrollback, `0..rows` = live screen).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MatchRange {
    pub line: i32,
    pub start_col: usize,
    pub end_col: usize,
}

/// The headless terminal. Owns the parser, the model, and the resolved
/// color palette. Single-threaded use: `feed` parses bytes into the grid,
/// `snapshot` produces an owned [`Frame`], `drain_events` collects side
/// effects.
pub struct TerminalEngine {
    term: Term<Proxy>,
    parser: Processor,
    palette: TermPalette,
    events: Proxy,
    cols: usize,
    rows: usize,
    scrollback: usize,
}

impl TerminalEngine {
    /// Build an engine for a `cols x rows` viewport with `scrollback`
    /// lines of history and the given color palette.
    pub fn new(cols: usize, rows: usize, scrollback: usize, palette: TermPalette) -> Self {
        let cols = cols.max(1);
        let rows = rows.max(1);
        let sizer = Sizer {
            cols,
            rows,
            scrollback,
        };
        let config = Config {
            scrolling_history: scrollback,
            ..Config::default()
        };
        let events = Proxy::default();
        let term = Term::new(config, &sizer, events.clone());
        Self {
            term,
            parser: Processor::new(),
            palette,
            events,
            cols,
            rows,
            scrollback,
        }
    }

    /// Parse a chunk of remote output into the grid. Replies the terminal
    /// generates (cursor reports, etc.) land in the event queue as
    /// [`TerminalEvent::PtyWrite`].
    pub fn feed(&mut self, bytes: &[u8]) {
        self.parser.advance(&mut self.term, bytes);
    }

    /// The terminal's current mode bitfield (DECCKM application-cursor,
    /// bracketed-paste, LNM, etc.). The key encoder reads it so a
    /// keystroke's bytes match what the running program set up — e.g.
    /// arrows flip to SS3 form under [`TermMode::APP_CURSOR`]. Returned by
    /// value (`TermMode` is `Copy`) so callers don't borrow the engine
    /// across the `encode_key` call.
    pub fn mode(&self) -> TermMode {
        *self.term.mode()
    }

    /// Resize the viewport. Content reflows per alacritty's rules and the
    /// cursor is clamped into bounds by the engine.
    pub fn resize(&mut self, cols: usize, rows: usize) {
        self.cols = cols.max(1);
        self.rows = rows.max(1);
        let sizer = Sizer {
            cols: self.cols,
            rows: self.rows,
            scrollback: self.scrollback,
        };
        self.term.resize(sizer);
    }

    /// Scroll the viewport by `delta` lines: positive scrolls up into
    /// scrollback, negative scrolls back down toward the live screen.
    pub fn scroll(&mut self, delta: i32) {
        self.term.scroll_display(Scroll::Delta(delta));
    }

    /// Jump the viewport to the live screen (bottom) or the oldest
    /// scrollback line (top).
    pub fn scroll_to_bottom(&mut self) {
        self.term.scroll_display(Scroll::Bottom);
    }

    /// Wipe the terminal: blank the visible grid, purge the entire
    /// scrollback history, and home the cursor. Unlike [`Self::scroll`] /
    /// [`Self::scroll_to_bottom`] (which only move the viewport over
    /// retained content), this drops the buffered output so nothing
    /// survives in memory — the auto-lock / wipe scrub path calls it when
    /// the DB key is cleared so sensitive command output cannot be read
    /// back from scrollback.
    ///
    /// `Grid::reset` does all three in one pass: `clear_history` shrinks
    /// the history rows to zero (so `history_size() == 0`), the cursor and
    /// display offset reset to the origin, and every visible line is reset
    /// to a blank template cell.
    pub fn clear(&mut self) {
        self.term.grid_mut().reset();
    }

    /// Replace the color palette (e.g. on theme change). Affects the next
    /// snapshot; already-parsed cells keep their abstract colors and
    /// re-resolve against the new palette.
    pub fn set_palette(&mut self, palette: TermPalette) {
        self.palette = palette;
    }

    /// Collect and clear the queued side effects since the last drain.
    pub fn drain_events(&mut self) -> Vec<TerminalEvent> {
        self.events.drain()
    }

    /// Build an owned render snapshot of the current viewport. Borrows
    /// `Term` only for the duration of this call.
    pub fn snapshot(&self) -> Frame {
        let content = self.term.renderable_content();
        let display_offset = content.display_offset;
        let cursor_point = content.cursor.point;
        let cursor_shape = map_cursor_shape(content.cursor.shape);

        let mut cells = Vec::new();
        for indexed in content.display_iter {
            let cell = indexed.cell;
            let flags = cell.flags;
            // The trailing half of a wide character is a spacer with no
            // glyph; the renderer paints the wide char across two columns
            // from the leading cell, so skip the spacer.
            if flags.contains(Flags::WIDE_CHAR_SPACER) {
                continue;
            }
            // Blank default cells are omitted — the renderer clears to the
            // background and overlays only non-blank cells.
            if cell.c == ' ' && !flags.contains(Flags::INVERSE) {
                continue;
            }

            let (fg, bg) = self.resolve_colors(cell.fg, cell.bg, flags);
            // Viewport row: the iterator yields native lines where 0 is the
            // top of the live screen; the visible top accounts for the
            // scroll offset so row 0 is always the topmost painted line.
            let row = indexed.point.line.0 + display_offset as i32;
            cells.push(Cell {
                row,
                col: indexed.point.column.0,
                ch: cell.c,
                fg,
                bg,
                flags: flags.bits(),
            });
        }

        let selection = content.selection.map(|sel| FrameSelection {
            start_row: sel.start.line.0 + display_offset as i32,
            start_col: sel.start.column.0,
            end_row: sel.end.line.0 + display_offset as i32,
            end_col: sel.end.column.0,
            is_block: sel.is_block,
        });

        Frame {
            cols: self.cols,
            rows: self.rows,
            cursor: FrameCursor {
                row: cursor_point.line.0 + display_offset as i32,
                col: cursor_point.column.0,
                shape: cursor_shape,
                visible: cursor_shape != CursorShape::Hidden,
            },
            display_offset,
            history_size: self.term.history_size(),
            cells,
            selection,
        }
    }

    /// Resolve a cell's abstract fg/bg colors to concrete RGB, applying
    /// SGR `DIM` to the foreground and swapping fg/bg under `INVERSE` so
    /// the renderer receives final colors.
    fn resolve_colors(
        &self,
        fg: alacritty_terminal::vte::ansi::Color,
        bg: alacritty_terminal::vte::ansi::Color,
        flags: Flags,
    ) -> (Rgb, Rgb) {
        let dim = flags.contains(Flags::DIM);
        let resolved_fg = self.palette.resolve_fg(fg, dim);
        let resolved_bg = self.palette.resolve_bg(bg);
        if flags.contains(Flags::INVERSE) {
            (resolved_bg, resolved_fg)
        } else {
            (resolved_fg, resolved_bg)
        }
    }

    /// Set a selection spanning `start` to `end`, each `(line, col)` in
    /// absolute grid coordinates (negative line = scrollback). The
    /// selection text is read back with [`Self::selection_text`].
    pub fn set_selection(&mut self, start: (i32, usize), end: (i32, usize), kind: SelectionKind) {
        let ty = match kind {
            SelectionKind::Simple => SelectionType::Simple,
            SelectionKind::Block => SelectionType::Block,
        };
        let start_point = Point::new(Line(start.0), Column(start.1));
        let end_point = Point::new(Line(end.0), Column(end.1));
        let mut selection = Selection::new(ty, start_point, Side::Left);
        selection.update(end_point, Side::Right);
        self.term.selection = Some(selection);
    }

    /// Clear any active selection.
    pub fn clear_selection(&mut self) {
        self.term.selection = None;
    }

    /// The text covered by the active selection, or `None` if there is no
    /// selection.
    pub fn selection_text(&self) -> Option<String> {
        self.term.selection_to_string()
    }

    /// Scan the grid + scrollback for every occurrence of `query` and
    /// return the matched spans in absolute grid-line coordinates. Empty
    /// queries return no matches. This replaces the Dart buffer-walk
    /// search the old renderer did.
    ///
    /// Matching is per-line and substring-literal (no regex, no wrap
    /// across the line boundary); columns are character offsets within the
    /// line. A line with N occurrences yields N ranges.
    pub fn search(&self, query: &str) -> Vec<MatchRange> {
        if query.is_empty() {
            return Vec::new();
        }
        let query_chars: Vec<char> = query.chars().collect();
        let grid = self.term.grid();
        let top = grid.topmost_line().0;
        let bottom = grid.bottommost_line().0;
        let cols = self.cols;

        let mut matches = Vec::new();
        for line_idx in top..=bottom {
            let line = Line(line_idx);
            let row: Vec<char> = (0..cols).map(|c| grid[line][Column(c)].c).collect();
            collect_line_matches(&row, &query_chars, line_idx, &mut matches);
        }
        matches
    }
}

/// Find every position where `query` occurs in `row` and push a span.
/// Extracted so the search loop body stays flat (cognitive-complexity).
fn collect_line_matches(row: &[char], query: &[char], line_idx: i32, out: &mut Vec<MatchRange>) {
    if query.len() > row.len() {
        return;
    }
    let last_start = row.len() - query.len();
    for start in 0..=last_start {
        if row[start..start + query.len()] == *query {
            out.push(MatchRange {
                line: line_idx,
                start_col: start,
                end_col: start + query.len() - 1,
            });
        }
    }
}

/// Map the parser's cursor shape to our render-facing enum.
fn map_cursor_shape(shape: VteCursorShape) -> CursorShape {
    match shape {
        VteCursorShape::Block => CursorShape::Block,
        VteCursorShape::Underline => CursorShape::Underline,
        VteCursorShape::Beam => CursorShape::Beam,
        VteCursorShape::HollowBlock => CursorShape::HollowBlock,
        VteCursorShape::Hidden => CursorShape::Hidden,
    }
}

#[cfg(test)]
mod tests;
