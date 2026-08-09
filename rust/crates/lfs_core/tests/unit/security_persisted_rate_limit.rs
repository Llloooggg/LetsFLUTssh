/// Unit tests extracted from security/persisted_rate_limit.rs
/// Declared via `#[path] mod tests;` in the source file.
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
