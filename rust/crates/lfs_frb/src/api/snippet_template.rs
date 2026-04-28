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
