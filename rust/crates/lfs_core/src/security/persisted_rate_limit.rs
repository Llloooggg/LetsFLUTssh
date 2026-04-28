//! Disk-blob format owner for the L2-tier `PersistedRateLimiter`.
//!
//! `PersistedRateLimiter` (Dart) writes its exponential-backoff
//! state to `rate_limit_state.bin` under app-support so a process
//! restart between guesses does not reset the counter. The state is
//! HMAC-authenticated with a key the caller derives from the L2
//! gate's stored hash — anyone who tampers with the file without
//! also possessing the keychain pepper produces an HMAC mismatch
//! and the limiter clamps to the worst-case cooldown.
//!
//! Wire format (UTF-8 bytes on disk):
//! ```json
//! {
//!   "payload": "<base64 of inner-payload JSON>",
//!   "hmac":    "<base64 of HMAC-SHA-256(key, inner-payload bytes)>"
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
//! Tamper handling lives in [`decode_state`]: any malformed shape
//! or HMAC mismatch returns `Ok(None)` so the Dart caller treats
//! the file as "fresh state" without surfacing the parse error.
//! `Err` is reserved for cryptographic-equality assertions that
//! cannot be expressed via `Option`.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::{json, Value};

use crate::crypto;

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
#[must_use]
pub fn encode_state(state: &PersistedState, hmac_key: &[u8]) -> Vec<u8> {
    let payload = json!({
        "failure_count": state.failure_count,
        "next_retry_at_millis": state.next_retry_at_millis,
    });
    // serde_json emits a minified JSON string for `to_string`; that
    // matches the Dart `jsonEncode` behaviour on the same shape, so
    // a state file written by either side parses on the other.
    let payload_str = payload.to_string();
    let payload_bytes = payload_str.as_bytes();
    let hmac = crypto::hmac_sha256(hmac_key, payload_bytes);
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
pub fn decode_state(bytes: &[u8], hmac_key: &[u8]) -> Result<Option<PersistedState>, String> {
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
    let expected = crypto::hmac_sha256(hmac_key, &payload_bytes);
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
        // Wrong HMAC key — the file looks valid but the signature
        // does not match. Caller treats this as a tamper signal.
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
        let hmac = crypto::hmac_sha256(&key(), payload_bytes);
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
}
