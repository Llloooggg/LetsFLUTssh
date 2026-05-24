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
//! Scope: this encodes a single keystroke's bytes. It deliberately does
//! NOT implement the Kitty keyboard protocol, nor SGR mouse reporting —
//! mouse input (vim/htop click + drag) is a separate follow-up.

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
}
