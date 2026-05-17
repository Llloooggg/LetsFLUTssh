//! Filesystem operations.
//!
//! `local` covers the Flutter-side `LocalFS` surface — list,
//! mkdir, remove, dir_size, rename, plus the Windows hidden-file
//! filter. All ops are async via `tokio::fs` so the Dart caller
//! awaits without blocking the UI isolate.

pub mod local;
