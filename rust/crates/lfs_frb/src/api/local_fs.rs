//! FRB adapter for `lfs_core::fs::local`. The Dart `LocalFS`
//! file_browser implementation routes every operation here so
//! `dart:io File / Directory` no longer participates in the
//! file_browser path. `initialDir` stays Dart-side because it
//! depends on `path_provider` (iOS sandbox / Android scoped
//! storage) which has no clean Rust analog.

#[derive(Debug, Clone)]
pub struct DbLocalFileEntry {
    pub name: String,
    pub path: String,
    pub size: u64,
    pub mode: u32,
    pub mod_time_unix_ms: i64,
    pub is_dir: bool,
    /// `true` only when the entry was produced by
    /// [`local_fs_symlink_stat`] and the path is itself a
    /// symbolic link. List / stat results report `false`.
    pub is_symlink: bool,
}

fn to_db_entry(e: lfs_core::fs::local::LocalFileEntry) -> DbLocalFileEntry {
    DbLocalFileEntry {
        name: e.name,
        path: e.path,
        size: e.size,
        mode: e.mode,
        mod_time_unix_ms: e.mod_time_unix_ms,
        is_dir: e.is_dir,
        is_symlink: e.is_symlink,
    }
}

pub async fn local_fs_list(path: String) -> Result<Vec<DbLocalFileEntry>, String> {
    Ok(lfs_core::fs::local::list(path)
        .await?
        .into_iter()
        .map(to_db_entry)
        .collect())
}

/// Stat `path` following symlinks. `None` means "does not
/// exist"; other I/O failures (permission denied, broken disk)
/// surface as `Err`. The transfer walker uses this to read size
/// and mtime for the change-detected replace path; the file pane
/// uses it as a one-trip "exists?" probe.
pub async fn local_fs_stat(path: String) -> Result<Option<DbLocalFileEntry>, String> {
    Ok(lfs_core::fs::local::stat(path).await?.map(to_db_entry))
}

/// Stat `path` without following symlinks. The returned
/// entry's `is_symlink` is `true` when the path itself is a
/// symlink, regardless of target type — matches Dart's
/// `FileSystemEntity.typeSync(path, followLinks: false)`.
pub async fn local_fs_symlink_stat(path: String) -> Result<Option<DbLocalFileEntry>, String> {
    Ok(lfs_core::fs::local::symlink_stat(path)
        .await?
        .map(to_db_entry))
}

pub async fn local_fs_list_directories(path: String) -> Result<Vec<String>, String> {
    lfs_core::fs::local::list_directories(path).await
}

pub async fn local_fs_mkdir(path: String) -> Result<(), String> {
    lfs_core::fs::local::mkdir(path).await
}

pub async fn local_fs_remove(path: String) -> Result<(), String> {
    lfs_core::fs::local::remove(path).await
}

pub async fn local_fs_remove_dir(path: String) -> Result<(), String> {
    lfs_core::fs::local::remove_dir(path).await
}

pub async fn local_fs_rename(old_path: String, new_path: String) -> Result<(), String> {
    lfs_core::fs::local::rename(old_path, new_path).await
}

pub async fn local_fs_dir_size(path: String) -> Result<u64, String> {
    lfs_core::fs::local::dir_size(path).await
}

pub async fn local_fs_windows_hidden_names(dir: String) -> Vec<String> {
    lfs_core::fs::local::windows_hidden_names(dir).await
}

/// Copy a single file. Replaces the destination if it exists.
/// Symmetric with [`local_fs_copy_recursive_no_symlinks`] so the
/// file-browser drop path stays Rust-side across both branches.
pub async fn local_fs_copy_file(src: String, dst: String) -> Result<(), String> {
    lfs_core::fs::local::copy_file(src, dst).await
}

/// Recursively copy a directory tree. Refuses to traverse
/// symlinks: a symlink at the root returns
/// `Err("symlink_in_source")`, symlinks inside the tree are
/// silently skipped, and recursion is bounded by `max_depth`.
/// The Dart file-browser drop path passes 100, matching the
/// constant it previously enforced inline.
pub async fn local_fs_copy_recursive_no_symlinks(
    src: String,
    dst: String,
    max_depth: u32,
) -> Result<(), String> {
    lfs_core::fs::local::copy_recursive_no_symlinks(src, dst, max_depth).await
}

/// Android shared-storage initial-dir probe. Stats
/// `/storage/emulated/0`, then stats and lists `Download` to
/// detect MANAGE_EXTERNAL_STORAGE (a permissive root listing
/// succeeds on scoped storage even when the child is locked).
/// `None` means the probe failed; the Dart caller falls back
/// to `getExternalStorageDirectory()` (Flutter plugin path,
/// no Rust analog). `home_dir` is the canonical shared root
/// (`/storage/emulated/0` on most devices).
pub async fn local_fs_android_initial_dir(home_dir: String) -> Option<String> {
    lfs_core::fs::local::android_initial_dir_probe(home_dir).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn list_empty_dir_returns_empty_vec() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let path = tmp.path().to_str().expect("utf-8 path").to_string();
        let entries = local_fs_list(path).await.expect("list empty");
        assert!(entries.is_empty());
    }

    #[tokio::test]
    async fn list_returns_entries_with_populated_fields() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        std::fs::write(tmp.path().join("file.txt"), b"hello").expect("write");
        std::fs::create_dir(tmp.path().join("sub")).expect("mkdir");
        let path = tmp.path().to_str().expect("utf-8 path").to_string();
        let entries = local_fs_list(path).await.expect("list");
        assert_eq!(entries.len(), 2);
        let file = entries
            .iter()
            .find(|e| e.name == "file.txt")
            .expect("file row");
        assert!(!file.is_dir);
        assert_eq!(file.size, 5);
        let sub = entries.iter().find(|e| e.name == "sub").expect("dir row");
        assert!(sub.is_dir);
    }

    #[tokio::test]
    async fn mkdir_creates_a_new_directory() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let target = tmp.path().join("new_subdir");
        let target_str = target.to_str().expect("utf-8 path").to_string();
        local_fs_mkdir(target_str).await.expect("mkdir");
        assert!(target.is_dir());
    }

    #[tokio::test]
    async fn remove_deletes_a_file() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let file = tmp.path().join("delete-me.txt");
        std::fs::write(&file, b"x").expect("write");
        let file_str = file.to_str().expect("utf-8 path").to_string();
        local_fs_remove(file_str).await.expect("remove");
        assert!(!file.exists());
    }

    #[tokio::test]
    async fn remove_dir_drops_empty_directory() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().join("empty-subdir");
        std::fs::create_dir(&dir).expect("mkdir");
        let dir_str = dir.to_str().expect("utf-8 path").to_string();
        local_fs_remove_dir(dir_str).await.expect("rmdir");
        assert!(!dir.exists());
    }

    #[tokio::test]
    async fn rename_relocates_a_file() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let src = tmp.path().join("src.txt");
        let dst = tmp.path().join("dst.txt");
        std::fs::write(&src, b"hello").expect("write");
        local_fs_rename(
            src.to_str().expect("utf-8").to_string(),
            dst.to_str().expect("utf-8").to_string(),
        )
        .await
        .expect("rename");
        assert!(!src.exists());
        assert!(dst.exists());
        assert_eq!(std::fs::read(&dst).expect("read"), b"hello");
    }

    #[tokio::test]
    async fn dir_size_sums_recursive_file_sizes() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        std::fs::write(tmp.path().join("a.bin"), [0u8; 100]).expect("write a");
        std::fs::write(tmp.path().join("b.bin"), [0u8; 200]).expect("write b");
        std::fs::create_dir(tmp.path().join("sub")).expect("mkdir");
        std::fs::write(tmp.path().join("sub/c.bin"), [0u8; 50]).expect("write c");
        let path = tmp.path().to_str().expect("utf-8 path").to_string();
        let total = local_fs_dir_size(path).await.expect("dir_size");
        assert_eq!(total, 350);
    }
}
