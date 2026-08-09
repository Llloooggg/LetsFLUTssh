/// Unit tests extracted from session_tree.rs
/// Declared via `#[path] mod tests;` in the source file.
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
