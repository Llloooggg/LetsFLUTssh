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

#[cfg(test)]
mod tests {
    use super::*;

    fn sess(id: &str, label: &str, folder: &str) -> DbSessionTreeInput {
        DbSessionTreeInput {
            id: id.into(),
            label: label.into(),
            folder: folder.into(),
            display_name: label.into(),
        }
    }

    #[test]
    fn empty_input_returns_empty_forest() {
        let nodes = session_tree_build(vec![], vec![]);
        assert!(nodes.is_empty());
    }

    #[test]
    fn root_only_sessions_appear_at_top_level() {
        let nodes =
            session_tree_build(vec![sess("a", "Alpha", ""), sess("b", "Bravo", "")], vec![]);
        // Root-level sessions surface as session-leaf nodes (one per
        // session, no children, session_id populated).
        assert_eq!(nodes.len(), 2);
        for n in &nodes {
            assert!(n.session_id.is_some());
            assert!(n.children.is_empty());
        }
    }

    #[test]
    fn nested_folder_sessions_build_a_two_level_tree() {
        let nodes = session_tree_build(
            vec![
                sess("a", "Alpha", "production"),
                sess("b", "Bravo", "production/edge"),
            ],
            vec![],
        );
        // Top-level: one folder node "production" with a leaf
        // (Alpha) + one folder child (edge) holding the Bravo leaf.
        let prod = nodes
            .iter()
            .find(|n| n.name == "production")
            .expect("production node");
        assert!(prod.session_id.is_none());
        assert!(prod.session_count >= 2);
        let edge = prod
            .children
            .iter()
            .find(|c| c.name == "edge")
            .expect("edge node");
        assert!(edge.children.iter().any(|c| c.session_id.is_some()));
    }

    #[test]
    fn empty_folder_paths_materialise_even_without_sessions() {
        // The Dart caller hands `empty_folders` for folders with no
        // sessions inside; the tree must still surface them so the
        // user can navigate / drop into the empty folder.
        let nodes = session_tree_build(vec![], vec!["empty-bucket".into()]);
        assert!(nodes.iter().any(|n| n.name == "empty-bucket"));
    }
}
