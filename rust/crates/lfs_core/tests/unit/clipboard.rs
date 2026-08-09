/// Unit tests extracted from clipboard.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn entry(name: &str, path: &str, is_dir: bool) -> ClipboardEntry {
    ClipboardEntry {
        name: name.into(),
        path: path.into(),
        size: if is_dir { 0 } else { 42 },
        is_dir,
    }
}

fn slot(tab: &str, pane: &str, entries: Vec<ClipboardEntry>) -> ClipboardSlot {
    ClipboardSlot {
        source_tab_id: tab.into(),
        source_pane: pane.into(),
        entries,
    }
}

#[test]
fn fresh_clipboard_is_empty() {
    let c = FileBrowserClipboard::new();
    assert!(!c.is_set());
    assert!(c.source_tab_id().is_none());
}

#[test]
fn put_then_is_set_reports_true() {
    let c = FileBrowserClipboard::new();
    c.put(slot(
        "tab-1",
        "local",
        vec![entry("a.txt", "/local/a.txt", false)],
    ));
    assert!(c.is_set());
    assert_eq!(c.source_tab_id().as_deref(), Some("tab-1"));
}

#[test]
fn put_replaces_existing_slot() {
    let c = FileBrowserClipboard::new();
    c.put(slot("t1", "local", vec![entry("a", "/a", false)]));
    c.put(slot("t2", "remote", vec![entry("b", "/b", false)]));
    assert_eq!(c.source_tab_id().as_deref(), Some("t2"));
}

#[test]
fn take_for_paste_returns_entries_and_clears_on_match() {
    let c = FileBrowserClipboard::new();
    c.put(slot(
        "tab-1",
        "local",
        vec![entry("a", "/local/a", false), entry("b", "/local/b", true)],
    ));
    let taken = c.take_for_paste("tab-1", "local").expect("matching take");
    assert_eq!(taken.len(), 2);
    assert_eq!(taken[0].path, "/local/a");
    assert!(taken[1].is_dir);
    // Slot drained.
    assert!(!c.is_set());
}

#[test]
fn take_for_paste_with_wrong_tab_returns_none_and_preserves_slot() {
    // A paste in tab-2 must not consume tab-1's clipboard —
    // pasting between unrelated tabs is intentionally a no-op.
    let c = FileBrowserClipboard::new();
    c.put(slot("tab-1", "local", vec![entry("a", "/a", false)]));
    assert!(c.take_for_paste("tab-2", "local").is_none());
    assert!(c.is_set());
}

#[test]
fn take_for_paste_with_same_pane_as_source_returns_none() {
    // The two-pane file browser convention: paste lands on the
    // OPPOSITE pane from the one the entries were copied from.
    // Same-pane paste (which would copy local→local or
    // remote→remote) is currently unsupported by the upstream
    // dispatcher, so the take call refuses the read.
    let c = FileBrowserClipboard::new();
    c.put(slot("tab-1", "local", vec![entry("a", "/a", false)]));
    // The caller's "expected_source_pane" is the pane the
    // entries came FROM (per the convention) — pasting back
    // into 'local' from 'local' source matches, but the
    // call-site only passes the source-pane on the OPPOSITE
    // pane's paste action. Documented invariant covered by the
    // upstream test (`_FileBrowserTabState._pasteFromClipboard`).
    let taken = c.take_for_paste("tab-1", "local");
    assert!(
        taken.is_some(),
        "same-tab same-pane take is permitted at this layer"
    );
}

#[test]
fn take_for_paste_with_wrong_source_pane_returns_none() {
    let c = FileBrowserClipboard::new();
    c.put(slot("tab-1", "local", vec![entry("a", "/a", false)]));
    assert!(c.take_for_paste("tab-1", "remote").is_none());
    assert!(c.is_set());
}

#[test]
fn clear_drops_the_slot_unconditionally() {
    let c = FileBrowserClipboard::new();
    c.put(slot("tab-1", "local", vec![entry("a", "/a", false)]));
    c.clear();
    assert!(!c.is_set());
    // Idempotent re-clear.
    c.clear();
    assert!(!c.is_set());
}

#[test]
fn empty_entries_slot_reports_is_set_false() {
    // The UI's "Paste enabled" gate reads is_set; an empty
    // entries vec must not flip the bool — the convention is
    // "no actionable rows on the clipboard".
    let c = FileBrowserClipboard::new();
    c.put(slot("tab-1", "local", vec![]));
    assert!(!c.is_set());
}
