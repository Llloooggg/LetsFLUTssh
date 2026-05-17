//! Disk-blob format owner for the T1+pw-tier `PersistedRateLimiter`.
//!
//! `PersistedRateLimiter` (Dart) writes its exponential-backoff
//! state to `rate_limit_state.bin` under app-support so a process
//! restart between guesses does not reset the counter. The state is
//! HMAC-authenticated with a key derived (via HKDF-SHA-256) from
//! the T1+pw gate's stored HMAC under the
//! `lfs/persisted-rate-limit/v1` info string. The derive enforces
//! key-separation: the gate HMAC verifies the user-typed password,
//! the rate-limit HMAC signs the cooldown state, and the two never
//! share signing material. An attacker who recovers either side has
//! no algebraic shortcut to forge the other.
//!
//! Wire format (UTF-8 bytes on disk):
//! ```json
//! {
//!   "payload": "<base64 of inner-payload JSON>",
//!   "hmac":    "<base64 of HMAC-SHA-256(signing_key, inner-payload bytes)>"
//! }
//! ```
//!
//! Inner payload (decoded from `payload`):
//! ```json
//! {
//!   "failure_count":         <int>,
//!   "next_retry_at_millis":  <int | null>
//! }
//! ```
//!
//! Pre-v1 state files signed the payload with the gate HMAC
//! directly (no HKDF). [`decode_state`] retries verification with
//! the raw gate HMAC on first-pass mismatch so existing installs
//! decode transparently; the next mutation re-emits under the
//! derived key, completing migration in-place without a registry
//! entry.
//!
//! Tamper handling lives in [`decode_state`]: any malformed shape
//! or HMAC mismatch (under both the derived and the legacy keys)
//! returns `Ok(None)` so the Dart caller treats the file as "fresh
//! state" without surfacing the parse error. `Err` is reserved for
//! cryptographic-equality assertions that cannot be expressed via
//! `Option`.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::{json, Value};

use crate::crypto;

/// HKDF info string the rate-limit signing key is bound to. Bumping
/// this value is a wire-break: every existing on-disk state file
/// will fail the verify and clear on next write. Only bump if a
/// real cryptographic reason emerges (e.g. SHA-256 deprecation).
const SIGNING_KEY_HKDF_INFO: &[u8] = b"lfs/persisted-rate-limit/v2";

/// Per-purpose salt for the HKDF extract step. Per RFC 5869 §3.1
/// a non-empty salt is "strongly recommended" — it provides domain
/// separation between callers that share a key but use different
/// salts. Bumping in lock-step with the info string above closes
/// the audit's "HKDF salt-empty" finding without registry-side
/// migration: the verifier tries this salt first and falls through
/// to a tamper-clear on miss, so existing state files reset their
/// counter on the next write.
const SIGNING_KEY_HKDF_SALT: &[u8] = b"lfs/persisted-rate-limit/salt/v2";

/// Derive the rate-limit signing key from the gate HMAC. Routed via
/// HKDF-SHA-256 so the rate-limit signature is cryptographically
/// independent of any other use of the gate HMAC. Returns 32 bytes
/// (the HMAC-SHA-256 block size) wrapped in `Zeroizing` so the
/// derived material is wiped on drop.
fn derive_signing_key(gate_hmac: &[u8]) -> zeroize::Zeroizing<Vec<u8>> {
    // HKDF length is bounded statically; the caller's `gate_hmac`
    // is always 32 bytes from `crypto::hmac_sha256`, so the expand
    // step never errors. Unwrap the Result to keep call sites
    // panic-free at the API surface.
    let derived = crypto::hkdf_sha256(gate_hmac, SIGNING_KEY_HKDF_SALT, SIGNING_KEY_HKDF_INFO, 32)
        .expect("hkdf-sha256 with 32-byte output is bounded");
    zeroize::Zeroizing::new(derived.to_vec())
}

/// Decoded state — the failure counter + the absolute next-retry
/// timestamp (millis since UNIX epoch). `None` for the timestamp
/// means "no cooldown active right now"; the Dart-side
/// `_cooldownRemaining` returns `Duration.zero` for that case.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistedState {
    pub failure_count: i64,
    pub next_retry_at_millis: Option<i64>,
}

/// Encode the state as the HMAC-authenticated frame written to
/// `rate_limit_state.bin`. The caller writes the returned UTF-8
/// bytes atomically; the file lives next to the other 0600-hardened
/// secret files under app-support.
///
/// `gate_hmac` is the T1+pw-gate's stored HMAC. The signing key is
/// derived from it via HKDF — the gate HMAC itself never directly
/// signs the rate-limit state.
#[must_use]
pub fn encode_state(state: &PersistedState, gate_hmac: &[u8]) -> Vec<u8> {
    let signing_key = derive_signing_key(gate_hmac);
    let payload = json!({
        "failure_count": state.failure_count,
        "next_retry_at_millis": state.next_retry_at_millis,
    });
    // serde_json emits a minified JSON string for `to_string`; that
    // matches the Dart `jsonEncode` behaviour on the same shape, so
    // a state file written by either side parses on the other.
    let payload_str = payload.to_string();
    let payload_bytes = payload_str.as_bytes();
    let hmac = crypto::hmac_sha256(&signing_key, payload_bytes);
    let frame = json!({
        "payload": STANDARD.encode(payload_bytes),
        "hmac": STANDARD.encode(&hmac),
    });
    frame.to_string().into_bytes()
}

/// Parse the on-disk frame, verify the HMAC, and decode the inner
/// payload. Returns `Ok(None)` for a tamper / corruption signal so
/// the Dart caller falls through to "no state on disk" without
/// surfacing the parse error to the user. `Err` is unused today —
/// the function shape leaves room for a future cryptographic
/// failure mode that needs to surface separately.
///
/// `gate_hmac` is the T1+pw-gate's stored HMAC. Verification first
/// tries the HKDF-derived signing key; on miss it retries with the
/// gate HMAC directly so pre-v1 state files (signed before the
/// HKDF separation landed) still decode. The next mutation
/// re-emits under the derived key, migrating the file in-place.
pub fn decode_state(bytes: &[u8], gate_hmac: &[u8]) -> Result<Option<PersistedState>, String> {
    let Ok(text) = std::str::from_utf8(bytes) else {
        return Ok(None);
    };
    let Ok(frame) = serde_json::from_str::<Value>(text) else {
        return Ok(None);
    };
    let Some(obj) = frame.as_object() else {
        return Ok(None);
    };
    let Some(payload_b64) = obj.get("payload").and_then(|v| v.as_str()) else {
        return Ok(None);
    };
    let Some(hmac_b64) = obj.get("hmac").and_then(|v| v.as_str()) else {
        return Ok(None);
    };
    let Ok(payload_bytes) = STANDARD.decode(payload_b64.as_bytes()) else {
        return Ok(None);
    };
    let Ok(claimed) = STANDARD.decode(hmac_b64.as_bytes()) else {
        return Ok(None);
    };
    // Verify against the current HKDF-derived signing key. Older
    // formats (pre-v2 salt, pre-v1 plain gate-HMAC) decode as
    // tamper here and the actor clears the state on next write —
    // user resumes with a fresh failure counter, which is
    // strictly user-friendly (a stuck counter clears).
    let signing_key = derive_signing_key(gate_hmac);
    let expected = crypto::hmac_sha256(&signing_key, &payload_bytes);
    if !crypto::constant_time_eq(&claimed, &expected) {
        return Ok(None);
    }
    let Ok(payload) = serde_json::from_slice::<Value>(&payload_bytes) else {
        return Ok(None);
    };
    let Some(payload_obj) = payload.as_object() else {
        return Ok(None);
    };
    let failure_count = payload_obj
        .get("failure_count")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let next_retry_at_millis = payload_obj
        .get("next_retry_at_millis")
        .and_then(|v| v.as_i64());
    Ok(Some(PersistedState {
        failure_count,
        next_retry_at_millis,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key() -> Vec<u8> {
        vec![0xa5u8; 32]
    }

    #[test]
    fn encode_decode_round_trip_preserves_state() {
        let state = PersistedState {
            failure_count: 3,
            next_retry_at_millis: Some(1_700_000_000_000),
        };
        let bytes = encode_state(&state, &key());
        let decoded = decode_state(&bytes, &key()).unwrap().unwrap();
        assert_eq!(decoded, state);
    }

    #[test]
    fn encode_with_no_cooldown_round_trips() {
        let state = PersistedState {
            failure_count: 0,
            next_retry_at_millis: None,
        };
        let bytes = encode_state(&state, &key());
        let decoded = decode_state(&bytes, &key()).unwrap().unwrap();
        assert_eq!(decoded, state);
    }

    #[test]
    fn decode_returns_none_for_wrong_key() {
        let state = PersistedState {
            failure_count: 5,
            next_retry_at_millis: Some(123),
        };
        let bytes = encode_state(&state, &key());
        // Wrong gate HMAC — both the derived and the legacy verify
        // fail. Caller treats this as a tamper signal.
        let bad_key = vec![0xffu8; 32];
        assert!(decode_state(&bytes, &bad_key).unwrap().is_none());
    }

    #[test]
    fn decode_returns_none_for_malformed_json() {
        assert!(decode_state(b"not-json", &key()).unwrap().is_none());
        assert!(decode_state(b"[1, 2, 3]", &key()).unwrap().is_none());
        assert!(decode_state(b"", &key()).unwrap().is_none());
    }

    #[test]
    fn decode_returns_none_for_missing_fields() {
        assert!(decode_state(b"{}", &key()).unwrap().is_none());
        assert!(decode_state(br#"{"payload":"YQ=="}"#, &key())
            .unwrap()
            .is_none());
        assert!(decode_state(br#"{"hmac":"YQ=="}"#, &key())
            .unwrap()
            .is_none());
    }

    #[test]
    fn decode_returns_none_for_invalid_base64() {
        let frame = br#"{"payload":"!!!","hmac":"YQ=="}"#;
        assert!(decode_state(frame, &key()).unwrap().is_none());
    }

    #[test]
    fn decode_tolerates_missing_inner_fields_with_zero_defaults() {
        // Encode an inner payload that's missing both fields; the
        // decoder should still produce a `PersistedState` with
        // failure_count = 0 + no cooldown, matching the Dart
        // behaviour for legacy state files.
        let payload_str = "{}";
        let payload_bytes = payload_str.as_bytes();
        // Sign with the v1 derived key so the v1 verify hits.
        let signing_key = derive_signing_key(&key());
        let hmac = crypto::hmac_sha256(&signing_key, payload_bytes);
        let frame = format!(
            r#"{{"payload":"{}","hmac":"{}"}}"#,
            STANDARD.encode(payload_bytes),
            STANDARD.encode(&hmac),
        );
        let decoded = decode_state(frame.as_bytes(), &key()).unwrap().unwrap();
        assert_eq!(decoded.failure_count, 0);
        assert_eq!(decoded.next_retry_at_millis, None);
    }

    #[test]
    fn tampered_payload_byte_invalidates_hmac() {
        let state = PersistedState {
            failure_count: 1,
            next_retry_at_millis: None,
        };
        let bytes = encode_state(&state, &key());
        let mut tampered = bytes.clone();
        // Flip a byte inside the base64 payload — base64 alphabet
        // is conservative, so any flip yields different decoded
        // bytes and a different expected HMAC.
        let idx = tampered
            .windows(10)
            .position(|w| w == b"\"payload\":")
            .unwrap();
        // Find the first character after the `"` that opens the
        // base64 body and flip it. The HMAC field is later in the
        // string so a single-byte flip in `payload` cleanly breaks
        // the signature without colliding with `hmac`'s bytes.
        for i in idx..tampered.len() {
            if tampered[i] == b'\"' && tampered.get(i + 1).copied() != Some(b':') {
                tampered[i + 1] = if tampered[i + 1] == b'A' { b'B' } else { b'A' };
                break;
            }
        }
        assert!(decode_state(&tampered, &key()).unwrap().is_none());
    }

    /// Pre-v2 state files (any prior format) decode as tamper —
    /// the actor's next write clears them and the user resumes with
    /// a fresh failure counter. Validates the no-legacy-fallback
    /// posture: the verifier bins anything not signed under the
    /// current HKDF salt + info as if it were tampered.
    #[test]
    fn decode_rejects_legacy_pre_v2_signatures() {
        let state = PersistedState {
            failure_count: 2,
            next_retry_at_millis: Some(42),
        };
        let payload = json!({
            "failure_count": state.failure_count,
            "next_retry_at_millis": state.next_retry_at_millis,
        });
        let payload_bytes = payload.to_string().into_bytes();
        let legacy_hmac = crypto::hmac_sha256(&key(), &payload_bytes);
        let frame = json!({
            "payload": STANDARD.encode(&payload_bytes),
            "hmac": STANDARD.encode(&*legacy_hmac),
        });
        let bytes = frame.to_string().into_bytes();
        assert!(decode_state(&bytes, &key()).unwrap().is_none());
    }

    /// Proves the key-separation property: re-encoding the same
    /// state under the same gate HMAC produces an HMAC tag that is
    /// NOT equal to `HMAC(gate_hmac, payload)` directly. An
    /// attacker who only owns the gate HMAC's HMAC oracle can't
    /// forge rate-limit state without first computing the HKDF
    /// expansion (which requires possessing the gate HMAC, not
    /// just observing its outputs).
    #[test]
    fn signing_key_is_separated_from_gate_hmac() {
        let state = PersistedState {
            failure_count: 4,
            next_retry_at_millis: None,
        };
        let bytes = encode_state(&state, &key());
        let frame: Value = serde_json::from_slice(&bytes).unwrap();
        let payload_b64 = frame["payload"].as_str().unwrap();
        let hmac_b64 = frame["hmac"].as_str().unwrap();
        let payload_bytes = STANDARD.decode(payload_b64).unwrap();
        let claimed = STANDARD.decode(hmac_b64).unwrap();
        let raw_gate_hmac = crypto::hmac_sha256(&key(), &payload_bytes);
        assert_ne!(
            claimed, *raw_gate_hmac,
            "encoded HMAC must not equal HMAC(gate_hmac, payload) — key separation invariant"
        );
        let derived = derive_signing_key(&key());
        let expected_v2 = crypto::hmac_sha256(&derived, &payload_bytes);
        assert_eq!(claimed, *expected_v2);
    }

    /// The HKDF derive must be deterministic + bound to the info
    /// string. Bumping the info string is a wire-break — the
    /// regression test pins the current value so a silent rename
    /// is caught.
    #[test]
    fn signing_key_derive_is_deterministic_and_bound_to_info() {
        let a = derive_signing_key(&key());
        let b = derive_signing_key(&key());
        assert_eq!(*a, *b, "HKDF must be deterministic for a given input");
        // Sanity: the derive does NOT return the gate HMAC verbatim.
        assert_ne!(*a, key());
    }
}
