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
mod tests {
    use super::*;

    fn s(id: &str, label: &str, folder: &str) -> TreeSession {
        TreeSession {
            id: id.to_string(),
            label: label.to_string(),
            folder: folder.to_string(),
            display_name: format!("{}@host:22", id),
        }
    }

    #[test]
    fn empty_inputs_produce_empty_tree() {
        assert!(build(vec![], vec![]).is_empty());
    }

    #[test]
    fn top_level_sessions_sort_alphabetically() {
        let tree = build(vec![s("1", "B", ""), s("2", "A", "")], vec![]);
        assert_eq!(tree.len(), 2);
        assert_eq!(tree[0].name, "A");
        assert_eq!(tree[1].name, "B");
        assert!(tree[0].session_id.is_some());
    }

    #[test]
    fn nested_folders_collapse_shared_prefix() {
        let tree = build(
            vec![
                s("1", "nginx", "Production/Web"),
                s("2", "db", "Production/DB"),
            ],
            vec![],
        );
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].name, "Production");
        assert!(tree[0].session_id.is_none());
        assert_eq!(tree[0].children.len(), 2);
        assert_eq!(tree[0].children[0].name, "DB");
        assert_eq!(tree[0].children[1].name, "Web");
        assert_eq!(tree[0].children[0].children[0].name, "db");
        assert_eq!(tree[0].children[1].children[0].name, "nginx");
    }

    #[test]
    fn folders_sort_before_sessions_at_same_level() {
        let tree = build(
            vec![s("1", "standalone", ""), s("2", "grouped", "Servers")],
            vec![],
        );
        assert_eq!(tree.len(), 2);
        assert!(tree[0].session_id.is_none());
        assert_eq!(tree[0].name, "Servers");
        assert!(tree[1].session_id.is_some());
        assert_eq!(tree[1].name, "standalone");
    }

    #[test]
    fn shared_folder_aggregates_children() {
        let tree = build(vec![s("1", "web1", "Prod"), s("2", "web2", "Prod")], vec![]);
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].children.len(), 2);
        assert_eq!(tree[0].children[0].name, "web1");
        assert_eq!(tree[0].children[1].name, "web2");
    }

    #[test]
    fn deeply_nested_folder_chain_is_preserved() {
        let tree = build(vec![s("1", "server", "A/B/C")], vec![]);
        assert_eq!(tree[0].name, "A");
        assert_eq!(tree[0].children[0].name, "B");
        assert_eq!(tree[0].children[0].children[0].name, "C");
        assert_eq!(tree[0].children[0].children[0].children[0].name, "server");
    }

    #[test]
    fn empty_label_falls_back_to_display_name() {
        let tree = build(vec![s("xyz", "", "")], vec![]);
        assert_eq!(tree[0].name, "xyz@host:22");
    }

    #[test]
    fn empty_folders_materialise_without_sessions() {
        let tree = build(vec![], vec!["Drafts".to_string()]);
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].name, "Drafts");
        assert!(tree[0].session_id.is_none());
        assert_eq!(tree[0].session_count, 0);
    }

    #[test]
    fn session_count_aggregates_recursively() {
        let tree = build(
            vec![
                s("1", "a", "Top"),
                s("2", "b", "Top/Mid"),
                s("3", "c", "Top/Mid/Bot"),
            ],
            vec![],
        );
        let top = &tree[0];
        assert_eq!(top.session_count, 3);
        // children: one folder ("Mid") and one session ("a")
        let mid = top.children.iter().find(|n| n.name == "Mid").unwrap();
        assert_eq!(mid.session_count, 2);
        let bot = mid.children.iter().find(|n| n.name == "Bot").unwrap();
        assert_eq!(bot.session_count, 1);
    }

    #[test]
    fn case_insensitive_sort() {
        let tree = build(
            vec![
                s("1", "banana", ""),
                s("2", "Apple", ""),
                s("3", "cherry", ""),
            ],
            vec![],
        );
        let names: Vec<&str> = tree.iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, vec!["Apple", "banana", "cherry"]);
    }

    #[test]
    fn full_path_reflects_folder_prefix() {
        let tree = build(vec![s("1", "leaf", "A/B")], vec![]);
        let a = &tree[0];
        assert_eq!(a.full_path, "A");
        let b = &a.children[0];
        assert_eq!(b.full_path, "A/B");
        let leaf = &b.children[0];
        assert_eq!(leaf.full_path, "A/B/leaf");
        assert_eq!(leaf.session_id.as_deref(), Some("1"));
    }
}
