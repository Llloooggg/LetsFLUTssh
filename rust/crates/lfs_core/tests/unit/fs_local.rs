/// Unit tests extracted from fs/local.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn temp_dir(label: &str) -> std::path::PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_local_fs_{label}_{pid}_{nanos}"));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

#[tokio::test]
async fn list_returns_directory_contents() {
    let dir = temp_dir("list");
    std::fs::write(dir.join("a.txt"), b"hello").unwrap();
    std::fs::write(dir.join("b.txt"), b"world!").unwrap();
    std::fs::create_dir(dir.join("sub")).unwrap();
    let mut entries = list(dir.to_string_lossy().into_owned()).await.unwrap();
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    assert_eq!(entries.len(), 3);
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(names, vec!["a.txt", "b.txt", "sub"]);
    let a = &entries[0];
    assert_eq!(a.size, 5);
    assert!(!a.is_dir);
    let s = &entries[2];
    assert!(s.is_dir);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn list_missing_directory_errors() {
    let result = list("/path/that/does/not/exist/lfs_test".to_string()).await;
    assert!(result.is_err());
}

#[tokio::test]
async fn mkdir_creates_nested_path() {
    let dir = temp_dir("mkdir");
    let nested = dir.join("a/b/c");
    mkdir(nested.to_string_lossy().into_owned()).await.unwrap();
    assert!(nested.is_dir());
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn remove_handles_file_and_directory() {
    let dir = temp_dir("remove");
    let f = dir.join("file.txt");
    std::fs::write(&f, b"x").unwrap();
    let sub = dir.join("sub");
    std::fs::create_dir(&sub).unwrap();
    std::fs::write(sub.join("inner"), b"y").unwrap();

    remove(f.to_string_lossy().into_owned()).await.unwrap();
    assert!(!f.exists());

    remove(sub.to_string_lossy().into_owned()).await.unwrap();
    assert!(!sub.exists());

    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn rename_moves_path() {
    let dir = temp_dir("rename");
    let from = dir.join("from.txt");
    let to = dir.join("to.txt");
    std::fs::write(&from, b"x").unwrap();
    rename(
        from.to_string_lossy().into_owned(),
        to.to_string_lossy().into_owned(),
    )
    .await
    .unwrap();
    assert!(!from.exists());
    assert!(to.exists());
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn dir_size_sums_recursively() {
    let dir = temp_dir("dir_size");
    std::fs::write(dir.join("top.txt"), b"12345").unwrap();
    let sub = dir.join("nested");
    std::fs::create_dir_all(&sub).unwrap();
    std::fs::write(sub.join("inner.bin"), b"67890ab").unwrap();
    let total = dir_size(dir.to_string_lossy().into_owned()).await.unwrap();
    assert_eq!(total, 5 + 7);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn dir_size_missing_directory_returns_zero() {
    let total = dir_size("/this/does/not/exist/lfs_test".to_string())
        .await
        .unwrap();
    assert_eq!(total, 0);
}

#[tokio::test]
async fn list_directories_returns_only_dirs() {
    let dir = temp_dir("list_dirs_only");
    std::fs::create_dir(dir.join("sub")).unwrap();
    std::fs::write(dir.join("file.txt"), b"x").unwrap();
    let out = list_directories(dir.to_string_lossy().into_owned())
        .await
        .unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(
        std::path::Path::new(&out[0])
            .file_name()
            .unwrap()
            .to_string_lossy(),
        "sub"
    );
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn list_directories_nonexistent_returns_no_such_file_or_directory() {
    let result = list_directories("/path/that/does/not/exist/lfs_test_pick".to_string()).await;
    assert_eq!(result.unwrap_err(), "no_such_file_or_directory");
}

#[tokio::test]
async fn list_directories_sorts_by_basename_case_insensitive() {
    let dir = temp_dir("list_dirs_sort");
    std::fs::create_dir(dir.join("Banana")).unwrap();
    std::fs::create_dir(dir.join("apple")).unwrap();
    std::fs::create_dir(dir.join("Cherry")).unwrap();
    let out = list_directories(dir.to_string_lossy().into_owned())
        .await
        .unwrap();
    let basenames: Vec<String> = out
        .iter()
        .map(|p| {
            std::path::Path::new(p)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    assert_eq!(basenames, vec!["apple", "Banana", "Cherry"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn stat_returns_some_for_existing_file() {
    let dir = temp_dir("stat_file");
    let f = dir.join("hello.txt");
    std::fs::write(&f, b"hello").unwrap();
    let entry = stat(f.to_string_lossy().into_owned())
        .await
        .unwrap()
        .expect("entry");
    assert_eq!(entry.size, 5);
    assert!(!entry.is_dir);
    assert!(!entry.is_symlink);
    assert_eq!(entry.name, "hello.txt");
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn stat_returns_some_for_existing_directory() {
    let dir = temp_dir("stat_dir");
    let entry = stat(dir.to_string_lossy().into_owned())
        .await
        .unwrap()
        .expect("entry");
    assert!(entry.is_dir);
    assert!(!entry.is_symlink);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn stat_returns_none_for_missing_path() {
    let result = stat("/path/that/does/not/exist/lfs_stat_test".to_string())
        .await
        .unwrap();
    assert!(result.is_none());
}

#[tokio::test]
async fn symlink_stat_returns_none_for_missing_path() {
    let result = symlink_stat("/path/that/does/not/exist/lfs_symlink_test".to_string())
        .await
        .unwrap();
    assert!(result.is_none());
}

#[tokio::test]
async fn symlink_stat_reports_plain_file_not_symlink() {
    let dir = temp_dir("symlink_stat_plain");
    let f = dir.join("plain.txt");
    std::fs::write(&f, b"x").unwrap();
    let entry = symlink_stat(f.to_string_lossy().into_owned())
        .await
        .unwrap()
        .expect("entry");
    assert!(!entry.is_symlink);
    assert!(!entry.is_dir);
    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(unix)]
#[tokio::test]
async fn list_marks_symlink_entries() {
    use std::os::unix::fs::symlink;
    let dir = temp_dir("list_symlink");
    std::fs::write(dir.join("plain.txt"), b"x").unwrap();
    let target = dir.join("target.txt");
    std::fs::write(&target, b"hello").unwrap();
    symlink(&target, dir.join("link.txt")).unwrap();

    let mut entries = list(dir.to_string_lossy().into_owned()).await.unwrap();
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    let by_name = |n: &str| entries.iter().find(|e| e.name == n).expect("present");

    assert!(!by_name("plain.txt").is_symlink);
    assert!(by_name("link.txt").is_symlink);
    // The link still resolves (target exists), so the
    // resolved metadata is populated.
    assert_eq!(by_name("link.txt").size, 5);

    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(unix)]
#[tokio::test]
async fn symlink_stat_reports_symlink_separately() {
    use std::os::unix::fs::symlink;
    let dir = temp_dir("symlink_stat_link");
    let target = dir.join("target_dir");
    std::fs::create_dir(&target).unwrap();
    let link = dir.join("link_to_dir");
    symlink(&target, &link).unwrap();

    let entry = symlink_stat(link.to_string_lossy().into_owned())
        .await
        .unwrap()
        .expect("entry");
    assert!(entry.is_symlink);
    // `symlink_metadata` does not chase the target, so the link
    // entry's own type (not the directory it points at) is what
    // `is_dir` reports — `false`.
    assert!(!entry.is_dir);

    // `stat` follows the symlink and reports the underlying
    // directory's metadata, with `is_symlink: false`.
    let resolved = stat(link.to_string_lossy().into_owned())
        .await
        .unwrap()
        .expect("resolved");
    assert!(resolved.is_dir);
    assert!(!resolved.is_symlink);

    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(not(target_os = "windows"))]
#[tokio::test]
async fn list_visible_matches_list_off_windows() {
    // Off Windows the hidden-name set is always empty, so the
    // view listing is byte-identical to the raw listing — a
    // dotfile is NOT a Windows-hidden entry and stays visible.
    let dir = temp_dir("list_visible");
    std::fs::write(dir.join("plain.txt"), b"x").unwrap();
    std::fs::write(dir.join(".dotfile"), b"y").unwrap();
    let mut raw = list(dir.to_string_lossy().into_owned()).await.unwrap();
    let mut visible = list_visible(dir.to_string_lossy().into_owned())
        .await
        .unwrap();
    raw.sort_by(|a, b| a.name.cmp(&b.name));
    visible.sort_by(|a, b| a.name.cmp(&b.name));
    let raw_names: Vec<&str> = raw.iter().map(|e| e.name.as_str()).collect();
    let visible_names: Vec<&str> = visible.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(raw_names, visible_names);
    assert!(visible_names.contains(&".dotfile"));
    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(not(target_os = "windows"))]
#[tokio::test]
async fn windows_hidden_names_is_empty_off_windows() {
    let dir = temp_dir("hidden");
    let result = windows_hidden_names(dir.to_string_lossy().into_owned()).await;
    assert!(result.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn flat_walk_returns_nested_leaves_with_relative_paths() {
    let dir = temp_dir("flat_walk_nested");
    std::fs::write(dir.join("top.txt"), b"12345").unwrap();
    std::fs::create_dir_all(dir.join("a/b")).unwrap();
    std::fs::write(dir.join("a/mid.bin"), b"xy").unwrap();
    std::fs::write(dir.join("a/b/deep.log"), b"deep!").unwrap();

    let mut leaves = flat_walk_files(dir.to_string_lossy().into_owned(), 100)
        .await
        .unwrap();
    leaves.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
    let rels: Vec<&str> = leaves.iter().map(|e| e.rel_path.as_str()).collect();
    // `/`-joined relative paths regardless of platform; only
    // leaf files, no directory rows.
    assert_eq!(rels, vec!["a/b/deep.log", "a/mid.bin", "top.txt"]);
    let top = leaves.iter().find(|e| e.rel_path == "top.txt").unwrap();
    assert_eq!(top.size, 5);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn flat_walk_empty_tree_returns_no_leaves() {
    let dir = temp_dir("flat_walk_empty");
    std::fs::create_dir_all(dir.join("empty_sub")).unwrap();
    let leaves = flat_walk_files(dir.to_string_lossy().into_owned(), 100)
        .await
        .unwrap();
    assert!(leaves.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(unix)]
#[tokio::test]
async fn flat_walk_skips_symlinks() {
    use std::os::unix::fs::symlink;
    let dir = temp_dir("flat_walk_symlink");
    std::fs::write(dir.join("real.txt"), b"real").unwrap();
    // A symlinked file and a symlinked directory both inside the
    // tree — neither should appear in the flat list, and the
    // linked directory must not be descended into.
    let target_dir = dir.join("target_dir");
    std::fs::create_dir(&target_dir).unwrap();
    std::fs::write(target_dir.join("inside.txt"), b"x").unwrap();
    symlink(dir.join("real.txt"), dir.join("link_to_file")).unwrap();
    symlink(&target_dir, dir.join("link_to_dir")).unwrap();

    let leaves = flat_walk_files(dir.to_string_lossy().into_owned(), 100)
        .await
        .unwrap();
    let rels: Vec<&str> = leaves.iter().map(|e| e.rel_path.as_str()).collect();
    // `target_dir/inside.txt` is reachable directly (not through
    // the link), so it IS present; the link entries are not.
    assert!(rels.contains(&"real.txt"));
    assert!(rels.contains(&"target_dir/inside.txt"));
    assert!(!rels.iter().any(|r| r.contains("link_to_file")));
    assert!(!rels.iter().any(|r| r.contains("link_to_dir")));
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn flat_walk_respects_max_depth() {
    let dir = temp_dir("flat_walk_depth");
    std::fs::create_dir_all(dir.join("a/b/c")).unwrap();
    std::fs::write(dir.join("a/b/c/deep.txt"), b"x").unwrap();
    std::fs::write(dir.join("top.txt"), b"y").unwrap();
    // max_depth 1 walks only the root level — `top.txt` lands,
    // the deeper `a/...` subtree is not descended.
    let leaves = flat_walk_files(dir.to_string_lossy().into_owned(), 1)
        .await
        .unwrap();
    let rels: Vec<&str> = leaves.iter().map(|e| e.rel_path.as_str()).collect();
    assert_eq!(rels, vec!["top.txt"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn copy_recursive_creates_target_tree() {
    let root = temp_dir("copy_recursive_tree");
    let src = root.join("src");
    let dst = root.join("dst");
    std::fs::create_dir_all(src.join("nested/inner")).unwrap();
    std::fs::write(src.join("top.txt"), b"hello").unwrap();
    std::fs::write(src.join("nested/mid.txt"), b"middle").unwrap();
    std::fs::write(src.join("nested/inner/deep.bin"), b"\x01\x02\x03").unwrap();

    copy_recursive_no_symlinks(
        src.to_string_lossy().into_owned(),
        dst.to_string_lossy().into_owned(),
        100,
    )
    .await
    .unwrap();

    assert_eq!(std::fs::read(dst.join("top.txt")).unwrap(), b"hello");
    assert_eq!(
        std::fs::read(dst.join("nested/mid.txt")).unwrap(),
        b"middle"
    );
    assert_eq!(
        std::fs::read(dst.join("nested/inner/deep.bin")).unwrap(),
        b"\x01\x02\x03"
    );
    std::fs::remove_dir_all(&root).ok();
}

#[cfg(unix)]
#[tokio::test]
async fn copy_recursive_skips_symlinks_inside_tree() {
    use std::os::unix::fs::symlink;
    let root = temp_dir("copy_recursive_skip_link");
    let src = root.join("src");
    let dst = root.join("dst");
    std::fs::create_dir_all(&src).unwrap();
    let real = src.join("real.txt");
    std::fs::write(&real, b"real").unwrap();
    // Both file and directory links land inside the tree —
    // neither should appear at dst.
    let target_dir = root.join("link_target_dir");
    std::fs::create_dir(&target_dir).unwrap();
    std::fs::write(target_dir.join("inside.txt"), b"x").unwrap();
    symlink(&real, src.join("link_to_file")).unwrap();
    symlink(&target_dir, src.join("link_to_dir")).unwrap();

    copy_recursive_no_symlinks(
        src.to_string_lossy().into_owned(),
        dst.to_string_lossy().into_owned(),
        100,
    )
    .await
    .unwrap();

    assert!(dst.join("real.txt").is_file());
    assert!(!dst.join("link_to_file").exists());
    assert!(!dst.join("link_to_dir").exists());
    std::fs::remove_dir_all(&root).ok();
}

#[cfg(unix)]
#[tokio::test]
async fn copy_recursive_refuses_symlink_at_root() {
    use std::os::unix::fs::symlink;
    let root = temp_dir("copy_recursive_refuse_root_link");
    let real_dir = root.join("real_dir");
    std::fs::create_dir(&real_dir).unwrap();
    let link = root.join("link_to_dir");
    symlink(&real_dir, &link).unwrap();
    let dst = root.join("dst");

    let err = copy_recursive_no_symlinks(
        link.to_string_lossy().into_owned(),
        dst.to_string_lossy().into_owned(),
        100,
    )
    .await
    .unwrap_err();
    assert_eq!(err, "symlink_in_source");
    std::fs::remove_dir_all(&root).ok();
}

#[tokio::test]
async fn copy_recursive_errors_on_depth_overflow() {
    let root = temp_dir("copy_recursive_depth");
    let src = root.join("src");
    // Three levels deep: src / a / b / c (plus a leaf file).
    std::fs::create_dir_all(src.join("a/b/c")).unwrap();
    std::fs::write(src.join("a/b/c/leaf.txt"), b"x").unwrap();
    let dst = root.join("dst");

    let err = copy_recursive_no_symlinks(
        src.to_string_lossy().into_owned(),
        dst.to_string_lossy().into_owned(),
        1,
    )
    .await
    .unwrap_err();
    assert_eq!(err, "max_depth_exceeded");
    std::fs::remove_dir_all(&root).ok();
}
