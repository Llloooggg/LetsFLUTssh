//! Owned snapshot DTOs handed to the renderer.
//!
//! Every type here is plain owned data — no borrows into the engine, no
//! `alacritty_terminal` / `vte` types, no FRB types. A [`Frame`] is the
//! complete render state for one paint: the engine builds it inside
//! `snapshot()` (which borrows `Term` transiently) and returns it by
//! value, so the caller can hold it across `await` points and FFI calls.

use super::palette::Rgb;

/// Cursor rendering shape, mirroring the VT cursor styles. The renderer
/// chooses a glyph per shape; `Hidden` means do not paint the cursor.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CursorShape {
    Block,
    Underline,
    Beam,
    HollowBlock,
    Hidden,
}

/// Cursor position and shape for one frame.
///
/// `row` is in display-viewport coordinates: `0` is the top visible line,
/// matching the rows emitted in [`Frame::cells`]. It is signed because the
/// engine's native line index is signed (scrollback is negative), but a
/// rendered cursor always lands in `0..rows`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameCursor {
    pub row: i32,
    pub col: usize,
    pub shape: CursorShape,
    pub visible: bool,
}

/// One painted cell. `flags` is the raw `alacritty_terminal` bitflags
/// (`u16`) so the renderer can test BOLD / ITALIC / UNDERLINE / etc.
/// without us re-encoding the bit layout. `fg` and `bg` are already
/// resolved to concrete RGB with INVERSE/DIM applied — the renderer never
/// resolves color.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cell {
    /// Viewport row (`0` = top visible line).
    pub row: i32,
    pub col: usize,
    /// Primary character. Combining marks (`zerowidth`) are not modelled
    /// in this first cut — flagged for the FRB task.
    pub ch: char,
    pub fg: Rgb,
    pub bg: Rgb,
    pub flags: u16,
}

/// Selection span for one frame, in viewport-row coordinates. `is_block`
/// distinguishes a rectangular (block) selection from a linear one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameSelection {
    pub start_row: i32,
    pub start_col: usize,
    pub end_row: i32,
    pub end_col: usize,
    pub is_block: bool,
}

/// Which mouse-tracking level the running program enabled, carried in the
/// frame so the renderer can decide — without an extra FFI call per
/// pointer event — whether a drag should be sent to the program as a mouse
/// report or handled locally as text selection. `None` means no tracking:
/// the pointer drives local selection / scrollback. The levels are
/// inclusive supersets in capability — `anyMotion` also reports drags and
/// clicks — but they are distinct so the renderer can still gate bare
/// motion (only `anyMotion` wants button-less moves).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseTracking {
    /// No mouse tracking — the pointer is local (selection / scroll).
    None,
    /// Click-only (`?1000h`): press / release, no motion.
    Click,
    /// Button-event (`?1002h`): press / release + drag (button held).
    ButtonEvent,
    /// Any-motion (`?1003h`): press / release + drag + bare motion.
    AnyMotion,
}

/// Complete render state for one paint. Owned — safe to hold across FFI.
#[derive(Debug, Clone)]
pub struct Frame {
    pub cols: usize,
    pub rows: usize,
    pub cursor: FrameCursor,
    /// How many lines the viewport is scrolled up into scrollback. `0`
    /// means the live screen is showing.
    pub display_offset: usize,
    /// Total scrollback lines available above the live screen.
    pub history_size: usize,
    /// Mouse-tracking level the running program enabled. The renderer
    /// routes pointer events to the program (mouse report) vs locally
    /// (selection / scroll) off this — a Shift modifier always forces
    /// local selection regardless, matching the xterm override convention.
    pub mouse_tracking: MouseTracking,
    /// Non-blank cells in the current viewport. Blank default cells are
    /// omitted so the renderer paints the background once and overlays only
    /// what differs — the grid is sparse for most TUI screens.
    pub cells: Vec<Cell>,
    pub selection: Option<FrameSelection>,
}
