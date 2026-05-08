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
    pub const GENERIC: &str = "generic";
    pub const CONNECT: &str = "connect";
    pub const HANDSHAKE: &str = "handshake";
    pub const AUTH_FAILED: &str = "auth_failed";
    pub const AUTH_OTHER: &str = "auth_other";
    pub const KEY_PARSE: &str = "key_parse";
    pub const PASSPHRASE_REQUIRED: &str = "passphrase_required";
    pub const PASSPHRASE_INCORRECT: &str = "passphrase_incorrect";
    pub const HOST_KEY_REJECTED: &str = "host_key_rejected";
    pub const IO: &str = "io";
    pub const DB: &str = "db";
    pub const SFTP: &str = "sftp";
    pub const SESSION_UNAVAILABLE: &str = "session_unavailable";
    pub const RECORDER: &str = "recorder";
    pub const ARCHIVE: &str = "archive";
    pub const TRANSPORT: &str = "transport";
    pub const VAULT: &str = "vault";
    pub const UPDATE: &str = "update";
    pub const PLATFORM: &str = "platform";
    pub const CRYPTO: &str = "crypto";
    pub const TIMEOUT: &str = "timeout";
    pub const CANCELLED: &str = "cancelled";
    pub const ARCHIVE_FUTURE_VERSION: &str = "archive_future_version";
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
        CoreError::Timeout => wire(kind::TIMEOUT, ""),
        CoreError::Cancelled => wire(kind::CANCELLED, ""),
        CoreError::ArchiveFutureVersion { found, supported } => wire(
            kind::ARCHIVE_FUTURE_VERSION,
            &format!("found={found},supported={supported}"),
        ),
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
