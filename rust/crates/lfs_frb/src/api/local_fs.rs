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
}

pub async fn local_fs_list(path: String) -> Result<Vec<DbLocalFileEntry>, String> {
    Ok(lfs_core::fs::local::list(path)
        .await?
        .into_iter()
        .map(|e| DbLocalFileEntry {
            name: e.name,
            path: e.path,
            size: e.size,
            mode: e.mode,
            mod_time_unix_ms: e.mod_time_unix_ms,
            is_dir: e.is_dir,
        })
        .collect())
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
