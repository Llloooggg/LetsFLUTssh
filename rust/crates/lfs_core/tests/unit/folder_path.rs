/// Unit tests extracted from folder_path.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn row(id: &str, name: &str, parent: Option<&str>) -> FolderRow {
    FolderRow {
        id: id.to_string(),
        name: name.to_string(),
        parent_id: parent.map(|s| s.to_string()),
        sort_order: 0,
        collapsed: false,
        created_at_ms: 0,
    }
}

fn map_of(rows: Vec<FolderRow>) -> BTreeMap<String, FolderRow> {
    rows.into_iter().map(|r| (r.id.clone(), r)).collect()
}

#[test]
fn build_path_returns_empty_for_empty_id() {
    let folders = map_of(vec![]);
    assert_eq!(build_folder_path("", &folders), "");
}

#[test]
fn build_path_walks_parent_chain() {
    let folders = map_of(vec![
        row("a", "Production", None),
        row("b", "EU", Some("a")),
        row("c", "web", Some("b")),
    ]);
    assert_eq!(build_folder_path("c", &folders), "Production/EU/web");
    assert_eq!(build_folder_path("b", &folders), "Production/EU");
    assert_eq!(build_folder_path("a", &folders), "Production");
}

#[test]
fn build_path_breaks_a_parent_cycle_instead_of_looping() {
    // Cyclic parent_id chain (hand-edited / pre-fix DB): a -> b,
    // b -> a. The walk must terminate at a "(cycle)/…" marker
    // rather than loop forever / OOM growing the path.
    let folders = map_of(vec![
        row("a", "Alpha", Some("b")),
        row("b", "Bravo", Some("a")),
    ]);
    let path = build_folder_path("a", &folders);
    assert!(
        path.starts_with("(cycle)/"),
        "expected a cycle marker, got {path:?}"
    );
}

#[test]
fn build_path_breaks_a_self_referential_cycle() {
    let folders = map_of(vec![row("a", "Alpha", Some("a"))]);
    let path = build_folder_path("a", &folders);
    assert!(
        path.starts_with("(cycle)/"),
        "expected a cycle marker, got {path:?}"
    );
}

#[test]
fn build_path_marks_orphan_with_prefix() {
    // `c` references a parent `b` that was deleted while `a`
    // was kept — surface the inconsistency instead of losing
    // the leaf name silently.
    let folders = map_of(vec![
        row("a", "Production", None),
        row("c", "web", Some("b")),
    ]);
    assert_eq!(build_folder_path("c", &folders), "(orphaned)/web");
}

#[test]
fn build_path_returns_orphan_marker_for_missing_root() {
    let folders = map_of(vec![]);
    assert_eq!(build_folder_path("missing", &folders), "(orphaned)/");
}

#[test]
fn find_id_by_path_returns_none_for_empty() {
    let folders = map_of(vec![row("a", "Production", None)]);
    assert!(find_folder_id_by_path("", &folders).is_none());
}

#[test]
fn find_id_by_path_matches_full_path() {
    let folders = map_of(vec![
        row("a", "Production", None),
        row("b", "EU", Some("a")),
        row("c", "web", Some("b")),
    ]);
    assert_eq!(
        find_folder_id_by_path("Production/EU/web", &folders),
        Some("c".to_string())
    );
    assert_eq!(
        find_folder_id_by_path("Production", &folders),
        Some("a".to_string())
    );
}

#[test]
fn find_id_by_path_returns_none_for_unknown() {
    let folders = map_of(vec![row("a", "Production", None)]);
    assert!(find_folder_id_by_path("Production/EU", &folders).is_none());
}

#[test]
fn all_paths_enumerates_every_node() {
    let folders = map_of(vec![
        row("a", "Production", None),
        row("b", "EU", Some("a")),
        row("c", "web", Some("b")),
        row("d", "Staging", None),
    ]);
    let paths = all_folder_paths(&folders);
    assert_eq!(
        paths,
        vec![
            "Production".to_string(),
            "Production/EU".to_string(),
            "Production/EU/web".to_string(),
            "Staging".to_string(),
        ]
    );
}

#[test]
fn rename_cascade_renames_exact_match() {
    let paths = vec!["Production".to_string(), "Staging".to_string()];
    let out = rename_paths_cascade(&paths, "Production", "Prod");
    assert_eq!(out, vec!["Prod".to_string(), "Staging".to_string()]);
}

#[test]
fn rename_cascade_renames_children_under_prefix() {
    let paths = vec![
        "Production".to_string(),
        "Production/EU".to_string(),
        "Production/EU/web".to_string(),
        "Staging".to_string(),
    ];
    let out = rename_paths_cascade(&paths, "Production", "Prod");
    assert_eq!(
        out,
        vec![
            "Prod".to_string(),
            "Prod/EU".to_string(),
            "Prod/EU/web".to_string(),
            "Staging".to_string(),
        ]
    );
}

#[test]
fn rename_cascade_skips_paths_with_matching_prefix_but_different_name() {
    // "ProductionExtra" must NOT be renamed when the user
    // renames "Production" — only exact matches and entries
    // under `Production/` (note the slash) move.
    let paths = vec!["Production".to_string(), "ProductionExtra".to_string()];
    let out = rename_paths_cascade(&paths, "Production", "Prod");
    assert_eq!(out, vec!["Prod".to_string(), "ProductionExtra".to_string()]);
}

#[test]
fn rename_cascade_no_op_for_identical_paths() {
    let paths = vec!["A".to_string(), "B".to_string()];
    let out = rename_paths_cascade(&paths, "X", "X");
    assert_eq!(out, vec!["A".to_string(), "B".to_string()]);
}

#[test]
fn rename_cascade_no_op_for_empty_old_or_new() {
    let paths = vec!["A".to_string(), "B".to_string()];
    assert_eq!(rename_paths_cascade(&paths, "", "Prod"), vec!["A", "B"]);
    assert_eq!(rename_paths_cascade(&paths, "A", ""), vec!["A", "B"]);
}

fn collapsed_row(id: &str, name: &str, parent: Option<&str>) -> FolderRow {
    FolderRow {
        id: id.to_string(),
        name: name.to_string(),
        parent_id: parent.map(|s| s.to_string()),
        sort_order: 0,
        collapsed: true,
        created_at_ms: 0,
    }
}

#[test]
fn empty_folders_skips_folders_with_sessions() {
    let folders = map_of(vec![
        row("a", "Production", None),
        row("b", "EU", Some("a")),
        row("c", "Staging", None),
    ]);
    let used: std::collections::HashSet<String> = ["a".into()].into();
    let empty = derive_empty_folders(&folders, &used);
    // 'a' has a session — exclude. 'b' (Production/EU) and 'c'
    // (Staging) are empty.
    assert_eq!(
        empty,
        vec!["Production/EU".to_string(), "Staging".to_string()]
    );
}

#[test]
fn empty_folders_returns_every_folder_when_no_session_present() {
    let folders = map_of(vec![
        row("a", "Production", None),
        row("b", "Staging", None),
    ]);
    let used: std::collections::HashSet<String> = std::collections::HashSet::new();
    let empty = derive_empty_folders(&folders, &used);
    assert_eq!(empty, vec!["Production".to_string(), "Staging".to_string()]);
}

#[test]
fn empty_folders_skips_orphan_partial_paths_when_root_present() {
    // An orphan folder still gets a path entry — the UI shows
    // the marker — but only when it actually resolves to a
    // non-empty path. A row with no name + no parent would
    // resolve to empty and we drop it.
    let folders = map_of(vec![row("a", "Production", None)]);
    let used: std::collections::HashSet<String> = std::collections::HashSet::new();
    let empty = derive_empty_folders(&folders, &used);
    assert_eq!(empty, vec!["Production".to_string()]);
}

#[test]
fn collapsed_folders_returns_only_collapsed_rows() {
    let folders = map_of(vec![
        row("a", "Production", None),
        collapsed_row("b", "EU", Some("a")),
        collapsed_row("c", "Staging", None),
    ]);
    let collapsed = derive_collapsed_folders(&folders);
    assert_eq!(
        collapsed,
        vec!["Production/EU".to_string(), "Staging".to_string()]
    );
}

#[test]
fn collapsed_folders_returns_empty_when_nothing_collapsed() {
    let folders = map_of(vec![row("a", "Production", None)]);
    assert!(derive_collapsed_folders(&folders).is_empty());
}
