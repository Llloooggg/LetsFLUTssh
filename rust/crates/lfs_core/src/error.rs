//! Typed error enum surfaced across the public API.
//!
//! Adapters translate these variants into frontend-friendly shapes
//! (FRB exception, tauri command error, CLI exit code). Core code
//! returns `Result<T, Error>` and never panics on transport faults.
//!
//! Display strings here are intended for log output, not for
//! user-facing UI — UI strings are localized on the Dart side via
//! the `S.of(context)` lookup, keyed off the variant.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("connect failed: {0}")]
    Connect(String),

    #[error("ssh handshake failed: {0}")]
    Handshake(String),

    #[error("authentication failed")]
    AuthFailed,

    #[error("auth error: {0}")]
    Auth(String),

    #[error("key parse failed: {0}")]
    KeyParse(String),

    #[error("passphrase required")]
    PassphraseRequired,

    #[error("passphrase incorrect")]
    PassphraseIncorrect,

    #[error("host key rejected")]
    HostKeyRejected,

    #[error("io: {0}")]
    Io(String),

    /// SQLCipher / rusqlite / DAO-layer failures. Carved out of the
    /// generic `Io` bucket so frontend matchers (toast routing, retry
    /// gating, the corrupt-DB recovery dialog) can pattern-match the
    /// variant directly instead of substring-matching the message.
    #[error("db: {0}")]
    Db(String),

    /// SFTP-protocol errors surfaced from the russh-sftp client. Same
    /// motivation as `Db` — carving them out keeps transfer-driver +
    /// file-browser surfaces from substring-matching `"sftp …"` to
    /// distinguish a remote refusal (permission denied, no such file)
    /// from a transport drop (`russh::Error → Io`).
    #[error("sftp: {0}")]
    Sftp(String),

    /// Connection / session registry misses — the caller asked for a
    /// session id that has no live transport, or the orchestrator's
    /// async branch raced a teardown. Frontend can route these into
    /// the "stale handle, retry connect" recovery rather than the
    /// generic IO toast.
    #[error("session unavailable: {0}")]
    SessionUnavailable(String),

    /// Recorder pipeline errors — registry miss on an unknown id,
    /// frame-write failure, magic-bytes corruption, etc. Frontend's
    /// recorder panel renders these inline rather than surfacing them
    /// as a generic IO toast.
    #[error("recorder: {0}")]
    Recorder(String),

    /// Archive (`.lfs`) build / parse / apply errors. Frontend's
    /// import + export dialogs render these in their own toast rail
    /// (the corruption-recovery dialog also matches a subset of
    /// these by variant rather than substring).
    #[error("archive: {0}")]
    Archive(String),

    /// Transport-level failures inside the connection / port-forward
    /// / transfer drivers. These are state-machine errors above the
    /// raw `russh::Error → Io` layer (e.g. "connection actor
    /// shutdown", "transfer task missing context") that the UI needs
    /// to distinguish from a low-level IO drop.
    #[error("transport: {0}")]
    Transport(String),

    /// Hardware-vault (TPM / Keychain / Keystore / CNG) round-trip
    /// errors. Frontend routes these into the tier-specific
    /// recovery rail rather than a generic IO toast.
    #[error("vault: {0}")]
    Vault(String),

    /// Update-channel HTTP / parse / installer-spawn failures. The
    /// update dialog renders these inline so the user knows the
    /// retry button hits the same network condition vs. a generic
    /// "something went wrong".
    #[error("update: {0}")]
    Update(String),

    /// Platform-tooling subprocess errors (Linux `tpm2-tools`, macOS
    /// `security` / `codesign` / `productsign`). The first-launch
    /// wizard + Settings → Security surfaces these against the
    /// per-tier capability snapshot rather than as generic IO.
    #[error("platform: {0}")]
    Platform(String),

    #[error("crypto: {0}")]
    Crypto(String),

    #[error("timeout")]
    Timeout,

    /// Operation was cancelled cooperatively — typically a long-
    /// running walker (recursive SFTP transfer, archive build)
    /// noticed its progress callback returned `false` and stopped
    /// at the next yield point.
    #[error("cancelled")]
    Cancelled,

    /// `.lfs` archive's manifest reports a `schema_version` newer
    /// than `migration::SchemaVersions::ARCHIVE`, or an
    /// out-of-range value (`<= 0`). The Display format is parsed
    /// Dart-side into `UnsupportedLfsVersionException`, which the
    /// import dialog renders with the "update the app" message —
    /// keep the `found=` / `supported=` shape stable. `found` is
    /// `i64` so the raw manifest value reaches the user / log
    /// trace verbatim instead of being clamped to `i32::MAX`.
    #[error("unsupported_archive_version: found={found}, supported={supported}")]
    ArchiveFutureVersion { found: i64, supported: i32 },
}

impl From<russh::Error> for Error {
    fn from(e: russh::Error) -> Self {
        // russh wraps a number of underlying conditions in one variant;
        // we keep the message verbatim and let UI branch on the typed
        // wrapper variant chosen by the caller (Connect/Handshake/Auth).
        Error::Io(e.to_string())
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e.to_string())
    }
}
