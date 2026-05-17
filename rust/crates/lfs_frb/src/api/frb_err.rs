//! Wire-format error envelope for the FRB boundary.
//!
//! Every FRB API surfaces failures as `Result<T, String>` whose
//! `Err` is a JSON-encoded [`FrbError`]. Dart side parses via
//! `lib/utils/frb_error.dart::FrbError.fromWire` and switches on
//! [`FrbError::kind`] for routing — never on substring of the
//! rendered text. The wire shape is stable; rewording the
//! `detail` text never changes UI routing because the routing
//! table reads `kind` only.
//!
//! Adoption is incremental: existing `.map_err(|e| e.to_string())`
//! sites still serialise as plain strings and the Dart parser
//! falls back to `kind = "generic"` when the wire shape is not
//! valid JSON. New sites use [`wire`] / [`wire_str`] /
//! [`From<lfs_core::Error>`] to land a typed envelope.
//!
//! Closes the substring-matching loop the audit found:
//! `lib/utils/format.dart` switching on English error text was
//! the leakiest part of the boundary; the typed `kind` lets the
//! Dart wrapper pick a localised message and a UI route without
//! ever inspecting `detail`.
// Re-export the alias so the codegen-emitted `use crate::api::frb_err::*;`
// wildcard pulls `CoreError` into the generated file's scope. The
// codegen wraps `CoreError` as a `RustAutoOpaque` for the
// `Result<_, lfs_core::Error>` round-trip and references it
// unqualified.
pub use lfs_core::error::Error as CoreError;

/// Stable wire-name discriminators. Add variants here when a new
/// error kind needs explicit routing in Dart; bumping any of
/// these is a wire break.
pub mod kind {
    /// Catch-all bucket. Unmapped panics, fallback for `e.to_string()`
    /// callsites, Dart parser default when wire JSON is malformed.
    /// UI shows the raw `detail` text under a generic "operation
    /// failed" heading.
    pub const GENERIC: &str = "generic";
    /// TCP connect / proxy chain failed before the SSH handshake
    /// started. UI surfaces "could not reach host" with retry.
    pub const CONNECT: &str = "connect";
    /// SSH transport handshake failed (KEX, host-key exchange,
    /// crypto negotiation). Distinct from `CONNECT` so the UI
    /// can offer a host-key inspection branch.
    pub const HANDSHAKE: &str = "handshake";
    /// Authentication exhausted every supplied credential. UI
    /// re-prompts on the matching tier (password / key / agent).
    pub const AUTH_FAILED: &str = "auth_failed";
    /// Auth succeeded protocol-wise but the server rejected the
    /// session (account disabled, expired, MFA required without
    /// keyboard-interactive). Caller routes through the manual
    /// retry path with the raw detail.
    pub const AUTH_OTHER: &str = "auth_other";
    /// Private key file failed to parse (corrupt PEM, unsupported
    /// algorithm, malformed OpenSSH wrapper). UI offers re-import.
    pub const KEY_PARSE: &str = "key_parse";
    /// Encrypted private key needs a passphrase the caller has
    /// not supplied yet. UI prompts for passphrase + retries.
    pub const PASSPHRASE_REQUIRED: &str = "passphrase_required";
    /// Caller supplied a passphrase but it failed to unwrap the
    /// key. UI re-prompts with the rate-limit hint.
    pub const PASSPHRASE_INCORRECT: &str = "passphrase_incorrect";
    /// Host-key TOFU verification rejected the server. UI routes
    /// to the known-hosts inspection dialog.
    pub const HOST_KEY_REJECTED: &str = "host_key_rejected";
    /// Generic IO failure (filesystem, network read/write that
    /// doesn't fit a more specific kind). Detail carries the OS
    /// errno text.
    pub const IO: &str = "io";
    /// rusqlite / SQLCipher backend error. UI surfaces a
    /// "data store problem" toast — never the raw SQL detail.
    pub const DB: &str = "db";
    /// SFTP-protocol level error (file ops, transfer state).
    /// Distinct from `IO` so the file pane can route specific
    /// recovery paths (e.g. resume on lost-connection).
    pub const SFTP: &str = "sftp";
    /// Caller referenced a session id that no longer exists in
    /// the registry (closed before the request landed). UI
    /// updates the session list and surfaces a stale-handle
    /// notice.
    pub const SESSION_UNAVAILABLE: &str = "session_unavailable";
    /// Asciinema recorder pipeline error (encode / flush / poison
    /// recovery). UI offers to retry the recording.
    pub const RECORDER: &str = "recorder";
    /// `.lfs` archive read / write failure (manifest parse,
    /// integrity check, zip-bomb cap hit). Distinct from
    /// `ARCHIVE_FUTURE_VERSION` so the latter routes to a
    /// "newer build needed" branch.
    pub const ARCHIVE: &str = "archive";
    /// Port-forward or transport-level error after the SSH
    /// session is up. UI marks the affected forward as failed
    /// without tearing down the parent session.
    pub const TRANSPORT: &str = "transport";
    /// Recoverable hardware-vault backend error (wrong PIN,
    /// missing file, TPM revoked). Caller may retry. Dart UI
    /// MUST NOT trigger the destructive reset cascade on this
    /// kind — see [`VAULT_CORRUPT`] for the corrupt-envelope
    /// variant that does.
    pub const VAULT: &str = "vault";
    /// On-disk vault envelope failed length-prefix sanity (truncated
    /// header, length out of range). The Dart UI's
    /// "vault corrupt — running reset cascade" branch routes off
    /// this discriminator. Distinct from `VAULT` so a recoverable
    /// backend error (wrong PIN, missing file) doesn't trigger the
    /// destructive reset path.
    pub const VAULT_CORRUPT: &str = "vault_corrupt";
    /// Hardware vault not available on this platform (Linux without
    /// TPM2, or a probe-rejected backend). Caller falls back to
    /// the master-password path; UI shows the "hardware tier
    /// unavailable" copy rather than a security warning.
    pub const VAULT_PLATFORM_UNSUPPORTED: &str = "vault_platform_unsupported";
    /// Auto-update download / verify / install failure. Detail
    /// carries the failing stage so the UI can offer the right
    /// retry (re-download vs re-verify vs manual install).
    pub const UPDATE: &str = "update";
    /// Platform-OS interaction error (Keychain / Keystore /
    /// libsecret / NCrypt / fprintd). Distinct from `VAULT` so
    /// the UI can mark the platform feature as unavailable
    /// rather than retry inline.
    pub const PLATFORM: &str = "platform";
    /// Crypto primitive failure (AES-GCM auth tag mismatch,
    /// HKDF length mismatch, Argon2id panic). UI treats as
    /// non-recoverable + routes to the data-corruption dialog.
    pub const CRYPTO: &str = "crypto";
    /// Operation exceeded its deadline. UI shows a timeout
    /// notice + offers retry; transports do NOT auto-retry.
    pub const TIMEOUT: &str = "timeout";
    /// Operation was cancelled by the caller (user pressed
    /// cancel, parent scope dropped). UI suppresses the toast —
    /// cancellation is not an error from the user's perspective.
    pub const CANCELLED: &str = "cancelled";
    /// `.lfs` archive's `manifest.schema_version` exceeds the build's
    /// `lfs_core::migration::SchemaVersions::ARCHIVE`. Dart UI shows
    /// "newer build needed" copy; archive is NOT applied.
    pub const ARCHIVE_FUTURE_VERSION: &str = "archive_future_version";
    /// WebDAV transport failure (PROPFIND parse, ETag mismatch,
    /// auth challenge cycle, depth=infinity refusal). Detail
    /// carries the short reason; UI surfaces the localized
    /// "sync server rejected the request" message.
    pub const WEBDAV: &str = "webdav";
    /// S3 transport / signing failure. Detail carries the short
    /// reason; UI surfaces the localized "S3 server rejected the
    /// request" message.
    pub const S3: &str = "s3";
    /// FIDO2 / CTAP2 hardware-key failure (no device plugged in,
    /// PIN rejected, user tap timeout, HID transport drop). Detail
    /// carries the short reason; the Dart UI's hardware-key prompt
    /// branches on the leading discriminator (`wrong pin:`,
    /// `timeout:`, generic) to pick the right toast.
    pub const FIDO2: &str = "fido2";
    /// PKCS#11 / Cryptoki hardware-token failure (module not loaded,
    /// no token in slot, PIN rejected, lockout imminent, sign refused,
    /// session dropped). Detail carries the short reason; the Dart UI
    /// smart-card prompt branches on the leading discriminator
    /// (`wrong pin:`, `pin locked:`, `unplugged:`, generic) to pick
    /// the right toast / dialog.
    pub const PKCS11: &str = "pkcs11";
    /// Apple Secure Enclave failure (ad-hoc-signed bundle, biometric
    /// cancel, key not found, sign refused). Detail carries the short
    /// reason; the Dart UI's wizard / connect dialog branches on the
    /// leading discriminator (`code-signing required`, `cancelled`,
    /// `key not found`, generic) to pick the right toast.
    pub const ENCLAVE: &str = "enclave";
    /// Windows Hello / NCrypt failure (Hello not configured, no TPM,
    /// Microsoft Platform Crypto Provider open refused, user dismissed
    /// the Hello prompt, P-384 unsupported by host TPM firmware). Detail
    /// carries the short reason; the Dart UI's wizard / connect dialog
    /// branches on the leading discriminator (`hello not configured`,
    /// `cancelled`, `tpm p384 unsupported`, generic) to pick the right
    /// toast.
    pub const HELLO: &str = "hello";
    /// TPM 2.0 SSH-signer failure (no TPM detected, fTPM disabled in
    /// firmware, app cannot access `/dev/tpmrm0` because the user is
    /// not in the `tss` group, PIN rejected, dictionary-attack
    /// lockout cooldown, persistent slot already in use, malformed
    /// cross-tool `.tpm` blob — `ssh-tpm-agent` / `openssl-tpm2-engine`
    /// files with PCR policy reject at import). Detail carries the
    /// short reason; the Dart UI's wizard / connect dialog branches
    /// on the leading discriminator (`pin incorrect:`, `lockout:`,
    /// `unavailable:`, `handle in use:`, generic) to pick the right
    /// toast / route.
    pub const TPM: &str = "tpm";
    /// Android Hardware Keystore / StrongBox SSH-signer failure
    /// (biometric not enrolled, key destroyed by fresh enrolment via
    /// `KeyPermanentlyInvalidatedException`, StrongBox refused via
    /// `StrongBoxUnavailableException`, BiometricPrompt cancel,
    /// per-op auth window expired through `UserNotAuthenticatedException`).
    /// Detail carries the short reason; the Dart UI's wizard /
    /// connect dialog branches on the leading discriminator
    /// (`invalidated:`, `strongbox unavailable:`, `no biometric:`,
    /// `cancelled:`, generic) to pick the right toast / remediation.
    pub const KEYSTORE: &str = "keystore";
    /// Operation is structurally unavailable on this build target
    /// (e.g. the in-process ssh-agent endpoint on Android / iOS).
    /// UI renders the matching control disabled-with-reason rather
    /// than retrying.
    pub const UNSUPPORTED: &str = "unsupported";
}

/// Compose a JSON envelope with the given kind + detail. Use
/// when the caller has a typed error and wants to attach a
/// stable wire-name without an explicit `From` impl.
///
/// Internal to `lfs_frb` — `pub(crate)` keeps codegen from
/// exposing it as a Dart-callable function. The `#[frb(ignore)]`
/// attribute is honoured but doesn't fully suppress the codegen
/// pass that names this surface "wire" in `frb_generated.dart`,
/// which then collides with the field name on the FFI dispatcher
/// class and produces a "wire is not a class" compile error in
/// the generated bindings. `pub(crate)` blocks codegen at the
/// visibility level — the function stays internal to the crate.
#[must_use]
pub(crate) fn wire(kind: &str, detail: &str) -> String {
    // Hand-built JSON so the wire shape stays stable without a
    // serde_json dep on the FRB crate (`lfs_core::error::Error`
    // is already kept dep-light to keep the FRB worker light).
    let kind_json = json_escape(kind);
    let detail_json = json_escape(detail);
    format!("{{\"kind\":\"{kind_json}\",\"detail\":\"{detail_json}\"}}")
}

/// Convenience wrapper that maps a `Display` value to its wire
/// envelope under a fixed kind.
#[must_use]
pub(crate) fn wire_str<E: std::fmt::Display>(kind: &str, e: E) -> String {
    wire(kind, &e.to_string())
}

/// Map a `lfs_core::Error` to its canonical wire envelope. Each
/// variant lands under a stable `kind` so Dart routing tables
/// never substring-match on the (potentially localized /
/// reworded) `detail` text.
#[must_use]
pub(crate) fn from_core(err: &CoreError) -> String {
    match err {
        CoreError::Connect(s) => wire(kind::CONNECT, s),
        CoreError::Handshake(s) => wire(kind::HANDSHAKE, s),
        CoreError::AuthFailed => wire(kind::AUTH_FAILED, ""),
        CoreError::Auth(s) => wire(kind::AUTH_OTHER, s),
        CoreError::KeyParse(s) => wire(kind::KEY_PARSE, s),
        CoreError::PassphraseRequired => wire(kind::PASSPHRASE_REQUIRED, ""),
        CoreError::PassphraseIncorrect => wire(kind::PASSPHRASE_INCORRECT, ""),
        CoreError::HostKeyRejected => wire(kind::HOST_KEY_REJECTED, ""),
        CoreError::Io(s) => wire(kind::IO, s),
        CoreError::Db(s) => wire(kind::DB, s),
        CoreError::Sftp(s) => wire(kind::SFTP, s),
        CoreError::SessionUnavailable(s) => wire(kind::SESSION_UNAVAILABLE, s),
        CoreError::Recorder(s) => wire(kind::RECORDER, s),
        CoreError::Archive(s) => wire(kind::ARCHIVE, s),
        CoreError::Transport(s) => wire(kind::TRANSPORT, s),
        CoreError::Vault(s) => wire(kind::VAULT, s),
        CoreError::Update(s) => wire(kind::UPDATE, s),
        CoreError::Platform(s) => wire(kind::PLATFORM, s),
        CoreError::Crypto(s) => wire(kind::CRYPTO, s),
        CoreError::WebDav(s) => wire(kind::WEBDAV, s),
        CoreError::S3(s) => wire(kind::S3, s),
        CoreError::Fido2(s) => wire(kind::FIDO2, s),
        CoreError::Pkcs11(s) => wire(kind::PKCS11, s),
        CoreError::Enclave(s) => wire(kind::ENCLAVE, s),
        CoreError::Hello(s) => wire(kind::HELLO, s),
        CoreError::Tpm(s) => wire(kind::TPM, s),
        CoreError::Keystore(s) => wire(kind::KEYSTORE, s),
        CoreError::Timeout => wire(kind::TIMEOUT, ""),
        CoreError::Cancelled => wire(kind::CANCELLED, ""),
        CoreError::ArchiveFutureVersion { found, supported } => wire(
            kind::ARCHIVE_FUTURE_VERSION,
            &format!("found={found},supported={supported}"),
        ),
        CoreError::Unsupported(s) => wire(kind::UNSUPPORTED, s),
    }
}

/// FRB-visible typed mirror of every wire discriminator declared in
/// [`kind`]. The Dart caller pattern-matches on this enum rather
/// than substring-matching the kind string — the FRB-generated Dart
/// enum mirrors variant-for-variant so a rewrite of the routing
/// logic in `lib/utils/format.dart` reads as a `switch` on a typed
/// value, not a string compare.
///
/// Unknown / future variants land on [`DbFrbErrorKind::Generic`] so
/// a newer Rust build cannot brick a Dart caller — the routing
/// table stays exhaustive across upgrades.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbFrbErrorKind {
    Generic,
    Connect,
    Handshake,
    AuthFailed,
    AuthOther,
    KeyParse,
    PassphraseRequired,
    PassphraseIncorrect,
    HostKeyRejected,
    Io,
    Db,
    Sftp,
    SessionUnavailable,
    Recorder,
    Archive,
    Transport,
    Vault,
    VaultCorrupt,
    VaultPlatformUnsupported,
    Update,
    Platform,
    Crypto,
    Timeout,
    Cancelled,
    ArchiveFutureVersion,
    WebDav,
    S3,
    Fido2,
    Pkcs11,
    Enclave,
    Hello,
    Tpm,
    Keystore,
    Unsupported,
}

impl DbFrbErrorKind {
    /// Stable wire name matching the [`kind`] constant of the same
    /// variant. Used by the Dart export-side codec for the round
    /// trip; the FRB Dart enum's `.name` getter is unsuitable
    /// because Rust's `WebDav` lowers to `webDav` not `webdav` and
    /// the underscored variants (`auth_failed`) lose their
    /// separator entirely.
    #[must_use]
    pub fn wire_name(self) -> &'static str {
        match self {
            Self::Generic => kind::GENERIC,
            Self::Connect => kind::CONNECT,
            Self::Handshake => kind::HANDSHAKE,
            Self::AuthFailed => kind::AUTH_FAILED,
            Self::AuthOther => kind::AUTH_OTHER,
            Self::KeyParse => kind::KEY_PARSE,
            Self::PassphraseRequired => kind::PASSPHRASE_REQUIRED,
            Self::PassphraseIncorrect => kind::PASSPHRASE_INCORRECT,
            Self::HostKeyRejected => kind::HOST_KEY_REJECTED,
            Self::Io => kind::IO,
            Self::Db => kind::DB,
            Self::Sftp => kind::SFTP,
            Self::SessionUnavailable => kind::SESSION_UNAVAILABLE,
            Self::Recorder => kind::RECORDER,
            Self::Archive => kind::ARCHIVE,
            Self::Transport => kind::TRANSPORT,
            Self::Vault => kind::VAULT,
            Self::VaultCorrupt => kind::VAULT_CORRUPT,
            Self::VaultPlatformUnsupported => kind::VAULT_PLATFORM_UNSUPPORTED,
            Self::Update => kind::UPDATE,
            Self::Platform => kind::PLATFORM,
            Self::Crypto => kind::CRYPTO,
            Self::Timeout => kind::TIMEOUT,
            Self::Cancelled => kind::CANCELLED,
            Self::ArchiveFutureVersion => kind::ARCHIVE_FUTURE_VERSION,
            Self::WebDav => kind::WEBDAV,
            Self::S3 => kind::S3,
            Self::Fido2 => kind::FIDO2,
            Self::Pkcs11 => kind::PKCS11,
            Self::Enclave => kind::ENCLAVE,
            Self::Hello => kind::HELLO,
            Self::Tpm => kind::TPM,
            Self::Keystore => kind::KEYSTORE,
            Self::Unsupported => kind::UNSUPPORTED,
        }
    }

    /// Parse a wire-string discriminator into the typed variant.
    /// Unknown strings fall back to [`Self::Generic`] so a future
    /// `kind` added in a newer Rust build cannot brick a Dart UI
    /// shipped against an older codegen.
    #[must_use]
    pub fn from_wire(value: &str) -> Self {
        match value {
            kind::CONNECT => Self::Connect,
            kind::HANDSHAKE => Self::Handshake,
            kind::AUTH_FAILED => Self::AuthFailed,
            kind::AUTH_OTHER => Self::AuthOther,
            kind::KEY_PARSE => Self::KeyParse,
            kind::PASSPHRASE_REQUIRED => Self::PassphraseRequired,
            kind::PASSPHRASE_INCORRECT => Self::PassphraseIncorrect,
            kind::HOST_KEY_REJECTED => Self::HostKeyRejected,
            kind::IO => Self::Io,
            kind::DB => Self::Db,
            kind::SFTP => Self::Sftp,
            kind::SESSION_UNAVAILABLE => Self::SessionUnavailable,
            kind::RECORDER => Self::Recorder,
            kind::ARCHIVE => Self::Archive,
            kind::TRANSPORT => Self::Transport,
            kind::VAULT => Self::Vault,
            kind::VAULT_CORRUPT => Self::VaultCorrupt,
            kind::VAULT_PLATFORM_UNSUPPORTED => Self::VaultPlatformUnsupported,
            kind::UPDATE => Self::Update,
            kind::PLATFORM => Self::Platform,
            kind::CRYPTO => Self::Crypto,
            kind::TIMEOUT => Self::Timeout,
            kind::CANCELLED => Self::Cancelled,
            kind::ARCHIVE_FUTURE_VERSION => Self::ArchiveFutureVersion,
            kind::WEBDAV => Self::WebDav,
            kind::S3 => Self::S3,
            kind::FIDO2 => Self::Fido2,
            kind::PKCS11 => Self::Pkcs11,
            kind::ENCLAVE => Self::Enclave,
            kind::HELLO => Self::Hello,
            kind::TPM => Self::Tpm,
            kind::KEYSTORE => Self::Keystore,
            kind::UNSUPPORTED => Self::Unsupported,
            _ => Self::Generic,
        }
    }
}

/// FRB-visible typed mirror of the wire envelope. The grammar
/// lives Rust-side; the Dart caller passes the raw wire string
/// through [`frb_error_from_wire`] to receive this struct back —
/// no Dart-side parser on the FRB error channel.
///
/// `kind` is a typed [`DbFrbErrorKind`] rather than a raw string;
/// the Dart routing table in `lib/utils/format.dart` pattern-matches
/// on the variant so a future `kind` rename in this file cannot
/// silently re-classify a routed UI toast as a generic one.
#[derive(Debug, Clone)]
pub struct DbFrbError {
    pub kind: DbFrbErrorKind,
    pub detail: String,
}

/// Parse an FRB error string into the typed [`DbFrbError`] envelope.
/// JSON-shaped payloads land with their typed [`DbFrbErrorKind`] +
/// `detail`; non-JSON strings (plain `e.to_string()` callsites that
/// have not migrated yet) fall back to
/// [`DbFrbErrorKind::Generic`] with the original text as detail.
/// Malformed JSON also lands in the generic bucket — never returns
/// an error so untrusted input still routes safely.
///
/// Sync because the only work is one `serde_json::from_str` + two
/// `as_str` reads; the Dart caller hits this on every UI toast
/// path and a per-render async hop would tax the rebuild.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn frb_error_from_wire(wire: String) -> DbFrbError {
    if wire.is_empty() {
        return DbFrbError {
            kind: DbFrbErrorKind::Generic,
            detail: String::new(),
        };
    }
    if !wire.starts_with('{') {
        return DbFrbError {
            kind: DbFrbErrorKind::Generic,
            detail: wire,
        };
    }
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&wire) else {
        return DbFrbError {
            kind: DbFrbErrorKind::Generic,
            detail: wire,
        };
    };
    let Some(obj) = value.as_object() else {
        return DbFrbError {
            kind: DbFrbErrorKind::Generic,
            detail: wire,
        };
    };
    let kind_str = obj.get("kind").and_then(serde_json::Value::as_str);
    let detail_str = obj.get("detail").and_then(serde_json::Value::as_str);
    match (kind_str, detail_str) {
        (Some(k), Some(d)) => DbFrbError {
            kind: DbFrbErrorKind::from_wire(k),
            detail: d.to_string(),
        },
        _ => DbFrbError {
            kind: DbFrbErrorKind::Generic,
            detail: wire,
        },
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                use std::fmt::Write as _;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_formats_kind_and_detail() {
        assert_eq!(wire("foo", "bar"), r#"{"kind":"foo","detail":"bar"}"#);
    }

    #[test]
    fn wire_escapes_quotes_and_control_chars() {
        let envelope = wire("k", "with \"quote\" and\nnewline");
        assert_eq!(
            envelope,
            r#"{"kind":"k","detail":"with \"quote\" and\nnewline"}"#
        );
    }

    #[test]
    fn from_wire_parses_canonical_envelope() {
        let e = frb_error_from_wire(r#"{"kind":"auth_failed","detail":"bad pw"}"#.to_string());
        assert_eq!(e.kind, DbFrbErrorKind::AuthFailed);
        assert_eq!(e.detail, "bad pw");
    }

    #[test]
    fn from_wire_falls_back_to_generic_for_non_json() {
        let e = frb_error_from_wire("no such host".to_string());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
        assert_eq!(e.detail, "no such host");
    }

    #[test]
    fn from_wire_falls_back_to_generic_for_malformed_json() {
        let e = frb_error_from_wire("{not json".to_string());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
        assert_eq!(e.detail, "{not json");
    }

    #[test]
    fn from_wire_empty_string_yields_generic_empty() {
        let e = frb_error_from_wire(String::new());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
        assert_eq!(e.detail, "");
    }

    #[test]
    fn from_wire_missing_kind_or_detail_folds_to_generic() {
        let e = frb_error_from_wire(r#"{"kind":"auth_failed"}"#.to_string());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
        let e = frb_error_from_wire(r#"{"detail":"x"}"#.to_string());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
    }

    #[test]
    fn from_wire_unknown_kind_folds_to_generic() {
        // A future Rust build adding a new `kind` discriminator must
        // not brick an older Dart caller — the parser folds the
        // unknown variant onto Generic so the routing table stays
        // exhaustive across the upgrade.
        let e = frb_error_from_wire(r#"{"kind":"future_variant","detail":"x"}"#.to_string());
        assert_eq!(e.kind, DbFrbErrorKind::Generic);
        assert_eq!(e.detail, "x");
    }

    #[test]
    fn kind_wire_name_round_trips_every_variant() {
        // Byte-identity guard — Dart receives the typed enum via
        // FRB and Rust serialises the same enum into the wire
        // envelope, so the round trip MUST be lossless for every
        // discriminator. A typo here would silently drop one
        // variant onto Generic on the receive side.
        for v in [
            DbFrbErrorKind::Generic,
            DbFrbErrorKind::Connect,
            DbFrbErrorKind::Handshake,
            DbFrbErrorKind::AuthFailed,
            DbFrbErrorKind::AuthOther,
            DbFrbErrorKind::KeyParse,
            DbFrbErrorKind::PassphraseRequired,
            DbFrbErrorKind::PassphraseIncorrect,
            DbFrbErrorKind::HostKeyRejected,
            DbFrbErrorKind::Io,
            DbFrbErrorKind::Db,
            DbFrbErrorKind::Sftp,
            DbFrbErrorKind::SessionUnavailable,
            DbFrbErrorKind::Recorder,
            DbFrbErrorKind::Archive,
            DbFrbErrorKind::Transport,
            DbFrbErrorKind::Vault,
            DbFrbErrorKind::VaultCorrupt,
            DbFrbErrorKind::VaultPlatformUnsupported,
            DbFrbErrorKind::Update,
            DbFrbErrorKind::Platform,
            DbFrbErrorKind::Crypto,
            DbFrbErrorKind::Timeout,
            DbFrbErrorKind::Cancelled,
            DbFrbErrorKind::ArchiveFutureVersion,
            DbFrbErrorKind::WebDav,
            DbFrbErrorKind::S3,
            DbFrbErrorKind::Fido2,
            DbFrbErrorKind::Pkcs11,
            DbFrbErrorKind::Enclave,
            DbFrbErrorKind::Hello,
            DbFrbErrorKind::Tpm,
            DbFrbErrorKind::Keystore,
            DbFrbErrorKind::Unsupported,
        ] {
            assert_eq!(DbFrbErrorKind::from_wire(v.wire_name()), v);
        }
    }

    #[test]
    fn from_core_maps_each_variant() {
        assert_eq!(
            from_core(&CoreError::AuthFailed),
            r#"{"kind":"auth_failed","detail":""}"#
        );
        assert_eq!(
            from_core(&CoreError::Sftp("no such file".into())),
            r#"{"kind":"sftp","detail":"no such file"}"#
        );
        assert_eq!(
            from_core(&CoreError::ArchiveFutureVersion {
                found: 5,
                supported: 2
            }),
            r#"{"kind":"archive_future_version","detail":"found=5,supported=2"}"#
        );
    }
}
