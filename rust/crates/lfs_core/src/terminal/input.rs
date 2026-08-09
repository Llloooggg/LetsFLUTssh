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
#[path = "../../tests/unit/terminal_input.rs"]
mod tests;
