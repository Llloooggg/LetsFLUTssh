//! Coverage-guided fuzzer for `lfs_core::terminal::TerminalEngine::feed`.
//!
//! The terminal engine parses raw output bytes from the remote shell —
//! a fully attacker-controlled SSH stream of ANSI/VT escape sequences,
//! OSC strings, CSI parameters, and arbitrary text. A malformed or
//! hostile sequence must never panic the parser, index out of the grid,
//! or leave the engine in a state where `snapshot` / `search` /
//! `selection_text` / `drain_events` crash. This target drives arbitrary
//! bytes through `feed` (in several chunks, so escape sequences split
//! across `advance` calls exercise the parser's cross-chunk buffering)
//! and then asserts the engine stays internally consistent: the snapshot
//! geometry matches the configured grid, and every cursor / cell
//! coordinate lands inside the viewport.
//!
//! Not run in CI (cargo-fuzz needs nightly) — local maintainer runs
//! `cargo +nightly fuzz run terminal_engine` from `rust/fuzz/`.

#![no_main]

use lfs_core::terminal::{TermPalette, TerminalEngine};
use libfuzzer_sys::fuzz_target;

const COLS: usize = 80;
const ROWS: usize = 24;
const SCROLLBACK: usize = 100;

fuzz_target!(|data: &[u8]| {
    let mut engine = TerminalEngine::new(COLS, ROWS, SCROLLBACK, TermPalette::one_dark());

    // Split the input into a handful of chunks so an escape sequence that
    // straddles a boundary is delivered across multiple `feed` calls —
    // the parser buffers partial sequences between `advance` invocations,
    // and that resumption path is where cross-chunk state bugs hide.
    let chunks = 4;
    let len = data.len();
    for i in 0..chunks {
        let start = len * i / chunks;
        let end = len * (i + 1) / chunks;
        engine.feed(&data[start..end]);
    }

    // None of the read-side surfaces may panic on a hostile stream.
    let frame = engine.snapshot();
    let _ = engine.search("a");
    let _ = engine.selection_text();
    let _ = engine.drain_events();

    // Snapshot geometry must mirror the configured viewport — `feed`
    // alone (no resize) never changes the grid dimensions.
    assert_eq!(
        frame.cols, COLS,
        "snapshot cols drifted from configured size"
    );
    assert_eq!(
        frame.rows, ROWS,
        "snapshot rows drifted from configured size"
    );

    // The rendered cursor always lands inside the live viewport. `row` is
    // in display-viewport coordinates (0 = top visible line); with no
    // scrolling it must be in `0..rows` and the column in `0..cols`.
    assert!(
        frame.cursor.row >= 0 && (frame.cursor.row as usize) < ROWS,
        "cursor row {} out of bounds (rows={ROWS})",
        frame.cursor.row
    );
    assert!(
        frame.cursor.col < COLS,
        "cursor col {} out of bounds (cols={COLS})",
        frame.cursor.col
    );

    // Every painted cell must sit inside the viewport — an out-of-range
    // coordinate would index past the renderer's grid on the Flutter side.
    for cell in &frame.cells {
        assert!(
            cell.row >= 0 && (cell.row as usize) < ROWS,
            "cell row {} out of bounds (rows={ROWS})",
            cell.row
        );
        assert!(
            cell.col < COLS,
            "cell col {} out of bounds (cols={COLS})",
            cell.col
        );
    }
});
