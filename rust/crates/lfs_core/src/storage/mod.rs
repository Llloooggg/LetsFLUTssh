//! Backend-agnostic storage abstraction.
//!
//! Defines the [`Provider`] trait every file-transfer backend
//! implements (SFTP today; S3 / WebDAV later) and a small set of
//! plain-old-data types ([`Entry`], [`EntryKind`], [`Metadata`])
//! the trait exchanges with callers. The dispatcher that maps a
//! `(connection_id, kind)` tuple to a concrete `Arc<dyn Provider>`
//! lives downstream — adapters (`lfs_frb`) wire it once the second
//! backend lands.
//!
//! ## Why a trait, not an enum
//!
//! Backend differences (SFTP path syntax vs S3 key prefixes,
//! WebDAV PROPFIND depth semantics) shape the implementation but
//! not the surface — every backend exposes list / stat / mkdir /
//! remove / rename plus streamed GET / PUT. An enum would force
//! every caller to `match` on the variant; a trait keeps the
//! caller polymorphic over `Arc<dyn Provider>`.
//!
//! ## Object-safety contract
//!
//! Every async method returns `Pin<Box<dyn Future<...> + Send>>`.
//! Native async-fn-in-traits (stable since Rust 1.75) is not
//! used here on purpose: the resulting trait would not be
//! `dyn`-compatible without per-method `+ Send` RPITIT desugaring,
//! and the dispatcher needs `Arc<dyn Provider>` for the
//! id-keyed routing in `lfs_frb`. The boxed-future shape matches
//! the existing `ChannelFactory` (`portforward/driver.rs`) and
//! `TaskExecutor` (`transfer/driver.rs`) patterns.
//!
//! ## Streaming bytes
//!
//! `get_stream` / `put_stream` exchange [`BoxStream<'static, Result<Bytes, Error>>`].
//! Per-chunk errors flow through `Result` so a mid-stream
//! transport drop surfaces to the caller without poisoning the
//! whole future. `Bytes` is the de-facto byte buffer in the
//! async Rust ecosystem (hyper / reqwest / h2 already use it),
//! so HTTP-backed providers (S3, WebDAV) forward chunks
//! zero-copy.

use std::future::Future;
use std::pin::Pin;

use bytes::Bytes;
use futures_util::stream::BoxStream;

use crate::error::Error;

pub mod registry;
pub mod s3;
pub mod sftp;
pub mod webdav;

pub use registry::{ProviderRegistration, ProviderRegistry};

/// One directory entry returned by [`Provider::list`].
///
/// `path` is the absolute path on the backend (joined from the
/// listed directory + the entry name). Callers should not
/// re-join it themselves — backends with non-Unix path syntax
/// (S3 keys, WebDAV URIs) own the joining rule.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// Last path component — file or directory name with no
    /// separators. Empty for the root entry when a backend
    /// surfaces one.
    pub name: String,
    /// Absolute path on the backend. The dispatcher hands this
    /// back verbatim on follow-up calls (stat / list / get).
    pub path: String,
    pub kind: EntryKind,
    /// Byte size for files; 0 for directories and symlinks the
    /// backend doesn't resolve.
    pub size_bytes: u64,
    /// Unix epoch milliseconds. `None` when the backend omitted
    /// the field or the value couldn't be translated.
    pub modified_unix_ms: Option<i64>,
}

/// Coarse entry type. Mirrors `dirent::d_type` shapes — backends
/// that only distinguish file / dir (S3, most HTTP storage) emit
/// `Symlink` only when they actually carry symlink semantics.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryKind {
    File,
    Dir,
    Symlink,
}

/// Standalone stat result returned by [`Provider::stat`].
///
/// Same field set as [`Entry`] minus the path / name (the caller
/// already holds the path it asked about). Backends that derive
/// stat from a list call (S3 `HeadObject` answers most, but some
/// providers fall back to a list scan) construct one of these
/// without re-emitting the path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Metadata {
    pub kind: EntryKind,
    pub size_bytes: u64,
    pub modified_unix_ms: Option<i64>,
}

/// Byte chunk stream — return type of [`Provider::get_stream`]
/// and input type of [`Provider::put_stream`]. Per-chunk `Result`
/// so transport drops surface inline; `'static` so the stream can
/// be owned by tokio tasks the dispatcher spawns.
pub type ByteStream = BoxStream<'static, Result<Bytes, Error>>;

/// Boxed future the [`Provider`] trait methods return. Aliased
/// out so the trait signature stays readable inline.
pub type ProviderFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T, Error>> + Send + 'a>>;

/// Storage backend surface. SFTP today; S3 / WebDAV plug in by
/// adding a sibling module + an impl block.
///
/// All methods take `&self` so the backend can multiplex calls
/// over a shared transport (one SFTP session pumps many `list` /
/// `get_stream` calls concurrently). Internal locking is the
/// backend's responsibility.
pub trait Provider: Send + Sync {
    /// List one directory level. No recursion — see [`dir_size`]
    /// for a recursive walk. Returns one [`Entry`] per child;
    /// the order is backend-defined.
    ///
    /// [`dir_size`]: Provider::dir_size
    fn list<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Vec<Entry>>;

    /// Stat a single path. Errors when the path doesn't exist —
    /// callers wanting "exists?" semantics check for
    /// [`Error::Sftp`] / [`Error::Io`] with a not-found
    /// indication and treat that as `false`.
    fn stat<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Metadata>;

    /// Create a directory. Backends with no native directory
    /// concept (S3) synthesise one (PutObject with key
    /// `"<path>/"`); callers don't see the difference.
    fn mkdir<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()>;

    /// Remove a file or directory. Trait surface intentionally
    /// uniform; per-backend split (SFTP file vs dir removal,
    /// S3 single-key delete vs bulk delete) is an implementation
    /// detail.
    fn remove<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()>;

    /// Rename / move. Atomic when the backend supports it; backends
    /// that lack a native rename (S3) emulate via copy + delete,
    /// which is observable to other readers mid-operation.
    fn rename<'a>(&'a self, from: &'a str, to: &'a str) -> ProviderFuture<'a, ()>;

    /// Streamed GET. `range` is `Some((start_inclusive, end_inclusive))`
    /// for a partial read; `None` requests the full file. The
    /// returned stream yields [`Bytes`] chunks until exhausted;
    /// transport errors surface inside the per-chunk `Result`.
    fn get_stream<'a>(
        &'a self,
        path: &'a str,
        range: Option<(u64, u64)>,
    ) -> ProviderFuture<'a, ByteStream>;

    /// Streamed PUT. `len` is a hint — backends that need a
    /// content-length up front (S3 single-shot) honour it;
    /// backends that don't (SFTP) ignore it. Callers that don't
    /// know the length pass `None`.
    fn put_stream<'a>(
        &'a self,
        path: &'a str,
        body: ByteStream,
        len: Option<u64>,
    ) -> ProviderFuture<'a, ()>;

    /// Recursive directory size in bytes. Walk strategy is
    /// backend-specific; the SFTP impl walks the tree depth-first.
    /// Backends with a native aggregate (S3 `ListObjectsV2`
    /// summing `Size` over a prefix) override.
    fn dir_size<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, u64>;
}
