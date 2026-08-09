//! Centralised id minting.
//!
//! Two shapes — opaque hex handles (32 chars from 16 random
//! bytes; no UUID structure) and proper UUIDv4 strings. Both
//! draw from `OsRng` so the entropy is the OS CSPRNG.
//!
//! Why two: handle ids are not user-visible and don't need to
//! survive cross-process parsing — the cheaper hex shape
//! suffices and avoids pulling `uuid::Uuid` formatting into
//! every callsite. UUIDv4 is preserved for the call sites that
//! either persist the id (sessions / ssh_keys table rows) or
//! interoperate with Dart `Uuid().v4()`.
//!
//! Lives in `lfs_core` (not `lfs_frb`) because adapter code
//! must not own randomness — the workspace policy keeps `rand`
//! out of the FRB layer's dep graph.

use rand::Rng;
use uuid::Uuid;

/// Produce a 32-character lowercase-hex handle id from 16
/// random bytes. Used for opaque in-process handles where UUID
/// structure (version + variant bits) is unnecessary cosmetic
/// overhead. Single source for handle-id minting across modules.
pub fn random_handle_hex_32() -> String {
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    let mut hex = String::with_capacity(32);
    for b in bytes {
        use std::fmt::Write as _;
        // Infallible — write! into String only fails on alloc
        // failure, which would have already aborted.
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

/// Produce a UUIDv4 as a hyphenated lowercase string. Used
/// where the id is persisted (sessions, ssh_keys) or has to
/// match Dart's `Uuid().v4()` shape across the bridge.
pub fn random_uuid_v4() -> String {
    Uuid::new_v4().to_string()
}
#[cfg(test)]
#[path = "../tests/unit/id.rs"]
mod tests;
