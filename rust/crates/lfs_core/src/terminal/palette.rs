//! Color model for the terminal engine.
//!
//! `alacritty_terminal` ships no default palette: cells carry an
//! abstract [`vte::ansi::Color`] (`Named` / `Indexed` / `Spec`) and the
//! crate leaves resolution to the renderer. We resolve every cell to a
//! concrete [`Rgb`] inside the engine so the future FRB/Flutter layer
//! receives only RGB triples — it never has to know the 16-color names,
//! the 256-color cube, or how `INVERSE`/`DIM` mutate a color.

use alacritty_terminal::vte::ansi::{Color, NamedColor, Rgb as VteRgb};

/// 24-bit color. Our own type so the FRB boundary (added later) does not
/// leak the upstream `vte::ansi::Rgb`; the renderer talks RGB, nothing more.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b }
    }

    const fn from_vte(c: VteRgb) -> Self {
        Self {
            r: c.r,
            g: c.g,
            b: c.b,
        }
    }
}

/// The colors the engine resolves against: the 16 ANSI base colors plus
/// the default foreground / background / cursor / selection swatches.
///
/// The 256-color cube (indices 16..256) is derived deterministically in
/// [`TermPalette::indexed`], so it is not stored here. A caller (theme
/// layer) supplies these; [`TermPalette::one_dark`] gives a sensible
/// default matching the app's OneDark theme.
#[derive(Debug, Clone)]
pub struct TermPalette {
    /// Indices 0..16: black, red, green, yellow, blue, magenta, cyan,
    /// white, then their eight bright variants, in NamedColor order.
    pub ansi: [Rgb; 16],
    pub foreground: Rgb,
    pub background: Rgb,
    pub cursor: Rgb,
    pub selection: Rgb,
}

impl TermPalette {
    /// OneDark default — matches the app theme so the engine has a usable
    /// palette before any OSC color override arrives from the remote host.
    pub fn one_dark() -> Self {
        Self {
            ansi: [
                Rgb::new(0x28, 0x2c, 0x34), // black
                Rgb::new(0xe0, 0x6c, 0x75), // red
                Rgb::new(0x98, 0xc3, 0x79), // green
                Rgb::new(0xe5, 0xc0, 0x7b), // yellow
                Rgb::new(0x61, 0xaf, 0xef), // blue
                Rgb::new(0xc6, 0x78, 0xdd), // magenta
                Rgb::new(0x56, 0xb6, 0xc2), // cyan
                Rgb::new(0xab, 0xb2, 0xbf), // white
                Rgb::new(0x5c, 0x63, 0x70), // bright black
                Rgb::new(0xe0, 0x6c, 0x75), // bright red
                Rgb::new(0x98, 0xc3, 0x79), // bright green
                Rgb::new(0xe5, 0xc0, 0x7b), // bright yellow
                Rgb::new(0x61, 0xaf, 0xef), // bright blue
                Rgb::new(0xc6, 0x78, 0xdd), // bright magenta
                Rgb::new(0x56, 0xb6, 0xc2), // bright cyan
                Rgb::new(0xff, 0xff, 0xff), // bright white
            ],
            foreground: Rgb::new(0xab, 0xb2, 0xbf),
            background: Rgb::new(0x28, 0x2c, 0x34),
            cursor: Rgb::new(0x52, 0x8b, 0xff),
            selection: Rgb::new(0x3e, 0x44, 0x51),
        }
    }

    /// Resolve a 256-palette index to RGB. 0..16 hit the ANSI table;
    /// 16..232 are the 6x6x6 color cube; 232..256 are the 24-step
    /// grayscale ramp. This is the standard xterm 256-color layout.
    fn indexed(&self, idx: u8) -> Rgb {
        match idx {
            0..=15 => self.ansi[idx as usize],
            16..=231 => {
                // 6x6x6 cube. Each channel steps 0,95,135,175,215,255.
                let i = idx - 16;
                let r = i / 36;
                let g = (i % 36) / 6;
                let b = i % 6;
                Rgb::new(cube_step(r), cube_step(g), cube_step(b))
            }
            232..=255 => {
                // 24-step grayscale ramp from 8 to 238 in steps of 10.
                let level = 8 + 10 * (idx as u16 - 232);
                let v = level as u8;
                Rgb::new(v, v, v)
            }
        }
    }

    /// Resolve a [`vte::ansi::Color`] (as stored on a cell) to RGB.
    ///
    /// `Spec` is already 24-bit. `Named` maps the 0..16 base colors plus
    /// the semantic Foreground/Background/Cursor entries and the Dim/Bright
    /// families; SGR `DIM`/`BOLD` flags are applied by the caller via
    /// [`resolve_fg`]/[`resolve_bg`] before this, so here we only fold the
    /// Named variants the parser itself emits. `Indexed` runs the cube.
    fn resolve(&self, color: Color) -> Rgb {
        match color {
            Color::Spec(rgb) => Rgb::from_vte(rgb),
            Color::Indexed(idx) => self.indexed(idx),
            Color::Named(named) => self.named(named),
        }
    }

    fn named(&self, named: NamedColor) -> Rgb {
        match named {
            NamedColor::Black => self.ansi[0],
            NamedColor::Red => self.ansi[1],
            NamedColor::Green => self.ansi[2],
            NamedColor::Yellow => self.ansi[3],
            NamedColor::Blue => self.ansi[4],
            NamedColor::Magenta => self.ansi[5],
            NamedColor::Cyan => self.ansi[6],
            NamedColor::White => self.ansi[7],
            NamedColor::BrightBlack => self.ansi[8],
            NamedColor::BrightRed => self.ansi[9],
            NamedColor::BrightGreen => self.ansi[10],
            NamedColor::BrightYellow => self.ansi[11],
            NamedColor::BrightBlue => self.ansi[12],
            NamedColor::BrightMagenta => self.ansi[13],
            NamedColor::BrightCyan => self.ansi[14],
            NamedColor::BrightWhite => self.ansi[15],
            NamedColor::Foreground | NamedColor::BrightForeground => self.foreground,
            NamedColor::Background => self.background,
            NamedColor::Cursor => self.cursor,
            NamedColor::DimBlack => dim(self.ansi[0]),
            NamedColor::DimRed => dim(self.ansi[1]),
            NamedColor::DimGreen => dim(self.ansi[2]),
            NamedColor::DimYellow => dim(self.ansi[3]),
            NamedColor::DimBlue => dim(self.ansi[4]),
            NamedColor::DimMagenta => dim(self.ansi[5]),
            NamedColor::DimCyan => dim(self.ansi[6]),
            NamedColor::DimWhite => dim(self.ansi[7]),
            NamedColor::DimForeground => dim(self.foreground),
        }
    }

    /// Resolve a cell's foreground, folding `DIM` (dims the swatch) and
    /// `INVERSE` (swap is done by the caller, here we just produce the fg).
    pub(crate) fn resolve_fg(&self, color: Color, dim_flag: bool) -> Rgb {
        let rgb = self.resolve(color);
        if dim_flag {
            dim(rgb)
        } else {
            rgb
        }
    }

    pub(crate) fn resolve_bg(&self, color: Color) -> Rgb {
        self.resolve(color)
    }
}

/// One channel of the xterm 6x6x6 color cube.
const fn cube_step(n: u8) -> u8 {
    if n == 0 {
        0
    } else {
        55 + n * 40
    }
}

/// SGR `DIM` halves each channel — the standard "faint" rendering.
fn dim(rgb: Rgb) -> Rgb {
    Rgb::new(rgb.r / 2, rgb.g / 2, rgb.b / 2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indexed_first_16_hit_ansi_table() {
        // Spec: indices 0..16 of the 256-palette are exactly the ANSI base
        // colors — index N must equal ansi[N], never the cube.
        let p = TermPalette::one_dark();
        for i in 0..16u8 {
            assert_eq!(p.indexed(i), p.ansi[i as usize]);
        }
    }

    #[test]
    fn indexed_cube_corners() {
        // Spec: the 6x6x6 cube channel steps are 0,95,135,175,215,255.
        // Index 16 is the cube origin (all channels at step 0 => black);
        // index 231 is the cube's far corner (all channels at step 5 => white).
        let p = TermPalette::one_dark();
        assert_eq!(p.indexed(16), Rgb::new(0, 0, 0));
        assert_eq!(p.indexed(231), Rgb::new(255, 255, 255));
        // Pure red corner: r at step 5, g/b at step 0 => index 16 + 5*36.
        assert_eq!(p.indexed(16 + 5 * 36), Rgb::new(255, 0, 0));
    }

    #[test]
    fn indexed_grayscale_ramp() {
        // Spec: indices 232..256 are a 24-step gray ramp from 8 to 238,
        // stepping by 10, with R==G==B at each step.
        let p = TermPalette::one_dark();
        assert_eq!(p.indexed(232), Rgb::new(8, 8, 8));
        assert_eq!(p.indexed(255), Rgb::new(238, 238, 238));
    }

    #[test]
    fn dim_halves_channels() {
        // Spec: SGR DIM produces a faint color — each channel halved.
        assert_eq!(dim(Rgb::new(200, 100, 50)), Rgb::new(100, 50, 25));
    }

    #[test]
    fn named_semantic_colors() {
        // Spec: the semantic Named entries map to the palette's named
        // swatches, not to an ANSI index.
        let p = TermPalette::one_dark();
        assert_eq!(p.named(NamedColor::Foreground), p.foreground);
        assert_eq!(p.named(NamedColor::Background), p.background);
        assert_eq!(p.named(NamedColor::Red), p.ansi[1]);
    }
}
