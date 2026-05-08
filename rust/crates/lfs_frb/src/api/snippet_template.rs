//! FRB adapter for `lfs_core::snippet_template`.
//!
//! Sync — the renderer is a single linear scan over the template
//! string + a hashmap lookup per token. Even a long bash one-liner
//! with a dozen tokens runs well under a millisecond. The Dart
//! caller (`SnippetPicker`) calls this from the build phase of a
//! widget that previews the rendered command, so async-jump
//! overhead would hurt UI snappiness without buying anything.

use std::collections::BTreeMap;

use lfs_core::snippet_template;

/// Result of [`snippet_template_render`].
#[derive(Debug, Clone)]
pub struct DbRenderedSnippet {
    pub rendered: String,
    /// Unknown token names in first-seen order, no duplicates.
    pub unresolved: Vec<String>,
}

/// Render the snippet command, substituting `{{name}}` tokens
/// against [`context`].
#[flutter_rust_bridge::frb(sync)]
pub fn snippet_template_render(
    template: String,
    context: Vec<(String, String)>,
) -> DbRenderedSnippet {
    let map: BTreeMap<String, String> = context.into_iter().collect();
    let r = snippet_template::render(&template, &map);
    DbRenderedSnippet {
        rendered: r.rendered,
        unresolved: r.unresolved,
    }
}

/// Substitute [`values`] for `{{name}}` tokens left behind by
/// [`snippet_template_render`]. Used by the picker after the
/// prompt dialog collects the user's input for each unresolved
/// token.
#[flutter_rust_bridge::frb(sync)]
pub fn snippet_template_fill_unresolved(
    partially_rendered: String,
    values: Vec<(String, String)>,
) -> String {
    let map: BTreeMap<String, String> = values.into_iter().collect();
    snippet_template::fill_unresolved(&partially_rendered, &map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_substitutes_known_tokens() {
        let r = snippet_template_render(
            "ssh {{user}}@{{host}}".into(),
            vec![
                ("user".into(), "alice".into()),
                ("host".into(), "edge".into()),
            ],
        );
        assert_eq!(r.rendered, "ssh alice@edge");
        assert!(r.unresolved.is_empty());
    }

    #[test]
    fn render_collects_unresolved_tokens_first_seen_order() {
        // The picker dialog uses `unresolved` to drive the
        // user-prompt sequence; first-seen ordering keeps
        // variables shown in the order they appear in the template
        // even when the same token appears twice.
        let r = snippet_template_render("{{port}} | {{host}} | {{port}}".into(), vec![]);
        assert!(r.rendered.contains("{{port}}"));
        assert!(r.rendered.contains("{{host}}"));
        assert_eq!(r.unresolved.len(), 2);
        assert_eq!(r.unresolved[0], "port");
        assert_eq!(r.unresolved[1], "host");
    }

    #[test]
    fn render_passes_template_without_tokens_unchanged() {
        let r = snippet_template_render("ls -la /tmp".into(), vec![]);
        assert_eq!(r.rendered, "ls -la /tmp");
        assert!(r.unresolved.is_empty());
    }

    #[test]
    fn fill_unresolved_replaces_remaining_tokens() {
        let r = snippet_template_fill_unresolved(
            "ssh {{user}}@edge".into(),
            vec![("user".into(), "deploy".into())],
        );
        assert_eq!(r, "ssh deploy@edge");
    }

    #[test]
    fn fill_unresolved_passes_through_untouched_text() {
        // Tokens not present in `values` survive — the caller can
        // round-trip the same string back through `render` later.
        let r = snippet_template_fill_unresolved(
            "ssh {{user}}@{{host}}".into(),
            vec![("user".into(), "deploy".into())],
        );
        assert!(r.contains("deploy"));
        assert!(r.contains("{{host}}"));
    }
}
