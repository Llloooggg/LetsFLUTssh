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
#[path = "../tests/unit/clipboard.rs"]
mod tests;
