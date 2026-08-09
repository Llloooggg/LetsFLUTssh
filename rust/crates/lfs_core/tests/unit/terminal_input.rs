/// Unit tests extracted from terminal/input.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn no_mode() -> TermMode {
    TermMode::empty()
}

#[test]
fn plain_char_encodes_utf8() {
    // Spec: a printable char with no modifiers is its UTF-8 bytes.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Char('a')), no_mode()),
        b"a"
    );
    // A multi-byte scalar survives as its UTF-8 encoding.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Char('é')), no_mode()),
        "é".as_bytes()
    );
}

#[test]
fn ctrl_c_is_etx() {
    // Spec: Ctrl+C → 0x03 (ETX), the canonical interrupt byte. Case
    // is irrelevant — Ctrl+c and Ctrl+C both yield 0x03.
    let lower = KeyInput {
        ctrl: true,
        ..KeyInput::new(KeyName::Char('c'))
    };
    let upper = KeyInput {
        ctrl: true,
        ..KeyInput::new(KeyName::Char('C'))
    };
    assert_eq!(encode_key(&lower, no_mode()), vec![0x03]);
    assert_eq!(encode_key(&upper, no_mode()), vec![0x03]);
}

#[test]
fn ctrl_special_control_bytes() {
    // Spec: the classic control range — Ctrl+@ = NUL, Ctrl+[ = ESC,
    // Ctrl+_ = US (0x1F), Ctrl+? = DEL (0x7F), Ctrl+Space = NUL.
    let ctrl = |c: char| {
        encode_key(
            &KeyInput {
                ctrl: true,
                ..KeyInput::new(KeyName::Char(c))
            },
            no_mode(),
        )
    };
    assert_eq!(ctrl('@'), vec![0x00]);
    assert_eq!(ctrl('['), vec![0x1b]);
    assert_eq!(ctrl('_'), vec![0x1f]);
    assert_eq!(ctrl('?'), vec![0x7f]);
    assert_eq!(ctrl(' '), vec![0x00]);
    assert_eq!(ctrl('a'), vec![0x01]);
    assert_eq!(ctrl('z'), vec![0x1a]);
}

#[test]
fn ctrl_non_control_char_falls_back_to_literal() {
    // Spec: Ctrl+1 has no control byte, so the literal '1' types
    // through rather than producing nothing.
    let input = KeyInput {
        ctrl: true,
        ..KeyInput::new(KeyName::Char('1'))
    };
    assert_eq!(encode_key(&input, no_mode()), b"1");
}

#[test]
fn alt_char_gets_escape_prefix() {
    // Spec: Alt+x sends ESC then 'x' (metaSendsEscape default).
    let input = KeyInput {
        alt: true,
        ..KeyInput::new(KeyName::Char('x'))
    };
    assert_eq!(encode_key(&input, no_mode()), vec![0x1b, b'x']);
}

#[test]
fn alt_ctrl_char_escape_then_control_byte() {
    // Spec: Alt+Ctrl+C is ESC then the control byte 0x03.
    let input = KeyInput {
        alt: true,
        ctrl: true,
        ..KeyInput::new(KeyName::Char('c'))
    };
    assert_eq!(encode_key(&input, no_mode()), vec![0x1b, 0x03]);
}

#[test]
fn enter_is_cr_unless_lnm() {
    // Spec: Enter → CR; under LNM (LINE_FEED_NEW_LINE) → CR+LF.
    assert_eq!(encode_key(&KeyInput::new(KeyName::Enter), no_mode()), b"\r");
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Enter), TermMode::LINE_FEED_NEW_LINE),
        b"\r\n"
    );
}

#[test]
fn tab_and_shift_tab() {
    // Spec: Tab → HT; Shift+Tab → CSI Z (back-tab).
    assert_eq!(encode_key(&KeyInput::new(KeyName::Tab), no_mode()), b"\t");
    let shift_tab = KeyInput {
        shift: true,
        ..KeyInput::new(KeyName::Tab)
    };
    assert_eq!(encode_key(&shift_tab, no_mode()), b"\x1b[Z");
}

#[test]
fn backspace_and_escape() {
    // Spec: Backspace → DEL (0x7F), Escape → ESC (0x1B).
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Backspace), no_mode()),
        vec![0x7f]
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Escape), no_mode()),
        vec![0x1b]
    );
}

#[test]
fn arrows_normal_vs_app_cursor() {
    // Spec: arrows are CSI (`\x1b[A..D`) in normal mode and SS3
    // (`\x1bOA..D`) under DECCKM application-cursor-keys.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Up), no_mode()),
        b"\x1b[A"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Down), no_mode()),
        b"\x1b[B"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Right), no_mode()),
        b"\x1b[C"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Left), no_mode()),
        b"\x1b[D"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Up), TermMode::APP_CURSOR),
        b"\x1bOA"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Left), TermMode::APP_CURSOR),
        b"\x1bOD"
    );
}

#[test]
fn home_end_app_cursor() {
    // Spec: Home/End use H/F finals, SS3 under DECCKM.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Home), no_mode()),
        b"\x1b[H"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::End), no_mode()),
        b"\x1b[F"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Home), TermMode::APP_CURSOR),
        b"\x1bOH"
    );
}

#[test]
fn modified_arrows_use_csi_modifier_form() {
    // Spec: modifiers force the CSI `1;mod` form regardless of DECCKM.
    // Modifier code = 1 + (shift=1 | alt=2 | ctrl=4).
    let ctrl_up = KeyInput {
        ctrl: true,
        ..KeyInput::new(KeyName::Up)
    };
    // Ctrl = 4 → 1+4 = 5.
    assert_eq!(encode_key(&ctrl_up, no_mode()), b"\x1b[1;5A");
    // Even under APP_CURSOR the modified form stays CSI.
    assert_eq!(encode_key(&ctrl_up, TermMode::APP_CURSOR), b"\x1b[1;5A");

    let shift_left = KeyInput {
        shift: true,
        ..KeyInput::new(KeyName::Left)
    };
    // Shift = 1 → 1+1 = 2.
    assert_eq!(encode_key(&shift_left, no_mode()), b"\x1b[1;2D");

    let alt_down = KeyInput {
        alt: true,
        ..KeyInput::new(KeyName::Down)
    };
    // Alt = 2 → 1+2 = 3.
    assert_eq!(encode_key(&alt_down, no_mode()), b"\x1b[1;3B");

    let ctrl_shift_right = KeyInput {
        ctrl: true,
        shift: true,
        ..KeyInput::new(KeyName::Right)
    };
    // Shift|Ctrl = 1|4 = 5 → 1+5 = 6.
    assert_eq!(encode_key(&ctrl_shift_right, no_mode()), b"\x1b[1;6C");
}

#[test]
fn modifier_param_covers_full_bitmask() {
    // Spec: the modifier code is 1 + (shift=1|alt=2|ctrl=4). Pin the
    // arithmetic across every combination so the CSI math can't drift.
    let cases = [
        (false, false, false, 1),
        (true, false, false, 2), // shift
        (false, true, false, 3), // alt
        (true, true, false, 4),  // shift+alt
        (false, false, true, 5), // ctrl
        (true, false, true, 6),  // shift+ctrl
        (false, true, true, 7),  // alt+ctrl
        (true, true, true, 8),   // shift+alt+ctrl
    ];
    for (shift, alt, ctrl, expected) in cases {
        let input = KeyInput {
            key: KeyName::Up,
            shift,
            alt,
            ctrl,
            meta: false,
        };
        assert_eq!(modifier_param(&input), expected);
    }
}

#[test]
fn page_insert_delete_tilde_forms() {
    // Spec: PageUp=5, PageDown=6, Insert=2, Delete=3 in the `\x1b[N~`
    // family; modified appends `;mod`.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::PageUp), no_mode()),
        b"\x1b[5~"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::PageDown), no_mode()),
        b"\x1b[6~"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Insert), no_mode()),
        b"\x1b[2~"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::Delete), no_mode()),
        b"\x1b[3~"
    );
    let shift_del = KeyInput {
        shift: true,
        ..KeyInput::new(KeyName::Delete)
    };
    assert_eq!(encode_key(&shift_del, no_mode()), b"\x1b[3;2~");
}

#[test]
fn function_keys_ss3_and_csi() {
    // Spec: F1–F4 → SS3 (`\x1bOP..S`); F5–F12 → CSI `\x1b[N~` with the
    // DEC code table; modified F-keys switch to the CSI `;mod` form.
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::F(1)), no_mode()),
        b"\x1bOP"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::F(4)), no_mode()),
        b"\x1bOS"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::F(5)), no_mode()),
        b"\x1b[15~"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::F(10)), no_mode()),
        b"\x1b[21~"
    );
    assert_eq!(
        encode_key(&KeyInput::new(KeyName::F(12)), no_mode()),
        b"\x1b[24~"
    );
    // Modified F1 → CSI `1;modP`.
    let ctrl_f1 = KeyInput {
        ctrl: true,
        ..KeyInput::new(KeyName::F(1))
    };
    assert_eq!(encode_key(&ctrl_f1, no_mode()), b"\x1b[1;5P");
    // Modified F5 → CSI `15;mod~`.
    let shift_f5 = KeyInput {
        shift: true,
        ..KeyInput::new(KeyName::F(5))
    };
    assert_eq!(encode_key(&shift_f5, no_mode()), b"\x1b[15;2~");
}

#[test]
fn out_of_range_function_key_encodes_nothing() {
    // Spec: only F1–F12 are defined; F0 / F13 produce no bytes rather
    // than a malformed sequence.
    assert!(encode_key(&KeyInput::new(KeyName::F(0)), no_mode()).is_empty());
    assert!(encode_key(&KeyInput::new(KeyName::F(13)), no_mode()).is_empty());
}

#[test]
fn paste_raw_without_bracketed_mode() {
    // Spec: with no bracketed-paste mode, paste is the raw UTF-8 bytes.
    assert_eq!(encode_paste("ls -la\n", no_mode()), b"ls -la\n");
}

#[test]
fn paste_wrapped_under_bracketed_mode() {
    // Spec: bracketed paste frames the body with `\x1b[200~` …
    // `\x1b[201~` so the shell knows the bytes are pasted, not typed.
    let out = encode_paste("echo hi", TermMode::BRACKETED_PASTE);
    assert_eq!(out, b"\x1b[200~echo hi\x1b[201~");
}

#[test]
fn paste_strips_embedded_terminator() {
    // Spec: a body containing the end marker `\x1b[201~` must have it
    // filtered, or a malicious paste could close the paste early and
    // inject the remainder as typed commands.
    let hostile = "safe\x1b[201~rm -rf /";
    let out = encode_paste(hostile, TermMode::BRACKETED_PASTE);
    assert_eq!(out, b"\x1b[200~saferm -rf /\x1b[201~");
    // The terminator must appear exactly once — the trailing frame.
    let body = &out[..out.len() - 6];
    assert!(!body.windows(6).any(|w| w == b"\x1b[201~"));
}

// ---- Mouse reporting tests ----------------------------------------

fn sgr() -> TermMode {
    TermMode::MOUSE_REPORT_CLICK | TermMode::SGR_MOUSE
}

fn mouse(button: MouseButton, action: MouseAction, col: u32, row: u32) -> MouseInput {
    MouseInput {
        button,
        action,
        col,
        row,
        shift: false,
        alt: false,
        ctrl: false,
    }
}

#[test]
fn no_mouse_report_without_tracking() {
    // Spec: with no mouse-tracking mode set, every event encodes to
    // nothing — local selection / scroll handles the pointer instead.
    let press = mouse(MouseButton::Left, MouseAction::Press, 1, 1);
    assert_eq!(encode_mouse(&press, no_mode()), None);
}

#[test]
fn sgr_left_press_and_release() {
    // Spec: SGR press is `\x1b[<Cb;Col;RowM`; the release is the same
    // button code with the trailing `m`. Left button code = 0.
    let press = mouse(MouseButton::Left, MouseAction::Press, 5, 7);
    assert_eq!(encode_mouse(&press, sgr()).unwrap(), b"\x1b[<0;5;7M");
    let release = mouse(MouseButton::Left, MouseAction::Release, 5, 7);
    assert_eq!(encode_mouse(&release, sgr()).unwrap(), b"\x1b[<0;5;7m");
}

#[test]
fn sgr_right_and_middle_button_codes() {
    // Spec: Middle = 1, Right = 2.
    let middle = mouse(MouseButton::Middle, MouseAction::Press, 1, 1);
    assert_eq!(encode_mouse(&middle, sgr()).unwrap(), b"\x1b[<1;1;1M");
    let right = mouse(MouseButton::Right, MouseAction::Press, 1, 1);
    assert_eq!(encode_mouse(&right, sgr()).unwrap(), b"\x1b[<2;1;1M");
}

#[test]
fn sgr_wheel_up_and_down() {
    // Spec: wheel up = 64, wheel down = 65; both are a press (`M`)
    // since the wheel has no release. Reportable under click-only mode.
    let up = mouse(MouseButton::WheelUp, MouseAction::Press, 3, 4);
    assert_eq!(encode_mouse(&up, sgr()).unwrap(), b"\x1b[<64;3;4M");
    let down = mouse(MouseButton::WheelDown, MouseAction::Press, 3, 4);
    assert_eq!(encode_mouse(&down, sgr()).unwrap(), b"\x1b[<65;3;4M");
}

#[test]
fn sgr_drag_sets_motion_bit() {
    // Spec: a drag (button held + Move) ORs in the motion bit 32 — a
    // left-button drag is code 0|32 = 32. Reportable only under
    // button-event (DRAG) mode, not click-only.
    let drag = mouse(MouseButton::Left, MouseAction::Move, 9, 2);
    let mode = TermMode::MOUSE_DRAG | TermMode::SGR_MOUSE;
    assert_eq!(encode_mouse(&drag, mode).unwrap(), b"\x1b[<32;9;2M");
    // The same drag under click-only mode is not reported.
    assert_eq!(encode_mouse(&drag, sgr()), None);
}

#[test]
fn bare_motion_only_under_motion_mode() {
    // Spec: a no-button move is reported only under any-motion mode;
    // the button-event (DRAG) mode does not report button-less motion.
    let move_event = mouse(MouseButton::None, MouseAction::Move, 4, 4);
    let motion = TermMode::MOUSE_MOTION | TermMode::SGR_MOUSE;
    // No-button code 3, plus motion bit 32 = 35.
    assert_eq!(encode_mouse(&move_event, motion).unwrap(), b"\x1b[<35;4;4M");
    let drag_only = TermMode::MOUSE_DRAG | TermMode::SGR_MOUSE;
    assert_eq!(encode_mouse(&move_event, drag_only), None);
}

#[test]
fn sgr_modifier_bits_fold_in() {
    // Spec: Shift=4, Alt=8, Ctrl=16 OR into the button code. A
    // Ctrl+Shift left press = 0 | 16 | 4 = 20.
    let input = MouseInput {
        shift: true,
        ctrl: true,
        ..mouse(MouseButton::Left, MouseAction::Press, 1, 1)
    };
    assert_eq!(encode_mouse(&input, sgr()).unwrap(), b"\x1b[<20;1;1M");
}

#[test]
fn legacy_normal_mouse_report() {
    // Spec: without SGR_MOUSE the legacy `\x1b[M` form encodes three
    // value+32 bytes. Left press at (1,1) = button 0+32=32 (space),
    // col 1+32=33 ('!'), row 1+32=33 ('!').
    let press = mouse(MouseButton::Left, MouseAction::Press, 1, 1);
    let mode = TermMode::MOUSE_REPORT_CLICK;
    assert_eq!(encode_mouse(&press, mode).unwrap(), b"\x1b[M\x20\x21\x21");
}

#[test]
fn legacy_release_uses_button_code_three() {
    // Spec: the legacy form has no per-button release — a normal-button
    // release encodes button code 3 (3+32 = 35 = '#').
    let release = mouse(MouseButton::Left, MouseAction::Release, 1, 1);
    let mode = TermMode::MOUSE_REPORT_CLICK;
    assert_eq!(encode_mouse(&release, mode).unwrap(), b"\x1b[M\x23\x21\x21");
}

#[test]
fn legacy_coordinate_clamps_at_223() {
    // Spec: the legacy byte is coord+32, so coordinates past 223 cannot
    // be represented and clamp to 223 (223+32 = 255 = 0xFF).
    let press = mouse(MouseButton::Left, MouseAction::Press, 500, 1);
    let mode = TermMode::MOUSE_REPORT_CLICK;
    let out = encode_mouse(&press, mode).unwrap();
    assert_eq!(out[4], 0xFF); // clamped column byte
}
