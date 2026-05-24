//! Behavioral tests for the terminal engine.
//!
//! Each test states the intended VT semantics it asserts — never the raw
//! observed output of a prior run. The vim-repro test is the regression
//! guard for the `xterm` scroll-region corruption that motivated this
//! engine.

use super::*;

const ESC: &str = "\x1b";

fn engine(cols: usize, rows: usize) -> TerminalEngine {
    TerminalEngine::new(cols, rows, 1000, TermPalette::one_dark())
}

/// Read the visible glyphs of one viewport row into a String, trimming
/// trailing blanks. Blank default cells are omitted from the snapshot, so
/// we reconstruct the row from the sparse cell list.
fn row_text(frame: &Frame, row: i32) -> String {
    let mut chars: Vec<char> = vec![' '; frame.cols];
    for cell in &frame.cells {
        if cell.row == row && cell.col < frame.cols {
            chars[cell.col] = cell.ch;
        }
    }
    chars.into_iter().collect::<String>().trim_end().to_string()
}

#[test]
fn plain_text_lands_on_row_zero_and_advances_cursor() {
    // Spec: feeding printable bytes writes them left-to-right on the
    // current line and advances the cursor one column per glyph.
    let mut eng = engine(20, 5);
    eng.feed(b"hello");
    let frame = eng.snapshot();
    assert_eq!(row_text(&frame, 0), "hello");
    assert_eq!(frame.cursor.row, 0);
    assert_eq!(frame.cursor.col, 5);
}

#[test]
fn carriage_return_and_newline_move_cursor() {
    // Spec: \r returns the cursor to column 0; \n moves it down one line.
    // "ab\r\ncd" => "ab" on row 0, "cd" on row 1.
    let mut eng = engine(20, 5);
    eng.feed(b"ab\r\ncd");
    let frame = eng.snapshot();
    assert_eq!(row_text(&frame, 0), "ab");
    assert_eq!(row_text(&frame, 1), "cd");
}

#[test]
fn vim_scroll_region_delete_line_shifts_without_stale_rows() {
    // The regression guard for upstream xterm #222: vim deleting a line
    // inside a scroll region left stale/duplicated rows below it (stray
    // horizontal stripes).
    //
    // VT sequence vim emits to delete the line under the cursor inside a
    // scroll region:
    //   ESC[2J ESC[H        clear screen, cursor home
    //   write 5 lines       L1..L5, one per row
    //   ESC[1;5r            set scroll region to rows 1..5 (1-based)
    //   ESC[2;1H            move cursor to row 2, col 1 (the line to drop)
    //   ESC[M               delete-line: rows below scroll up, the bottom
    //                       row of the region is cleared
    //
    // Correct result: L1 stays, L2 is gone, L3/L4/L5 shift up one row, and
    // the vacated bottom row (row 4) is blank — not a duplicate of L5.
    let mut eng = engine(10, 5);
    eng.feed(format!("{ESC}[2J{ESC}[H").as_bytes());
    eng.feed(b"L1\r\nL2\r\nL3\r\nL4\r\nL5");
    eng.feed(format!("{ESC}[1;5r").as_bytes());
    eng.feed(format!("{ESC}[2;1H").as_bytes());
    eng.feed(format!("{ESC}[M").as_bytes());

    let frame = eng.snapshot();
    assert_eq!(
        row_text(&frame, 0),
        "L1",
        "row 0 above the deleted line is untouched"
    );
    assert_eq!(
        row_text(&frame, 1),
        "L3",
        "L3 shifted up into the deleted line's row"
    );
    assert_eq!(row_text(&frame, 2), "L4");
    assert_eq!(row_text(&frame, 3), "L5");
    assert_eq!(
        row_text(&frame, 4),
        "",
        "vacated bottom row is blank, not a stale L5 copy"
    );
}

#[test]
fn scroll_up_inside_region_clears_vacated_row() {
    // Spec: ESC[S scrolls the scroll region up one line; the top line of
    // the region scrolls off and the bottom line is blanked. With a full
    // region this is equivalent to a screen scroll-up.
    let mut eng = engine(10, 4);
    eng.feed(b"A\r\nB\r\nC\r\nD");
    eng.feed(format!("{ESC}[S").as_bytes());
    let frame = eng.snapshot();
    assert_eq!(row_text(&frame, 0), "B");
    assert_eq!(row_text(&frame, 1), "C");
    assert_eq!(row_text(&frame, 2), "D");
    assert_eq!(row_text(&frame, 3), "");
}

#[test]
fn resize_keeps_cursor_in_bounds_and_preserves_content() {
    // Spec: after a resize the cursor must stay within the new viewport,
    // and existing visible content must survive (alacritty reflows wrapped
    // lines but short lines stay put).
    let mut eng = engine(20, 6);
    eng.feed(b"first\r\nsecond");
    eng.resize(10, 4);
    let frame = eng.snapshot();
    assert!(
        frame.cursor.col < frame.cols,
        "cursor column within new width"
    );
    assert!(frame.cursor.row >= 0 && (frame.cursor.row as usize) < frame.rows);
    // The two short lines fit in 10 columns, so they survive intact.
    let joined: String = (0..frame.rows as i32)
        .map(|r| row_text(&frame, r))
        .collect();
    assert!(joined.contains("first"));
    assert!(joined.contains("second"));
}

#[test]
fn writing_past_viewport_builds_scrollback() {
    // Spec: writing more lines than the viewport height pushes the oldest
    // lines into scrollback, so history_size grows; scrolling up changes
    // display_offset and reveals the scrolled-away content.
    let mut eng = engine(10, 3);
    for i in 0..10 {
        eng.feed(format!("line{i}\r\n").as_bytes());
    }
    let before = eng.snapshot();
    assert!(
        before.history_size > 0,
        "lines pushed off-screen become scrollback"
    );
    assert_eq!(
        before.display_offset, 0,
        "live screen showing before scroll"
    );

    eng.scroll(2);
    let after = eng.snapshot();
    assert_eq!(
        after.display_offset, 2,
        "scrolling up moves the viewport into history"
    );
    // The viewport now shows older content than the live screen did.
    let after_top = row_text(&after, 0);
    assert_ne!(after_top, row_text(&before, 0));
}

#[test]
fn scroll_to_bottom_returns_to_live_screen() {
    // Spec: after scrolling into history, jumping to bottom restores a
    // zero display offset (the live screen).
    let mut eng = engine(10, 3);
    for i in 0..10 {
        eng.feed(format!("line{i}\r\n").as_bytes());
    }
    eng.scroll(3);
    assert_eq!(eng.snapshot().display_offset, 3);
    eng.scroll_to_bottom();
    assert_eq!(eng.snapshot().display_offset, 0);
}

#[test]
fn clear_wipes_grid_scrollback_and_homes_cursor() {
    // Spec: clear() is the auto-lock / wipe scrub. It must remove the
    // buffered output entirely — not merely scroll the viewport — so
    // sensitive command output cannot be read back. After clear(): the
    // visible grid is blank, the cursor is homed at (0,0), and the
    // scrollback history is gone (history_size == 0). Scrolling back must
    // reveal nothing, since there is no history to reveal.
    let mut eng = engine(10, 3);
    // Write more than `rows` lines so the oldest spill into scrollback.
    for i in 0..10 {
        eng.feed(format!("line{i}\r\n").as_bytes());
    }
    let before = eng.snapshot();
    assert!(
        before.history_size > 0,
        "precondition: lines pushed off-screen built scrollback"
    );
    assert!(
        !before.cells.is_empty(),
        "precondition: the visible grid has content"
    );

    eng.clear();

    let frame = eng.snapshot();
    assert!(
        frame.cells.is_empty(),
        "every visible cell is blanked after clear"
    );
    assert_eq!(frame.cursor.row, 0, "cursor homed to row 0");
    assert_eq!(frame.cursor.col, 0, "cursor homed to col 0");
    assert_eq!(frame.history_size, 0, "scrollback history is purged");
    assert_eq!(frame.display_offset, 0, "viewport back on the live screen");

    // No retained content to scroll back into.
    eng.scroll(5);
    let scrolled = eng.snapshot();
    assert_eq!(
        scrolled.display_offset, 0,
        "no history remains, so scrolling up is a no-op"
    );
    assert!(scrolled.cells.is_empty(), "still nothing buffered to show");
}

#[test]
fn sgr_foreground_color_resolves_to_palette_rgb() {
    // Spec: SGR 31 selects ANSI red; the snapshot cell must carry the
    // palette's resolved red RGB, never an abstract Named color.
    let mut eng = engine(10, 2);
    let palette = TermPalette::one_dark();
    eng.feed(format!("{ESC}[31mR").as_bytes());
    let frame = eng.snapshot();
    let cell = frame.cells.iter().find(|c| c.ch == 'R').expect("R painted");
    assert_eq!(cell.fg, palette.ansi[1], "fg resolves to palette red");
}

#[test]
fn sgr_bold_flag_is_recorded() {
    // Spec: SGR 1 sets the BOLD attribute; the cell flags must carry it so
    // the renderer can pick a bold font.
    let mut eng = engine(10, 2);
    eng.feed(format!("{ESC}[1mB").as_bytes());
    let frame = eng.snapshot();
    let cell = frame.cells.iter().find(|c| c.ch == 'B').expect("B painted");
    assert!(Flags::from_bits_truncate(cell.flags).contains(Flags::BOLD));
}

#[test]
fn sgr_inverse_swaps_resolved_fg_and_bg() {
    // Spec: SGR 7 (inverse) swaps foreground and background at render time.
    // With default colors, an inverse cell's fg becomes the default bg and
    // its bg becomes the default fg.
    let mut eng = engine(10, 2);
    let palette = TermPalette::one_dark();
    eng.feed(format!("{ESC}[7mI").as_bytes());
    let frame = eng.snapshot();
    let cell = frame.cells.iter().find(|c| c.ch == 'I').expect("I painted");
    assert_eq!(cell.fg, palette.background, "inverse fg is the default bg");
    assert_eq!(cell.bg, palette.foreground, "inverse bg is the default fg");
}

#[test]
fn selection_returns_selected_text() {
    // Spec: a simple selection over known cells yields exactly that text.
    let mut eng = engine(20, 3);
    eng.feed(b"copyme");
    // Select columns 0..4 on row 0 => "copy".
    eng.set_selection((0, 0), (0, 3), SelectionKind::Simple);
    assert_eq!(eng.selection_text().as_deref(), Some("copy"));
}

#[test]
fn semantic_selection_expands_to_whole_word() {
    // Spec: a Semantic (double-click) selection started anywhere inside a
    // word expands out to the word's boundaries. Words break on alacritty's
    // semantic escape chars (whitespace + common punctuation), so over
    // "foo bar baz" a click inside "bar" yields exactly "bar" regardless of
    // which column of the word the start/end land on.
    let mut eng = engine(20, 3);
    eng.feed(b"foo bar baz");
    // "bar" occupies columns 4..6; start and end both inside the word.
    eng.set_selection((0, 5), (0, 5), SelectionKind::Semantic);
    assert_eq!(eng.selection_text().as_deref(), Some("bar"));
    // Starting on the first column of the word expands the same way.
    eng.set_selection((0, 4), (0, 4), SelectionKind::Semantic);
    assert_eq!(eng.selection_text().as_deref(), Some("bar"));
}

#[test]
fn lines_selection_expands_to_whole_line() {
    // Spec: a Lines (triple-click) selection started at one cell expands to
    // cover the entire grid line the point touches, regardless of the start
    // column. A whole-line selection carries the line terminator, so the
    // text reads back with a trailing newline.
    let mut eng = engine(20, 3);
    eng.feed(b"the whole line here");
    eng.set_selection((0, 9), (0, 9), SelectionKind::Lines);
    assert_eq!(
        eng.selection_text().as_deref(),
        Some("the whole line here\n")
    );
}

#[test]
fn clear_selection_drops_text() {
    // Spec: clearing the selection leaves no selected text.
    let mut eng = engine(20, 3);
    eng.feed(b"hello");
    eng.set_selection((0, 0), (0, 4), SelectionKind::Simple);
    assert!(eng.selection_text().is_some());
    eng.clear_selection();
    assert_eq!(eng.selection_text(), None);
}

#[test]
fn dsr_cursor_position_request_emits_pty_write() {
    // Spec: ESC[6n is a Device Status Report asking for the cursor
    // position; the terminal must reply with a CPR (ESC[row;colR) bytes
    // the caller forwards to the PTY. We assert a PtyWrite is queued and
    // its payload is a well-formed CPR report.
    let mut eng = engine(10, 3);
    eng.feed(b"ab"); // cursor now at row 1, col 3 (1-based)
    eng.feed(format!("{ESC}[6n").as_bytes());
    let events = eng.drain_events();
    let reply = events.iter().find_map(|e| match e {
        TerminalEvent::PtyWrite(bytes) => Some(bytes.clone()),
        _ => None,
    });
    let reply = reply.expect("DSR request must produce a PtyWrite reply");
    let text = String::from_utf8(reply).expect("CPR reply is ASCII");
    assert!(text.starts_with(ESC), "reply is a CSI sequence");
    assert!(text.ends_with('R'), "CPR reply terminates with R");
    assert!(text.contains("1;3"), "reports cursor at row 1, col 3");
}

#[test]
fn bell_byte_emits_bell_event() {
    // Spec: a BEL byte (0x07) raises a Bell event for the UI.
    let mut eng = engine(10, 2);
    eng.feed(b"\x07");
    assert!(eng.drain_events().contains(&TerminalEvent::Bell));
}

#[test]
fn osc_title_emits_title_event() {
    // Spec: OSC 0 sets the window/icon title; the engine surfaces it as a
    // Title event. Sequence: ESC ] 0 ; <title> BEL.
    let mut eng = engine(10, 2);
    eng.feed(format!("{ESC}]0;my-title\x07").as_bytes());
    let events = eng.drain_events();
    assert!(events.contains(&TerminalEvent::Title("my-title".to_string())));
}

#[test]
fn drain_events_is_idempotent() {
    // Spec: draining clears the queue, so a second drain with no new input
    // returns nothing.
    let mut eng = engine(10, 2);
    eng.feed(b"\x07");
    assert!(!eng.drain_events().is_empty());
    assert!(eng.drain_events().is_empty());
}

#[test]
fn search_finds_substring_on_screen() {
    // Spec: search scans every grid line for literal substring matches and
    // reports each occurrence's line and column span.
    let mut eng = engine(20, 3);
    eng.feed(b"the cat sat\r\non the mat");
    let matches = eng.search("the");
    // "the" at row 0 col 0, and "the" inside "on the mat" at row 1 col 3.
    assert_eq!(matches.len(), 2);
    assert!(matches.contains(&MatchRange {
        line: 0,
        start_col: 0,
        end_col: 2
    }));
    assert!(matches.contains(&MatchRange {
        line: 1,
        start_col: 3,
        end_col: 5
    }));
}

#[test]
fn search_reaches_into_scrollback() {
    // Spec: search covers scrollback, not just the visible viewport, so a
    // match scrolled off-screen is still found (negative line index).
    let mut eng = engine(10, 2);
    eng.feed(b"needle\r\n");
    for i in 0..5 {
        eng.feed(format!("pad{i}\r\n").as_bytes());
    }
    let matches = eng.search("needle");
    assert_eq!(matches.len(), 1);
    assert!(
        matches[0].line < 0,
        "the match lives in scrollback (negative line)"
    );
    assert_eq!(matches[0].start_col, 0);
    assert_eq!(matches[0].end_col, 5);
}

#[test]
fn empty_search_returns_no_matches() {
    // Spec: an empty query is not a wildcard — it matches nothing.
    let mut eng = engine(10, 2);
    eng.feed(b"content");
    assert!(eng.search("").is_empty());
}

#[test]
fn set_palette_changes_resolved_colors() {
    // Spec: replacing the palette re-resolves already-parsed cells against
    // the new colors on the next snapshot.
    let mut eng = engine(10, 2);
    eng.feed(format!("{ESC}[31mX").as_bytes());
    let before = eng
        .snapshot()
        .cells
        .iter()
        .find(|c| c.ch == 'X')
        .map(|c| c.fg)
        .expect("X painted");

    let mut palette = TermPalette::one_dark();
    palette.ansi[1] = Rgb::new(1, 2, 3);
    eng.set_palette(palette);
    let after = eng
        .snapshot()
        .cells
        .iter()
        .find(|c| c.ch == 'X')
        .map(|c| c.fg)
        .expect("X painted");

    assert_ne!(before, after);
    assert_eq!(after, Rgb::new(1, 2, 3));
}

#[test]
fn frame_reports_no_mouse_tracking_by_default() {
    // Spec: a fresh engine has no mouse tracking — the pointer is local
    // (selection / scroll), so the frame reports `None`.
    let eng = engine(20, 5);
    assert_eq!(eng.snapshot().mouse_tracking, MouseTracking::None);
}

#[test]
fn frame_tracks_mouse_dec_modes() {
    // Spec: enabling a mouse DEC mode surfaces the matching tracking level
    // in the frame so the renderer routes the pointer to the program.
    // `?1000h` = click-only, `?1002h` = button-event, `?1003h` = any-motion.
    let mut eng = engine(20, 5);
    eng.feed(b"\x1b[?1000h");
    assert_eq!(eng.snapshot().mouse_tracking, MouseTracking::Click);
    eng.feed(b"\x1b[?1002h");
    assert_eq!(eng.snapshot().mouse_tracking, MouseTracking::ButtonEvent);
    eng.feed(b"\x1b[?1003h");
    assert_eq!(eng.snapshot().mouse_tracking, MouseTracking::AnyMotion);
    // Disabling returns to local.
    eng.feed(b"\x1b[?1003l\x1b[?1002l\x1b[?1000l");
    assert_eq!(eng.snapshot().mouse_tracking, MouseTracking::None);
}

#[test]
fn zero_dimensions_are_clamped() {
    // Spec: a 0-width or 0-height engine would panic the grid; the
    // constructor clamps to at least 1x1 so a degenerate resize during
    // layout never crashes.
    let eng = TerminalEngine::new(0, 0, 100, TermPalette::one_dark());
    let frame = eng.snapshot();
    assert!(frame.cols >= 1 && frame.rows >= 1);
}
