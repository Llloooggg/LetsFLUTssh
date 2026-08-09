//! Session-manager tree builder.
//!
//! Folds a flat session list into the folder tree the sidebar
//! renders. Living next to the domain types in
//! `lfs_core::sessions` lets `lfs_cli` / `lfs_tauri` consumers
//! reuse the structural logic without reimplementing the sort
//! and folder-prefix rules.
//!
//! The output is intentionally immutable — UI-only state
//! (expansion, focus, selection) lives on the Dart wrapper that
//! reuses these nodes by reference. The Rust side hands back
//! data; the frontend layers presentation on top.

#[derive(Debug, Clone)]
pub struct TreeSession {
    pub id: String,
    pub label: String,
    pub folder: String,
    /// Pre-computed `user@host:port` fallback used when `label`
    /// is empty. Computed Dart-side from the live `Session`
    /// model so this module stays oblivious to `ServerAddress`
    /// formatting rules.
    pub display_name: String,
}

#[derive(Debug, Clone)]
pub struct TreeNode {
    pub name: String,
    pub full_path: String,
    /// `None` for folder nodes; `Some(session_id)` for leaves —
    /// the Dart wrapper looks up the live `Session` from the
    /// caller's flat list by this id.
    pub session_id: Option<String>,
    /// Recursive count of session leaves under this subtree.
    /// Computed during sort so the sidebar's "(N sessions)" copy
    /// doesn't have to re-walk on every paint.
    pub session_count: u32,
    pub children: Vec<TreeNode>,
}

/// Build the forest from a flat session list.
///
/// `empty_folders` materialises folder paths that should appear
/// without any contained session — used when the user has just
/// created an empty folder via the sidebar context menu.
///
/// Sort order: folder nodes come before session leaves at every
/// level; within each kind, sort case-insensitive by `name`.
pub fn build(sessions: Vec<TreeSession>, empty_folders: Vec<String>) -> Vec<TreeNode> {
    let mut root: Vec<TreeNode> = Vec::new();
    for folder_path in &empty_folders {
        ensure_folder_path(&mut root, folder_path);
    }
    for session in &sessions {
        insert_session(&mut root, session);
    }
    sort_tree(&mut root);
    root
}

/// Walk `root` creating each missing folder segment along
/// `folder_path` (slash-separated), returning a mutable handle
/// to the deepest folder's children list so the caller can
/// append a leaf there.
fn ensure_folder_path<'a>(root: &'a mut Vec<TreeNode>, folder_path: &str) -> &'a mut Vec<TreeNode> {
    let mut current: &'a mut Vec<TreeNode> = root;
    let mut current_path = String::new();
    for part in folder_path.split('/') {
        if !current_path.is_empty() {
            current_path.push('/');
        }
        current_path.push_str(part);
        let idx = current
            .iter()
            .position(|n| n.session_id.is_none() && n.name == part);
        let group_idx = match idx {
            Some(i) => i,
            None => {
                current.push(TreeNode {
                    name: part.to_string(),
                    full_path: current_path.clone(),
                    session_id: None,
                    session_count: 0,
                    children: Vec::new(),
                });
                current.len() - 1
            }
        };
        current = &mut current[group_idx].children;
    }
    current
}

fn insert_session(root: &mut Vec<TreeNode>, session: &TreeSession) {
    let name = if session.label.is_empty() {
        session.display_name.clone()
    } else {
        session.label.clone()
    };
    if session.folder.is_empty() {
        // Top-level session — `full_path` matches the Dart contract
        // (`session.fullPath` returns just the label when folder is
        // empty).
        root.push(TreeNode {
            name,
            full_path: session.label.clone(),
            session_id: Some(session.id.clone()),
            session_count: 0,
            children: Vec::new(),
        });
        return;
    }
    let full_path = format!("{}/{}", session.folder, session.label);
    let parent = ensure_folder_path(root, &session.folder);
    parent.push(TreeNode {
        name,
        full_path,
        session_id: Some(session.id.clone()),
        session_count: 0,
        children: Vec::new(),
    });
}

fn sort_tree(nodes: &mut [TreeNode]) {
    nodes.sort_by(
        |a, b| match (a.session_id.is_none(), b.session_id.is_none()) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        },
    );
    for node in nodes.iter_mut() {
        if node.session_id.is_none() {
            sort_tree(&mut node.children);
            node.session_count = count_sessions(node);
        }
    }
}

fn count_sessions(node: &TreeNode) -> u32 {
    if node.session_id.is_some() {
        return 1;
    }
    node.children.iter().map(count_sessions).sum()
}
#[cfg(test)]
#[path = "../tests/unit/session_tree.rs"]
mod tests;
