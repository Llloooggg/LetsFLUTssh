//! Snippet template renderer — the `{{name}}` token machine the
//! Dart-side `Snippet.command` field runs through before the user
//! sees the suggested terminal command.
//!
//! Pure data over a `&str` template + a `&BTreeMap<String, String>`
//! context. No I/O, no allocations beyond the rendered string +
//! the unresolved-tokens list.
//!
//! Token format:
//!
//! * `{{name}}` — substitute the value from `context` for `name`.
//!   Whitespace inside the braces is trimmed (`{{  host  }}` works).
//!   An unknown token leaves its literal text in the output so the
//!   picker dialog can prompt the user, and the name lands in the
//!   `unresolved` list (first-seen order, no duplicates) for the
//!   prompt machine to walk.
//! * `{{{{` — escape, emits a literal `{{` and skips the token
//!   scan over those four bytes. Lets the user write a snippet
//!   that prints `{{not-a-token}}` literally.
//! * `{{}}` — typo, kept literal in the output so the user sees
//!   their own bad input instead of a silent drop.
//! * Unterminated `{{` — the remaining tail copies verbatim.
//!
//! No recursion: a substituted value containing `{{x}}` is taken
//! literally. Same predictability contract as `~/.ssh/config`.

use std::collections::BTreeMap;

/// Result of [`render`].
///
/// `rendered` is the substituted command — known tokens replaced,
/// unknown ones left intact so the picker can prompt the user.
/// `unresolved` lists each unknown token name in **first-seen order
/// without duplicates**, ready to be walked by the prompt dialog.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedSnippet {
    pub rendered: String,
    pub unresolved: Vec<String>,
}

/// Render `template`, substituting `{{name}}` tokens against
/// `context`. See module docs for the exact token grammar.
pub fn render(template: &str, context: &BTreeMap<String, String>) -> RenderedSnippet {
    let mut out = String::with_capacity(template.len());
    let mut unresolved: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    let bytes = template.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        // Escape: `{{{{` → literal `{{`, no token scan over those
        // four bytes.
        if bytes.len() >= i + 4 && &bytes[i..i + 4] == b"{{{{" {
            out.push_str("{{");
            i += 4;
            continue;
        }
        // Token start.
        if bytes.len() > i + 1 && bytes[i] == b'{' && bytes[i + 1] == b'{' {
            match scan_token(bytes, i, context, &mut out, &mut unresolved, &mut seen) {
                Some(next) => i = next,
                // Unterminated `{{` — the tail was copied verbatim.
                None => break,
            }
            continue;
        }
        // Plain byte. UTF-8 boundaries are preserved because we
        // only enter this branch outside of token / escape
        // sequences, and the template was a valid `&str` to start.
        let ch = template[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }

    RenderedSnippet {
        rendered: out,
        unresolved,
    }
}

/// Handle a `{{…}}` token starting at byte `i` (caller has already
/// confirmed `bytes[i..i+2] == "{{"`). Appends the substituted /
/// literal text to `out` and records first-seen unknown names in
/// `unresolved`. Returns the index to resume scanning from, or
/// `None` for an unterminated `{{` (tail copied verbatim, caller
/// stops).
fn scan_token(
    bytes: &[u8],
    i: usize,
    context: &BTreeMap<String, String>,
    out: &mut String,
    unresolved: &mut Vec<String>,
    seen: &mut std::collections::HashSet<String>,
) -> Option<usize> {
    // Find the matching `}}`. Search on byte slice; the
    // template + tokens are ASCII in practice, but we'll
    // recover the original chars via `from_utf8` on the
    // span if a multi-byte codepoint slips into a key.
    let after_open = i + 2;
    let Some(close_rel) = find_close(&bytes[after_open..]) else {
        // Unterminated `{{` — copy the remaining tail
        // verbatim. Matches the Dart contract.
        out.push_str(std::str::from_utf8(&bytes[i..]).unwrap_or(""));
        return None;
    };
    let close = after_open + close_rel;
    let raw = std::str::from_utf8(&bytes[after_open..close]).unwrap_or("");
    let name = raw.trim();
    if name.is_empty() {
        // `{{}}` is a typo, not a token. Keep it
        // literal so the user sees their own bad input.
        out.push_str(std::str::from_utf8(&bytes[i..close + 2]).unwrap_or_default());
        return Some(close + 2);
    }
    if let Some(value) = context.get(name) {
        out.push_str(value);
    } else {
        // Leave the token text in the output so the
        // prompt dialog can substitute it after the user
        // fills the value.
        out.push_str(std::str::from_utf8(&bytes[i..close + 2]).unwrap_or_default());
        if seen.insert(name.to_string()) {
            unresolved.push(name.to_string());
        }
    }
    Some(close + 2)
}

/// Substitute `values` for `{{name}}` tokens left behind by
/// [`render`]. Used by the picker after the prompt dialog collects
/// values for each unresolved token; honours the same `{{{{`
/// escape and "no recursion" rules as the first pass.
#[must_use]
pub fn fill_unresolved(partially_rendered: &str, values: &BTreeMap<String, String>) -> String {
    render(partially_rendered, values).rendered
}

fn find_close(haystack: &[u8]) -> Option<usize> {
    if haystack.len() < 2 {
        return None;
    }
    let mut i = 0;
    while i + 1 < haystack.len() {
        if haystack[i] == b'}' && haystack[i + 1] == b'}' {
            return Some(i);
        }
        i += 1;
    }
    None
}
#[cfg(test)]
#[path = "../tests/unit/snippet_template.rs"]
mod tests;
