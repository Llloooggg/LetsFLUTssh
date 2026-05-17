//! FRB adapter for [`lfs_core::clipboard::FileBrowserClipboard`].
//!
//! Thin pass-through — every endpoint hands the call to the
//! process-singleton clipboard on [`AppState::file_clipboard`].
//! Dart calls into these from `_FileBrowserTabState`'s Ctrl+C /
//! Ctrl+V / dispose paths so the buffer survives tab teardown
//! and is reachable from a sibling tab — neither of which were
//! possible with the prior Dart-side per-tab state.

use lfs_core::clipboard::{ClipboardEntry, ClipboardSlot};

/// FRB mirror of [`lfs_core::clipboard::ClipboardEntry`]. Field set
/// matches verbatim — the four columns the paste path needs.
#[derive(Debug, Clone)]
pub struct DbClipboardEntry {
    pub name: String,
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
}

impl From<DbClipboardEntry> for ClipboardEntry {
    fn from(e: DbClipboardEntry) -> Self {
        Self {
            name: e.name,
            path: e.path,
            size: e.size,
            is_dir: e.is_dir,
        }
    }
}

impl From<ClipboardEntry> for DbClipboardEntry {
    fn from(e: ClipboardEntry) -> Self {
        Self {
            name: e.name,
            path: e.path,
            size: e.size,
            is_dir: e.is_dir,
        }
    }
}

/// Store `entries` in the process-singleton clipboard under
/// `tab_id` + `source_pane`. Replaces any prior slot. Empty
/// `entries` are accepted (an "explicit clear via copy" — the
/// `is_set` probe still reports false since the slot's entry
/// list is empty per [`FileBrowserClipboard::is_set`]'s contract).
pub fn file_clipboard_put(tab_id: String, source_pane: String, entries: Vec<DbClipboardEntry>) {
    let slot = ClipboardSlot {
        source_tab_id: tab_id,
        source_pane,
        entries: entries.into_iter().map(ClipboardEntry::from).collect(),
    };
    lfs_core::app::instance().file_clipboard.put(slot);
}

/// Take + clear the clipboard slot when it was put by
/// `expected_tab_id` + `expected_source_pane`. Returns `None` for
/// an empty slot or a mismatched source. See
/// [`FileBrowserClipboard::take_for_paste`] for the full
/// "paste-clears" rationale.
pub fn file_clipboard_take(
    expected_tab_id: String,
    expected_source_pane: String,
) -> Option<Vec<DbClipboardEntry>> {
    lfs_core::app::instance()
        .file_clipboard
        .take_for_paste(&expected_tab_id, &expected_source_pane)
        .map(|entries| entries.into_iter().map(DbClipboardEntry::from).collect())
}

/// Drop the slot regardless of source. Hosts call this from their
/// own `dispose` so a closing tab can't leave entries pointing at
/// a file system the user can no longer paste against.
pub fn file_clipboard_clear() {
    lfs_core::app::instance().file_clipboard.clear();
}

/// Whether the clipboard currently holds a non-empty slot. Sync —
/// the UI's paste-enabled gate reads this on every menu render and
/// shouldn't pay an FRB async hop.
#[flutter_rust_bridge::frb(sync)]
pub fn file_clipboard_is_set() -> bool {
    lfs_core::app::instance().file_clipboard.is_set()
}

/// Source-tab id of the currently held slot (or `None` for empty).
/// The file-browser tab uses this to decide whether to render its
/// own paste menu item — paste is intentionally scoped to within a
/// single tab.
#[flutter_rust_bridge::frb(sync)]
pub fn file_clipboard_source_tab_id() -> Option<String> {
    lfs_core::app::instance().file_clipboard.source_tab_id()
}
