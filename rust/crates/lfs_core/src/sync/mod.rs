//! WebDAV-backed sync orchestrator. Ships the encrypted `.lfs`
//! archive between devices over the
//! [`crate::webdav::WebDavClient`] transport.
//!
//! Two verbs:
//!
//! - [`service::push`] — compose the `.lfs` archive Rust-side
//!   (`archive::export_archive` with `sync_origin` stamped),
//!   PUT it under the configured remote path with an `If-Match`
//!   ETag when one is cached. The push is a no-op when the
//!   plaintext SHA-256 matches the last successful push's hash
//!   ([`SyncResult::UpToDate`]). A 412 from the server surfaces
//!   as [`SyncError::EtagMismatch`] so the caller can route the
//!   user through "pull first".
//!
//! - [`service::pull`] — PROPFIND the remote, skip the body fetch
//!   when the ETag matches the last push (this is our own push
//!   echoing back), GET the bytes, decrypt + parse via
//!   [`crate::archive::read_archive_to_pending`], merge the
//!   pending state into the local DB via [`merge`].
//!
//! ## Why one orchestrator, not "sync drivers" per backend
//!
//! WebDAV is the only sync transport on the roadmap and the
//! archive shape is the single source of truth across devices.
//! A per-backend driver layer would force a `dyn` boundary on
//! the only consumer that exists — `push` / `pull` stay direct
//! function calls until a second backend appears.
//!
//! ## Threading
//!
//! Both verbs are `async`. The orchestrator runs DB work inside
//! [`tokio::task::spawn_blocking`] via the FRB adapter so the
//! rusqlite Connection's blocking I/O does not pin the tokio
//! worker. The merge transaction lives entirely inside one
//! `with_conn_mut` closure so a partial failure rolls back
//! cleanly.

pub mod merge;
pub mod service;

pub use merge::{merge_pending_into_local, MergeOutcome};
pub use service::{pull, push, status, SyncError, SyncResult, SyncStatus};
