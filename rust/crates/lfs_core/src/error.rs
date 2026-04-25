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

    #[error("crypto: {0}")]
    Crypto(String),

    #[error("timeout")]
    Timeout,
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
