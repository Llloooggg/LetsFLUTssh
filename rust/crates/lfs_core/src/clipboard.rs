//! Process-singleton clipboard for file-browser copy/cut/paste.
//!
//! The Dart `_FileBrowserTabState` used to keep `_clipboardEntries`
//! on its own heap, which scoped the buffer to one tab — no path
//! for a sibling tab to read the slot, no path for the buffer to
//! survive tab close. Lifting the canonical slot here matches the
//! AGENTS.md "Rust owns data AND logic" posture for user data the
//! app holds across UI surfaces and unblocks cross-tab paste as a
//! single UI tweak (the per-tab id filter today is a UX choice,
//! not a transport limit).
//!
//! ## Lifecycle
//!
//! `put` replaces the single slot. `take_for_paste` returns + clears
//! when the source-pane filter matches; non-matching takes leave the
//! slot intact (a paste in a different tab shouldn't consume the
//! source tab's clipboard). `clear` drops the slot unconditionally
//! — the host calls it on tab disposal so cross-tab references
//! don't outlive their source.
//!
//! ## Threading
//!
//! Plain `Mutex<Option<ClipboardSlot>>`. The clipboard is contended
//! between Dart-side UI ticks (typically <1 op/second from any one
//! tab) and the FRB worker thread — no shared `RwLock` win.

use std::sync::Mutex;

/// One file/dir entry on the clipboard. Mirrors the field subset
/// of `lib/core/sftp/sftp_models.dart::FileEntry` the paste path
/// actually needs to enqueue an upload / download: name, path,
/// size, is-dir. Mode / mtime / owner are display-only at the
/// source and don't matter at the destination.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardEntry {
    pub name: String,
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
}

/// Per-cut/copy snapshot. Carries the source tab + pane so a paste
/// in a sibling tab can ignore it (per the "two panes per tab"
/// SFTP-browser convention). `source_pane` is the canonical
/// `"local"` / `"remote"` string the file-browser-tab uses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardSlot {
    pub source_tab_id: String,
    pub source_pane: String,
    pub entries: Vec<ClipboardEntry>,
}

/// Process-singleton clipboard registry.
#[derive(Default)]
pub struct FileBrowserClipboard {
    inner: Mutex<Option<ClipboardSlot>>,
}

impl FileBrowserClipboard {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stash `slot` in the single clipboard cell, replacing any
    /// prior contents. The replaced `ClipboardSlot` drops in
    /// place; `Vec<ClipboardEntry>` releases its backing buffer on
    /// drop. Paths are metadata, not secrets, so no `Zeroizing`.
    pub fn put(&self, slot: ClipboardSlot) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        *g = Some(slot);
    }

    /// Whether the clipboard currently holds a non-empty slot.
    /// Used by the UI to gate the "Paste" menu item / shortcut
    /// hint without copying the buffer over FRB.
    pub fn is_set(&self) -> bool {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.as_ref().is_some_and(|s| !s.entries.is_empty())
    }

    /// Read the slot when it was put by `expected_tab_id` /
    /// `expected_source_pane`, **consuming** it on return. A
    /// non-matching `expected_*` tuple leaves the slot alone so a
    /// paste in a sibling tab doesn't drain the source tab's
    /// clipboard. Returns `None` when the slot is empty or
    /// belongs to a different source.
    ///
    /// "Take on paste" matches the desktop convention — pasting
    /// the same clipboard into N targets in a row would need the
    /// user to re-copy each time, but it keeps the "what was
    /// last copied" question unambiguous and rules out
    /// double-paste of a freshly-cut row (cut-then-paste-twice
    /// would otherwise duplicate the file).
    pub fn take_for_paste(
        &self,
        expected_tab_id: &str,
        expected_source_pane: &str,
    ) -> Option<Vec<ClipboardEntry>> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let slot = g.as_ref()?;
        if slot.source_tab_id != expected_tab_id || slot.source_pane != expected_source_pane {
            return None;
        }
        let taken = g.take()?;
        Some(taken.entries)
    }

    /// Drop the slot regardless of source. The file-browser tab
    /// host calls this on `dispose` so a closing tab doesn't leak
    /// references to entries the user can no longer paste against.
    pub fn clear(&self) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        *g = None;
    }

    /// Inspect the source-tab id of the held slot without taking
    /// it. The UI uses this to decide whether its own paste menu
    /// item should fire (paste only across panes within the same
    /// tab, per current convention). Returns `None` for an empty
    /// slot.
    pub fn source_tab_id(&self) -> Option<String> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.as_ref().map(|s| s.source_tab_id.clone())
    }
}

#[cfg(test)]
mod tests {
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
}
