//! VT/xterm key encoder for the headless terminal engine.
//!
//! `alacritty_terminal` ships only the terminal *model* — the Alacritty
//! binary owns its key→byte encoding, so a library consumer gets none. We
//! therefore own a focused encoder here, next to the engine, because the
//! correct byte sequence for a key depends on terminal *modes* the engine
//! tracks live: DECCKM application-cursor-keys ([`TermMode::APP_CURSOR`])
//! flips arrows between CSI and SS3 forms, bracketed-paste
//! ([`TermMode::BRACKETED_PASTE`]) frames pasted text, and LNM
//! ([`TermMode::LINE_FEED_NEW_LINE`]) turns Enter into CR+LF. Placing the
//! encoder Dart-side would mean shipping a stale copy of the mode bits
//! across FRB on every keystroke; here it reads the model the parser
//! already maintains.
//!
//! Dart's only job is to normalise a platform key event into a
//! [`KeyInput`] descriptor — a logical key plus modifier bools — and hand
//! it across FRB. All grammar (control-byte math, CSI modifier codes,
//! SS3 vs CSI selection, paste-terminator filtering) lives here and is
//! unit-tested against xterm/VT semantics.
//!
//! Scope: this encodes a single keystroke's bytes, plus mouse reports
//! ([`encode_mouse`]) for programs that enable mouse tracking (vim/htop
//! click + drag + wheel). It deliberately does NOT implement the Kitty
//! keyboard protocol.

use alacritty_terminal::term::TermMode;

/// A logical key, OS-independent. The Dart layer maps a
/// `LogicalKeyboardKey` (or a typed character) to one of these so the
/// encoder never sees a platform key code.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyName {
    /// A printable character the user typed (already the resolved glyph,
    /// e.g. `'A'` for Shift+a). The encoder applies Ctrl/Alt transforms.
    Char(char),
    Enter,
    Tab,
    Backspace,
    Escape,
    Up,
    Down,
    Right,
    Left,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    /// A function key F1–F12. Values outside 1..=12 encode to nothing.
    F(u8),
}

/// A normalised key event: the logical key plus the modifier state at the
/// time it was pressed. `meta` is the Command / Windows / Super key; it is
/// carried for completeness but, like most terminals, is not folded into
/// the byte encoding (it drives app-level shortcuts, not PTY bytes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyInput {
    pub key: KeyName,
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
}

impl KeyInput {
    /// A modifier-free press of `key` — convenience for callers/tests.
    pub fn new(key: KeyName) -> Self {
        Self {
            key,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }
    }
}

/// The xterm modifier parameter for a CSI/SS3 sequence: `1 + bitmask`
/// where Shift=1, Alt=2, Ctrl=4 (Meta=8, unused here). A return of `1`
/// means "no modifiers" and the caller omits the `;mod` parameter
/// entirely (so an unmodified Up stays `\x1b[A`, not `\x1b[1;1A`).
fn modifier_param(input: &KeyInput) -> u8 {
    let mut mask = 0u8;
    if input.shift {
        mask |= 1;
    }
    if input.alt {
        mask |= 2;
    }
    if input.ctrl {
        mask |= 4;
    }
    1 + mask
}

/// True when the press carries no encodable modifier (Shift/Alt/Ctrl).
/// Meta is excluded — it never enters the byte form.
fn unmodified(input: &KeyInput) -> bool {
    !input.shift && !input.alt && !input.ctrl
}

/// Encode a key press into the bytes to write to the PTY, reading `mode`
/// for the DECCKM / LNM state that changes the encoding.
pub fn encode_key(input: &KeyInput, mode: TermMode) -> Vec<u8> {
    match input.key {
        KeyName::Char(c) => encode_char(c, input),
        KeyName::Enter => encode_enter(mode),
        KeyName::Tab => {
            if input.shift {
                b"\x1b[Z".to_vec()
            } else {
                b"\t".to_vec()
            }
        }
        KeyName::Backspace => vec![0x7f],
        KeyName::Escape => vec![0x1b],
        KeyName::Up => encode_cursor(b'A', input, mode),
        KeyName::Down => encode_cursor(b'B', input, mode),
        KeyName::Right => encode_cursor(b'C', input, mode),
        KeyName::Left => encode_cursor(b'D', input, mode),
        KeyName::Home => encode_cursor(b'H', input, mode),
        KeyName::End => encode_cursor(b'F', input, mode),
        KeyName::PageUp => encode_tilde(5, input),
        KeyName::PageDown => encode_tilde(6, input),
        KeyName::Insert => encode_tilde(2, input),
        KeyName::Delete => encode_tilde(3, input),
        KeyName::F(n) => encode_function(n, input),
    }
}

/// Encode a printable character, applying Ctrl (control byte) and
/// Alt/Meta (ESC prefix) transforms.
fn encode_char(c: char, input: &KeyInput) -> Vec<u8> {
    if input.ctrl {
        if let Some(byte) = control_byte(c) {
            let mut out = Vec::with_capacity(2);
            // Alt+Ctrl+key keeps the ESC prefix in front of the control
            // byte (xterm's metaSendsEscape applies to control keys too).
            if input.alt {
                out.push(0x1b);
            }
            out.push(byte);
            return out;
        }
        // Ctrl with a non-control-producing char (e.g. Ctrl+1): fall
        // through to the plain-char path so the literal still types.
    }
    let mut buf = [0u8; 4];
    let encoded = c.encode_utf8(&mut buf).as_bytes();
    if input.alt {
        // Alt-sends-escape: ESC then the character bytes. This is the
        // xterm default (metaSendsEscape) and what readline / vim expect
        // for Alt-key bindings.
        let mut out = Vec::with_capacity(encoded.len() + 1);
        out.push(0x1b);
        out.extend_from_slice(encoded);
        out
    } else {
        encoded.to_vec()
    }
}

/// Map a character to its Ctrl control byte, or `None` when the
/// combination has no control representation. Covers the classic range:
/// Ctrl+@ = 0x00, Ctrl+A..Ctrl+Z = 0x01..0x1A, Ctrl+[ \ ] ^ _ =
/// 0x1B..0x1F, and Ctrl+? = 0x7F. Letters are upper-cased first so both
/// Ctrl+c and Ctrl+C yield 0x03.
fn control_byte(c: char) -> Option<u8> {
    let upper = c.to_ascii_uppercase();
    match upper {
        '@'..='_' => Some((upper as u8) & 0x1f),
        '?' => Some(0x7f),
        ' ' => Some(0x00),
        _ => None,
    }
}

/// Enter encodes as CR (`\r`) by default; under LNM
/// ([`TermMode::LINE_FEED_NEW_LINE`]) the terminal expects CR+LF.
fn encode_enter(mode: TermMode) -> Vec<u8> {
    if mode.contains(TermMode::LINE_FEED_NEW_LINE) {
        b"\r\n".to_vec()
    } else {
        b"\r".to_vec()
    }
}

/// Encode a cursor / Home / End key. Unmodified, the final byte is
/// prefixed with SS3 (`\x1bO`) under application-cursor-keys mode and CSI
/// (`\x1b[`) otherwise. With modifiers, xterm always uses the CSI form
/// with a `1;mod` parameter (e.g. Ctrl+Up = `\x1b[1;5A`), regardless of
/// DECCKM — the modifier parameter has no SS3 form.
fn encode_cursor(final_byte: u8, input: &KeyInput, mode: TermMode) -> Vec<u8> {
    if unmodified(input) {
        if mode.contains(TermMode::APP_CURSOR) {
            vec![0x1b, b'O', final_byte]
        } else {
            vec![0x1b, b'[', final_byte]
        }
    } else {
        let m = modifier_param(input);
        format!("\x1b[1;{m}{}", final_byte as char).into_bytes()
    }
}

/// Encode a `\x1b[N~`-family key (PageUp/Down, Insert, Delete). With
/// modifiers the parameter becomes `N;mod` (e.g. Shift+Delete =
/// `\x1b[3;2~`).
fn encode_tilde(n: u8, input: &KeyInput) -> Vec<u8> {
    if unmodified(input) {
        format!("\x1b[{n}~").into_bytes()
    } else {
        let m = modifier_param(input);
        format!("\x1b[{n};{m}~").into_bytes()
    }
}

/// Encode a function key. F1–F4 use SS3 (`\x1bOP`..`\x1bOS`) when
/// unmodified; F5–F12 use the CSI `\x1b[N~` form. With any modifier, all
/// of F1–F12 use the CSI `;mod` form (F1–F4 switch to `\x1b[1;modP`..,
/// F5–F12 to `\x1b[N;mod~`) — xterm has no SS3 modifier form. Function
/// numbers outside 1..=12 produce no bytes.
fn encode_function(n: u8, input: &KeyInput) -> Vec<u8> {
    // F1–F4 final letters P, Q, R, S.
    let pf_letter = |n: u8| (b'P' + (n - 1)) as char;
    match n {
        1..=4 => {
            if unmodified(input) {
                vec![0x1b, b'O', pf_letter(n) as u8]
            } else {
                let m = modifier_param(input);
                format!("\x1b[1;{m}{}", pf_letter(n)).into_bytes()
            }
        }
        5..=12 => {
            let code = function_tilde_code(n);
            if unmodified(input) {
                format!("\x1b[{code}~").into_bytes()
            } else {
                let m = modifier_param(input);
                format!("\x1b[{code};{m}~").into_bytes()
            }
        }
        _ => Vec::new(),
    }
}

/// The `\x1b[N~` parameter for F5–F12. The xterm table skips a few
/// numbers (there is no 16, 22, 23-gap rationale beyond DEC history):
/// F5=15, F6=17, F7=18, F8=19, F9=20, F10=21, F11=23, F12=24.
fn function_tilde_code(n: u8) -> u8 {
    match n {
        5 => 15,
        6 => 17,
        7 => 18,
        8 => 19,
        9 => 20,
        10 => 21,
        11 => 23,
        12 => 24,
        _ => 0,
    }
}

/// The bracketed-paste terminator. When the engine is in bracketed-paste
/// mode the pasted body must not contain this sequence, or a hostile /
/// accidental payload could close the paste early and inject the
/// remainder as typed commands.
const PASTE_END: &str = "\x1b[201~";

/// Encode text for a paste. Under [`TermMode::BRACKETED_PASTE`] the body
/// is wrapped in `\x1b[200~` … `\x1b[201~` and any embedded terminator is
/// stripped (the spec's safety requirement — see [`PASTE_END`]). Without
/// bracketed paste the raw UTF-8 bytes are returned unchanged.
pub fn encode_paste(text: &str, mode: TermMode) -> Vec<u8> {
    if mode.contains(TermMode::BRACKETED_PASTE) {
        let safe = text.replace(PASTE_END, "");
        let mut out = Vec::with_capacity(safe.len() + 12);
        out.extend_from_slice(b"\x1b[200~");
        out.extend_from_slice(safe.as_bytes());
        out.extend_from_slice(b"\x1b[201~");
        out
    } else {
        text.as_bytes().to_vec()
    }
}

// ---- Mouse reporting --------------------------------------------------

/// Which button a mouse report is about. Wheel up/down ride the same CSI
/// `M`/SGR channel as buttons (xterm encodes the wheel as buttons 64/65),
/// so they are buttons here. `None` is a bare pointer move with no button
/// held — only encoded under [`TermMode::MOUSE_MOTION`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseButton {
    Left,
    Middle,
    Right,
    WheelUp,
    WheelDown,
    /// No button — a bare motion event.
    None,
}

/// What happened to the pointer. A `Press` reports the button going down,
/// `Release` the button coming up, `Move` a drag (button held) or bare
/// motion (button `None`). Wheel events are always a `Press` (xterm has no
/// wheel release).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseAction {
    Press,
    Release,
    Move,
}

/// A normalised mouse event for [`encode_mouse`]. `col`/`row` are 1-based
/// cell coordinates as they appear in the report (the Dart layer converts
/// pixels → 0-based cell, then the FRB DTO adds 1). Modifier bools fold
/// into the xterm modifier bits (Shift=4, Alt=8, Ctrl=16).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MouseInput {
    pub button: MouseButton,
    pub action: MouseAction,
    /// 1-based column in the report.
    pub col: u32,
    /// 1-based row in the report.
    pub row: u32,
    pub shift: bool,
    pub alt: bool,
    pub ctrl: bool,
}

/// The xterm button code (the low 6 bits of the CC byte before the
/// motion/modifier bits are OR-ed in). Left=0, Middle=1, Right=2,
/// release-of-a-normal-button also uses the button's own code under SGR
/// (the trailing `m` marks it a release) but `3` under the legacy
/// protocol. Wheel up/down are 64/65. A bare motion with no button is the
/// "no button" sentinel 3.
fn mouse_button_code(button: MouseButton) -> u8 {
    match button {
        MouseButton::Left => 0,
        MouseButton::Middle => 1,
        MouseButton::Right => 2,
        MouseButton::None => 3,
        MouseButton::WheelUp => 64,
        MouseButton::WheelDown => 65,
    }
}

/// Fold the modifier bools into the xterm CC byte: Shift=4, Alt(Meta)=8,
/// Ctrl=16. Matches xterm's modifyOtherKeys-independent mouse modifier
/// layout.
fn mouse_modifier_bits(input: &MouseInput) -> u8 {
    let mut bits = 0u8;
    if input.shift {
        bits |= 4;
    }
    if input.alt {
        bits |= 8;
    }
    if input.ctrl {
        bits |= 16;
    }
    bits
}

/// True when the engine's mode reports the given event at all. Click-only
/// mode ([`TermMode::MOUSE_REPORT_CLICK`]) reports press/release but no
/// motion; button-event mode ([`TermMode::MOUSE_DRAG`]) adds motion while a
/// button is held; any-motion mode ([`TermMode::MOUSE_MOTION`]) adds bare
/// motion with no button. Wheel and press/release report under any of the
/// three.
fn mouse_event_reported(input: &MouseInput, mode: TermMode) -> bool {
    let any_tracking = mode
        .intersects(TermMode::MOUSE_REPORT_CLICK | TermMode::MOUSE_DRAG | TermMode::MOUSE_MOTION);
    if !any_tracking {
        return false;
    }
    match input.action {
        MouseAction::Press | MouseAction::Release => true,
        MouseAction::Move => {
            if input.button == MouseButton::None {
                // Bare motion (no button) only under any-motion mode.
                mode.contains(TermMode::MOUSE_MOTION)
            } else {
                // Drag (button held) under button-event or any-motion mode.
                mode.intersects(TermMode::MOUSE_DRAG | TermMode::MOUSE_MOTION)
            }
        }
    }
}

/// Encode a mouse event into the bytes to write to the PTY, or `None` when
/// the current `mode` does not report that event (no tracking enabled, or a
/// motion event under a mode that only reports clicks). Produces the SGR
/// form (`\x1b[<Cb;Col;Row M` for press/motion, `…m` for release) when
/// [`TermMode::SGR_MOUSE`] is set, otherwise the legacy X10/normal form
/// (`\x1b[M` then three bytes `Cb+32`, `Col+32`, `Row+32`).
///
/// SGR is preferred when available because the legacy form caps a
/// coordinate at 223 (255 − 32): a click past column 223 in the legacy
/// form would emit a byte the program cannot decode, so the legacy branch
/// clamps to that ceiling while SGR carries the true coordinate.
pub fn encode_mouse(input: &MouseInput, mode: TermMode) -> Option<Vec<u8>> {
    if !mouse_event_reported(input, mode) {
        return None;
    }
    let base = mouse_button_code(input.button);
    // Motion (drag / bare-move) sets bit 5 (32) on the button code.
    let motion_bit = if input.action == MouseAction::Move {
        32
    } else {
        0
    };
    let modifiers = mouse_modifier_bits(input);

    if mode.contains(TermMode::SGR_MOUSE) {
        let cb = u32::from(base) | u32::from(motion_bit) | u32::from(modifiers);
        // Release is the trailing `m`; press / motion / wheel use `M`. A
        // wheel is always a press (no release), so it takes `M`.
        let terminator = if input.action == MouseAction::Release {
            'm'
        } else {
            'M'
        };
        Some(format!("\x1b[<{cb};{};{}{terminator}", input.col, input.row).into_bytes())
    } else {
        encode_legacy_mouse(input, base, motion_bit, modifiers)
    }
}

/// The legacy X10/normal mouse report: `\x1b[M` then three bytes, each a
/// value offset by 32. A normal-button release encodes the button code 3
/// (the protocol has no per-button release); wheel and motion keep their
/// own codes. Coordinates clamp to 223 because the byte is `value + 32`
/// and a `u8` saturates at 255.
fn encode_legacy_mouse(
    input: &MouseInput,
    base: u8,
    motion_bit: u8,
    modifiers: u8,
) -> Option<Vec<u8>> {
    // A normal-button release loses its button identity in the legacy
    // form — code 3 with the motion/modifier bits preserved.
    let button_code = if input.action == MouseAction::Release
        && matches!(
            input.button,
            MouseButton::Left | MouseButton::Middle | MouseButton::Right
        ) {
        3
    } else {
        base
    };
    let cb = button_code
        .wrapping_add(motion_bit)
        .wrapping_add(modifiers)
        .wrapping_add(32);
    let col = clamp_legacy_coord(input.col);
    let row = clamp_legacy_coord(input.row);
    Some(vec![0x1b, b'[', b'M', cb, col, row])
}

/// Clamp a 1-based coordinate into the legacy report's representable range
/// and offset it by 32. The byte holds `coord + 32`, so the largest
/// encodable coordinate is `255 - 32 = 223`; past that the legacy protocol
/// cannot represent the position and clamps to the ceiling.
fn clamp_legacy_coord(coord: u32) -> u8 {
    let clamped = coord.min(223);
    (clamped as u8).wrapping_add(32)
}

#[cfg(test)]
mod tests {
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
}
