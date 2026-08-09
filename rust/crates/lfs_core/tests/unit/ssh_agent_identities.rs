/// Unit tests extracted from ssh_agent/identities.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::db::ssh_keys::KeyBackend;

fn row(id: &str, backend: KeyBackend, public_key: &str, agent_policy: AgentPolicy) -> SshKeyRow {
    SshKeyRow {
        id: id.into(),
        label: format!("label-{id}"),
        private_key: "PEM".into(),
        public_key: public_key.into(),
        key_type: "sk-ssh-ed25519@openssh.com".into(),
        is_generated: false,
        created_at_ms: 0,
        credential_id: Some(vec![1, 2, 3]),
        application_string: Some("ssh:".into()),
        has_user_verification: false,
        agent_policy,
        backend,
        pkcs11_uri: None,
        pkcs11_module_path: None,
        pkcs11_token_serial: None,
        pkcs11_object_id: None,
        pkcs11_object_label: None,
        enclave_tag: None,
        hello_credential_name: None,
        tpm_blob: None,
        tpm_handle: None,
        tpm_provider: None,
        tpm_pin_required: false,
        cng_key_name: None,
        keystore_alias: None,
        keystore_strongbox: false,
        keystore_user_auth_required: false,
        keystore_platform: None,
        imported_as_stub: false,
    }
}

/// Ed25519 OpenSSH public-key text — the bare key the cert
/// fixture below was signed against (`ssh-keygen -t ed25519`).
/// Round-tripped through `PublicKey::from_openssh` in
/// `bare_key_blob`.
const ED25519_PUB: &str = include_str!("../fixtures/ssh_agent/ed25519_user.pub");

/// OpenSSH cert text — `ssh-keygen -s ca -I user-id -n alice,bob
/// -V always:forever user.pub` against the matching CA. Generated
/// once and committed so the test does not re-run the signing
/// flow each run; the bytes are the load-bearing shape, not the
/// signing key.
const ED25519_CERT: &[u8] = include_bytes!("../fixtures/ssh_agent/ed25519_cert.pub");

#[test]
fn build_skips_software_rows() {
    let r = row("a", KeyBackend::Software, ED25519_PUB, AgentPolicy::Ask);
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert!(out.is_empty());
}

#[test]
fn build_skips_deny_policy_rows() {
    let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Deny);
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert!(out.is_empty());
}

/// FIDO2 row whose CTAP2 metadata carries the user-verification
/// bit is filtered out of the listing — the agent wire has no PIN
/// surface and publishing the row would let an external client
/// trigger a `CTAP2_ERR_PIN_REQUIRED` on every sign.
#[test]
fn build_skips_fido2_user_verification_required_rows() {
    let mut r = row("uv", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
    r.has_user_verification = true;
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert!(out.is_empty());
}

/// FIDO2 row WITHOUT user-verification is still published — the
/// filter is the UV bit, not the FIDO2 backend.
#[test]
fn build_emits_fido2_row_without_user_verification() {
    let mut r = row("touch", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
    r.has_user_verification = false;
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].comment, "label-touch");
}

#[test]
fn build_emits_bare_when_no_cert_paired() {
    let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].comment, "label-a");
    // The bare blob starts with the SSH wire-format algo string
    // — bytes 0..4 hold the algo-string length (big-endian).
    assert_eq!(&out[0].key_blob[0..4], &[0, 0, 0, 11]);
    assert_eq!(&out[0].key_blob[4..15], b"ssh-ed25519");
}

#[test]
fn build_emits_bare_then_cert_when_paired() {
    let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Always);
    let lookup = |_key_id: &str| -> Result<Option<CertRecord>, Error> {
        Ok(Some(CertRecord {
            key_id: "a".into(),
            certificate: ED25519_CERT.to_vec(),
            valid_after: 0,
            valid_before: i64::MAX,
            principals: Vec::new(),
            critical_options: std::collections::BTreeMap::new(),
            fingerprint: "SHA256:fixture".into(),
        }))
    };
    let out = build_advertised(&[r], lookup).unwrap();
    assert_eq!(out.len(), 2);
    // First entry is the bare pubkey blob, second is the cert
    // blob. Cert blob starts with the cert algorithm string
    // (`ssh-ed25519-cert-v01@openssh.com`, 32 ascii bytes).
    let cert_algo = b"ssh-ed25519-cert-v01@openssh.com";
    assert_eq!(
        &out[1].key_blob[0..4],
        &(cert_algo.len() as u32).to_be_bytes()[..]
    );
    assert_eq!(&out[1].key_blob[4..4 + cert_algo.len()], cert_algo);
}

#[test]
fn build_falls_back_to_bare_when_cert_text_unparseable() {
    // Corrupt cert text — the bare entry must survive even though
    // the cert blob slot drops.
    let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Always);
    let lookup = |_: &str| -> Result<Option<CertRecord>, Error> {
        Ok(Some(CertRecord {
            key_id: "a".into(),
            certificate: b"not a cert".to_vec(),
            valid_after: 0,
            valid_before: i64::MAX,
            principals: Vec::new(),
            critical_options: std::collections::BTreeMap::new(),
            fingerprint: "SHA256:nope".into(),
        }))
    };
    let out = build_advertised(&[r], lookup).unwrap();
    assert_eq!(out.len(), 1);
}

#[test]
fn build_skips_row_with_unparseable_public_key() {
    let mut r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
    r.public_key = "not openssh".into();
    let out = build_advertised(&[r], |_| Ok(None)).unwrap();
    assert!(out.is_empty());
}

#[test]
fn encode_msg_id_and_count_match_wire_shape() {
    let bytes = encode_identities_answer(&[]).unwrap();
    assert_eq!(bytes[0], IDENTITIES_ANSWER_MSG_ID);
    // 4 bytes of big-endian zero for nkeys=0.
    assert_eq!(&bytes[1..5], &[0, 0, 0, 0]);
}

#[test]
fn encode_writes_two_entries_with_correct_length_prefixes() {
    let entries = vec![
        Advertised {
            key_blob: vec![0xAA, 0xBB, 0xCC],
            comment: "first".into(),
        },
        Advertised {
            key_blob: vec![0x11, 0x22],
            comment: "snd".into(),
        },
    ];
    let bytes = encode_identities_answer(&entries).unwrap();
    // Header: msg_id + nkeys(=2).
    assert_eq!(bytes[0], IDENTITIES_ANSWER_MSG_ID);
    assert_eq!(&bytes[1..5], &[0, 0, 0, 2]);
    // First key_blob: u32(3) || 0xAA 0xBB 0xCC; then comment u32(5) || "first".
    assert_eq!(&bytes[5..9], &[0, 0, 0, 3]);
    assert_eq!(&bytes[9..12], &[0xAA, 0xBB, 0xCC]);
    assert_eq!(&bytes[12..16], &[0, 0, 0, 5]);
    assert_eq!(&bytes[16..21], b"first");
    // Second key_blob: u32(2) || 0x11 0x22; comment u32(3) || "snd".
    assert_eq!(&bytes[21..25], &[0, 0, 0, 2]);
    assert_eq!(&bytes[25..27], &[0x11, 0x22]);
    assert_eq!(&bytes[27..31], &[0, 0, 0, 3]);
    assert_eq!(&bytes[31..34], b"snd");
    assert_eq!(bytes.len(), 34);
}
