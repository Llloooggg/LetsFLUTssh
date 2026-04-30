//! FRB adapter for `lfs_core::session_tree`. The frontend hands
//! over a flat list of sessions plus the empty-folder paths that
//! must materialise without children, and gets back the sorted
//! folder forest. Pure data — UI-only state (expansion, focus)
//! is layered on top by the Dart wrapper.

#[derive(Debug, Clone)]
pub struct DbSessionTreeInput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub display_name: String,
}

#[derive(Debug, Clone)]
pub struct DbSessionTreeNode {
    pub name: String,
    pub full_path: String,
    pub session_id: Option<String>,
    pub session_count: u32,
    pub children: Vec<DbSessionTreeNode>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_tree_build(
    sessions: Vec<DbSessionTreeInput>,
    empty_folders: Vec<String>,
) -> Vec<DbSessionTreeNode> {
    let core_sessions: Vec<lfs_core::session_tree::TreeSession> = sessions
        .into_iter()
        .map(|s| lfs_core::session_tree::TreeSession {
            id: s.id,
            label: s.label,
            folder: s.folder,
            display_name: s.display_name,
        })
        .collect();
    lfs_core::session_tree::build(core_sessions, empty_folders)
        .into_iter()
        .map(into_db_node)
        .collect()
}

fn into_db_node(node: lfs_core::session_tree::TreeNode) -> DbSessionTreeNode {
    DbSessionTreeNode {
        name: node.name,
        full_path: node.full_path,
        session_id: node.session_id,
        session_count: node.session_count,
        children: node.children.into_iter().map(into_db_node).collect(),
    }
}
